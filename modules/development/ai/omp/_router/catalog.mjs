// Provider-qualified profiles and generated cross-account fallback chains.
// Pure functions: inputs are never mutated and nothing is read from disk or
// the network, so callers can validate everything before writing any file.
import { isExcluded, priorityRank, tiers } from "./policy.mjs";

const tierNames = Object.keys(tiers);
const isObject = value => value !== null && typeof value === "object" && !Array.isArray(value);
const isText = value => typeof value === "string" && value.trim() !== "";
const isCount = value => typeof value === "number" && Number.isFinite(value) && value > 0;

function fail(where, message) {
  throw new Error(`${where}: ${message}`);
}

function onlyKeys(value, allowed, where) {
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) fail(where, `unknown field ${JSON.stringify(key)}`);
  }
}

function textList(value, where) {
  if (!Array.isArray(value) || !value.every(isText)) fail(where, "must be a list of non-empty strings");
  return [...value];
}

const scoreFields = ["benchmark", "score", "unit", "setup", "source"];
const definitionFields = ["description", "caveat", "source"];
const modelFields = ["tier", "capabilities", "identityNote", "benchmarks", "sources"];

function checkDefinition(value, where) {
  if (!isObject(value)) fail(where, "must be an object");
  onlyKeys(value, definitionFields, where);
  for (const key of definitionFields) {
    if (!isText(value[key])) fail(where, `${key} must be a non-empty string`);
  }
  return Object.fromEntries(definitionFields.map(key => [key, value[key]]));
}

function checkScores(value, where, definitions) {
  if (!Array.isArray(value)) fail(where, "must be a list of benchmark scores");
  return value.map((score, index) => {
    const here = `${where}[${index}]`;
    if (!isObject(score)) fail(here, "must be an object");
    onlyKeys(score, scoreFields, here);
    for (const key of ["benchmark", "unit", "setup", "source"]) {
      if (!isText(score[key])) fail(here, `${key} must be a non-empty string`);
    }
    if (typeof score.score !== "number" || !Number.isFinite(score.score)) fail(here, "score must be a finite number");
    if (!Object.hasOwn(definitions, score.benchmark)) {
      fail(here, `benchmark ${JSON.stringify(score.benchmark)} has no definition (description, caveat, source)`);
    }
    return Object.fromEntries(scoreFields.map(key => [key, score[key]]));
  });
}

const selectorPattern = /^[^/\s]+\/\S+$/;

// Ordered provider/model globs; validated here so a typo fails before anything is written.
function checkGlobs(value, where) {
  if (!Array.isArray(value) || !value.every(glob => typeof glob === "string" && selectorPattern.test(glob))) {
    fail(where, "must be a list of provider/model globs without spaces");
  }
  if (new Set(value).size !== value.length) fail(where, "must not repeat a glob");
  return [...value];
}

// base: profiles.json (bare ids, all served by provider "llm").
// local: routing.local.yml; null/undefined (absent file) means no overrides.
// priority: provider/model globs, most preferred first; exclude: globs never
// routed to nor used as generated fallbacks. Both default to none.
// Operator entries win field by field: an entry that only sets `tier` keeps the
// remaining researched data of the same provider/id; a model for any other
// provider starts empty, so same-named llm evidence is never copied across.
export function mergeProfiles(base, local) {
  if (!isObject(base) || !isObject(base.models)) fail("profiles", "must contain a models object");
  if (base.benchmarks !== undefined && !isObject(base.benchmarks)) fail("profiles", "benchmarks must be an object");
  if (local === undefined || local === null) local = {};
  if (!isObject(local)) fail("routing.local", "must be an object");
  onlyKeys(local, ["models", "benchmarks", "priority", "exclude"], "routing.local");
  const priority = checkGlobs(local.priority ?? [], "routing.local.priority");
  const exclude = checkGlobs(local.exclude ?? [], "routing.local.exclude");
  const localModels = local.models ?? {};
  const localBenchmarks = local.benchmarks ?? {};
  if (!isObject(localModels)) fail("routing.local.models", "must be an object keyed by provider/id");
  if (!isObject(localBenchmarks)) fail("routing.local.benchmarks", "must be an object keyed by benchmark name");

  const benchmarks = new Map(Object.entries(structuredClone(base.benchmarks ?? {})));
  for (const [name, definition] of Object.entries(localBenchmarks)) {
    if (!isText(name)) fail("routing.local.benchmarks", "benchmark names must be non-empty");
    benchmarks.set(name, checkDefinition(definition, `routing.local.benchmarks.${name}`));
  }
  const definitions = Object.fromEntries(benchmarks);

  const models = new Map(Object.entries(base.models).map(([id, profile]) => [`llm/${id}`, structuredClone(profile)]));
  for (const [key, entry] of Object.entries(localModels)) {
    const where = `routing.local.models.${key}`;
    if (!selectorPattern.test(key)) fail(where, "key must be provider/id");
    if (!isObject(entry)) fail(where, "must be an object");
    onlyKeys(entry, modelFields, where);
    const existing = models.get(key);
    if (entry.tier === undefined ? !existing : !tierNames.includes(entry.tier)) {
      fail(where, existing ? `tier must be one of ${tierNames.join(", ")}` : `tier is required and must be one of ${tierNames.join(", ")}`);
    }
    for (const field of ["capabilities", "identityNote"]) {
      if (entry[field] !== undefined && !isText(entry[field])) fail(where, `${field} must be a non-empty string`);
    }
    const patch = {};
    for (const field of ["tier", "capabilities", "identityNote"]) {
      if (entry[field] !== undefined) patch[field] = entry[field];
    }
    if (entry.benchmarks !== undefined) patch.benchmarks = checkScores(entry.benchmarks, `${where}.benchmarks`, definitions);
    if (entry.sources !== undefined) patch.sources = textList(entry.sources, `${where}.sources`);
    models.set(key, {
      ...(existing ?? {
        capabilities: "No researched profile. Operator-assigned tier; use only the live declared capabilities and do not infer benchmark scores from the name.",
        identityNote: "Operator-defined profile",
        benchmarks: [],
        sources: [],
      }),
      ...patch,
    });
  }
  return { ...base, models: Object.fromEntries(models), benchmarks: definitions, priority, exclude };
}

// Unknown context is 0, not a guessed default: an undeclared candidate ranks below
// any declared one for a source with a declared window, so explicit capacity wins.
const unknownContext = 0;
const efforts = new Set(["off", "minimal", "low", "medium", "high", "xhigh", "max"]);
const preferredEffort = { genius: "high", smart: "high", average: "medium", dumb: "low" };

// Accounts behind the shared CLIProxyAPI provider. Unknown llm ids share one
// account of their own; every other provider is its own account.
function accountOf(provider, id) {
  if (provider !== "llm") return `provider:${provider}`;
  if (id.startsWith("glm-")) return "llm:zai";
  if (id.startsWith("gpt-") || id === "codex-auto-review") return "llm:chatgpt";
  if (id.startsWith("gemini-") || id.endsWith("-high")) return "llm:antigravity";
  if (id.startsWith("claude-")) return "llm:anthropic";
  return "llm:other";
}

function configuredChatModels(catalog, profiles) {
  if (catalog === undefined || catalog === null) catalog = {};
  if (!isObject(catalog)) fail("catalog", "must be an object");
  if (catalog.providers !== undefined && !isObject(catalog.providers)) fail("catalog.providers", "must be an object");
  const result = [];
  const seen = new Set();
  for (const [provider, value] of Object.entries(catalog.providers ?? {})) {
    if (!isObject(value)) fail(`catalog.providers.${provider}`, "must be an object");
    if (value.models !== undefined && !Array.isArray(value.models)) fail(`catalog.providers.${provider}.models`, "must be a list");
    for (const model of value.models ?? []) {
      const where = `catalog.providers.${provider}.models`;
      if (!isObject(model) || !isText(model.id)) fail(where, "every model needs a non-empty id");
      const here = `${where}[${model.id}]`;
      if (model.kind !== undefined && model.kind !== null && typeof model.kind !== "string") fail(here, "kind must be a string");
      // Judges, image generators and any future non-chat kind never take part.
      if ((model.kind ?? "chat") !== "chat") continue;
      if (model.contextWindow !== undefined && model.contextWindow !== null && !isCount(model.contextWindow)) {
        fail(here, "contextWindow must be a positive finite number");
      }
      if (model.input !== undefined && model.input !== null && !(Array.isArray(model.input) && model.input.every(isText))) {
        fail(here, "input must be a list of strings");
      }
      const thinking = model.thinking ?? undefined;
      if (thinking !== undefined && !isObject(thinking)) fail(here, "thinking must be an object");
      const supported = thinking?.efforts ?? [];
      if (!Array.isArray(supported) || !supported.every(isText)) fail(here, "thinking.efforts must be a list of strings");
      const selector = `${provider}/${model.id}`;
      if (seen.has(selector)) continue;
      seen.add(selector);
      const profiled = Object.hasOwn(profiles.models, selector) ? profiles.models[selector]?.tier : undefined;
      result.push({
        selector, account: accountOf(provider, model.id),
        // Catalogs declare each family newest first; equal candidates keep that order.
        index: result.length,
        // Unknown or unclassified models order as "smart": neither promoted nor demoted.
        tier: tierNames.includes(profiled) ? profiled : "smart",
        image: (model.input ?? ["text"]).includes("image"),
        context: model.contextWindow ?? unknownContext,
        efforts: supported,
      });
    }
  }
  return result;
}

const rankOf = tier => tierNames.indexOf(tier);

// Same tier first, then stronger (closest first), then weaker (closest first).
function tierDistance(source, candidate) {
  const delta = rankOf(candidate.tier) - rankOf(source.tier);
  return delta === 0 ? 0 : delta < 0 ? -delta : tierNames.length + delta;
}

// Same tier, then enough context (declared short beats undeclared), then the
// earlier declared (newest) model.
function compareFor(source) {
  const shortfall = candidate => candidate.context >= source.context ? 0 : candidate.context === unknownContext ? 20 : 10;
  const score = candidate => 100 * tierDistance(source, candidate) + shortfall(candidate);
  return (a, b) => score(a) - score(b) || a.index - b.index;
}

function suffixFor(model) {
  if (!model.efforts.length) return "";
  const preferred = preferredEffort[model.tier];
  return `:${model.efforts.includes(preferred) ? preferred : model.efforts[0]}`;
}

// catalog: models.yml shape ({providers:{name:{models:[{id,...}]}}}).
// profiles: mergeProfiles() result. existingChains: selector -> [selector[:effort]].
// Returns selector -> chain for every configured chat model. Existing entries
// keep their order (even selectors this catalog does not declare, which are
// never dropped) unless profiles.exclude matches them; one best candidate is
// appended for each account the chain does not yet reach. Models of the same
// account, excluded models, the source itself and selectors already present are
// never appended. profiles.priority then stably reorders the whole chain. No
// compatible alternative yields an unchanged (possibly empty) chain. Explicit
// operator chains are layered over the result by the caller.
export function extendFallbackChains(catalog, profiles, existingChains) {
  if (profiles === undefined || profiles === null) profiles = { models: {} };
  if (!isObject(profiles) || !isObject(profiles.models)) fail("profiles", "must contain a models object");
  const chains = existingChains ?? {};
  if (!isObject(chains)) fail("existingChains", "must be an object");
  for (const [key, chain] of Object.entries(chains)) {
    if (!Array.isArray(chain) || !chain.every(isText)) fail(`existingChains.${key}`, "must be a list of selector strings");
  }
  const models = configuredChatModels(catalog, profiles);
  const known = new Set(models.map(model => model.selector));
  // provider/id[:effort]; ids may contain ":" so an exact catalog match wins.
  const modelOf = selector => {
    if (known.has(selector)) return selector;
    const colon = selector.lastIndexOf(":");
    return colon > 0 && efforts.has(selector.slice(colon + 1)) ? selector.slice(0, colon) : selector;
  };
  const accountOfSelector = selector => {
    const slash = selector.indexOf("/");
    return slash > 0 ? accountOf(selector.slice(0, slash), selector.slice(slash + 1)) : undefined;
  };

  const excluded = selector => isExcluded(profiles.exclude, modelOf(selector));
  const targets = models.filter(model => !excluded(model.selector));
  const sources = new Set(models.map(model => model.selector));
  const entries = models.map(source => {
    const existing = (chains[source.selector] ?? []).filter(item => !excluded(item));
    const taken = new Set([source.selector, ...existing.map(modelOf)]);
    const covered = new Set([source.account, ...existing.map(item => accountOfSelector(modelOf(item)))]);
    const compare = compareFor(source);
    const added = [...new Set(targets.map(model => model.account))]
      .filter(account => !covered.has(account))
      .map(account => targets
        .filter(model => model.account === account && !taken.has(model.selector) && (!source.image || model.image))
        .sort(compare)[0])
      .filter(Boolean)
      .sort(compare);
    const chain = [...existing, ...added.map(model => `${model.selector}${suffixFor(model)}`)];
    return [source.selector, chain.sort((a, b) =>
      priorityRank(profiles.priority, modelOf(a)) - priorityRank(profiles.priority, modelOf(b)))];
  });
  const untouched = Object.entries(chains).filter(([key]) => !sources.has(key)).map(([key, chain]) => [key, [...chain]]);
  return Object.fromEntries([...entries, ...untouched]);
}
