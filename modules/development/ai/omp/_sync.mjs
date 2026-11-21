#!/usr/bin/env bun
// Synchronizes Nix-managed omp settings into ~/.omp/agent without owning the
// directory: user files (*.local.yml) are read-only inputs, native files are
// merged or regenerated, and everything is computed before the first write.
import {
  chmodSync, closeSync, existsSync, fsyncSync, lstatSync, mkdirSync, openSync,
  readFileSync, renameSync, unlinkSync, writeFileSync,
} from "node:fs";
import { randomBytes } from "node:crypto";
import { basename, dirname, join } from "node:path";
import { extendFallbackChains, mergeProfiles } from "./_router/catalog.mjs";

const SCHEMA = "https://raw.githubusercontent.com/can1357/oh-my-pi/main/packages/coding-agent/src/config/mcp-schema.json";
const STATE_FILE = ".omp-sync-state.json";
const STATE_VERSION = 1;

// Messages only ever carry file names and key locations, never file contents.
export class SyncError extends Error {}

const isObject = value => value !== null && typeof value === "object" && !Array.isArray(value);
const unique = list => [...new Set(list)];

function deepMerge(base, over) {
  if (!isObject(base) || !isObject(over)) return over;
  const out = { ...base };
  for (const [key, value] of Object.entries(over)) {
    if (key === "__proto__") continue;
    out[key] = Object.hasOwn(base, key) ? deepMerge(base[key], value) : value;
  }
  return out;
}

// Managed files may be unreadable (sops not rendered yet): that is not an error.
function readManaged(path) {
  try {
    const text = readFileSync(path, "utf8");
    return text.trim() ? text : null;
  } catch {
    return null;
  }
}

// Optional user/native files: missing is empty, anything else unreadable is an error.
function readOptional(path) {
  try {
    return readFileSync(path, "utf8");
  } catch (error) {
    if (error.code === "ENOENT" || error.code === "ENOTDIR") return null;
    throw new SyncError(`${basename(path)}: cannot be read (${error.code ?? "error"}); nothing was changed`);
  }
}

function parseYaml(text, name) {
  if (text === null || !text.trim()) return {};
  let value;
  try {
    value = Bun.YAML.parse(text);
  } catch {
    throw new SyncError(`${name}: invalid YAML; fix the file and re-run, nothing was changed`);
  }
  return value ?? {};
}

function parseJson(text, name) {
  if (text === null || !text.trim()) return {};
  try {
    return JSON.parse(text);
  } catch {
    throw new SyncError(`${name}: invalid JSON; fix the file and re-run, nothing was changed`);
  }
}

const bad = (name, what) => new SyncError(`${name}: ${what}; fix the file and re-run, nothing was changed`);

function validateModelsDoc(doc, name) {
  if (!isObject(doc)) throw bad(name, "top level must be a mapping");
  if (doc.providers === undefined) return doc;
  if (!isObject(doc.providers)) throw bad(name, "providers must be a mapping");
  for (const [provider, value] of Object.entries(doc.providers)) {
    if (!isObject(value)) throw bad(name, `providers.${provider} must be a mapping`);
    if (value.models === undefined) continue;
    if (!Array.isArray(value.models)) throw bad(name, `providers.${provider}.models must be a list`);
    const seen = new Set();
    value.models.forEach((model, index) => {
      if (!isObject(model) || typeof model.id !== "string" || !model.id)
        throw bad(name, `providers.${provider}.models[${index}] must be a mapping with a string id`);
      if (seen.has(model.id)) throw bad(name, `providers.${provider}.models[${index}] repeats an earlier model id`);
      seen.add(model.id);
    });
  }
  return doc;
}

function validateConfigDoc(doc, name) {
  if (!isObject(doc)) throw bad(name, "top level must be a mapping");
  const { extensions, retry } = doc;
  if (extensions !== undefined && (!Array.isArray(extensions) || extensions.some(item => typeof item !== "string")))
    throw bad(name, "extensions must be a list of strings");
  if (retry !== undefined) {
    if (!isObject(retry)) throw bad(name, "retry must be a mapping");
    const chains = retry.fallbackChains;
    if (chains !== undefined) {
      if (!isObject(chains)) throw bad(name, "retry.fallbackChains must be a mapping");
      for (const value of Object.values(chains))
        if (!Array.isArray(value) || value.some(item => typeof item !== "string"))
          throw bad(name, "retry.fallbackChains values must be lists of strings");
    }
  }
  return doc;
}

function validateRoutingDoc(doc, name) {
  if (!isObject(doc)) throw bad(name, "top level must be a mapping");
  for (const key of ["models", "benchmarks"])
    if (doc[key] !== undefined && !isObject(doc[key])) throw bad(name, `${key} must be a mapping`);
  return doc;
}

// Provider objects merge deeply; each provider's model list merges by id with
// the later (local) fields winning. Order: managed first, new local models after.
function mergeModels(managed, local) {
  const out = deepMerge(managed, local);
  for (const provider of Object.keys(out.providers ?? {})) {
    const first = managed.providers?.[provider]?.models;
    const second = local.providers?.[provider]?.models;
    if (first === undefined && second === undefined) continue;
    const byId = new Map();
    for (const model of [...(first ?? []), ...(second ?? [])])
      byId.set(model.id, byId.has(model.id) ? deepMerge(byId.get(model.id), model) : model);
    out.providers[provider].models = [...byId.values()];
  }
  return out;
}

function readState(path) {
  try {
    const state = JSON.parse(readFileSync(path, "utf8"));
    if (state?.version === STATE_VERSION && Array.isArray(state.extensions) && Array.isArray(state.fallbackChainKeys))
      return state;
  } catch {}
  return null;
}

// First run after the migration has no ownership manifest, so previous
// Nix-owned entries cannot be identified. Keep every live extension except an
// obsolete store copy of the managed router (a second copy would register the
// router twice), recognised by its /nix/store/.../_router/index.ts path and
// only when the managed set now contains a different router path. Other
// plugins, including old Superpowers store paths, are preserved.
const routerPath = path => path.startsWith("/nix/store/") && /(?:\/|-)_router\/index\.ts$/.test(path);

function buildConfig({ live, managed, local, catalog, state, profiles }) {
  const out = deepMerge(deepMerge(live, managed), local);

  const nixExtensions = unique([...(managed.extensions ?? []), ...(local.extensions ?? [])]);
  const owned = state ? new Set(state.extensions) : null;
  const liveExtensions = (live.extensions ?? []).filter(path =>
    !nixExtensions.includes(path) && (owned ? !owned.has(path) : !(routerPath(path) && nixExtensions.some(routerPath))));
  const extensions = unique([...nixExtensions, ...liveExtensions]);
  if (extensions.length || live.extensions !== undefined) out.extensions = extensions;

  const managedChains = managed.retry?.fallbackChains ?? {};
  const localChains = local.retry?.fallbackChains ?? {};
  let generated = managedChains;
  if (Object.keys(catalog.providers ?? {}).length) {
    generated = { ...managedChains, ...extendFallbackChains(catalog, profiles, managedChains) };
  }
  const nixChains = { ...generated, ...localChains };

  const staleKeys = new Set(state?.fallbackChainKeys ?? []);
  const kept = Object.fromEntries(Object.entries(live.retry?.fallbackChains ?? {}).filter(([key]) => !staleKeys.has(key)));
  const chains = { ...kept, ...nixChains };
  if (Object.keys(chains).length || live.retry?.fallbackChains !== undefined)
    out.retry = { ...(out.retry ?? {}), fallbackChains: chains };

  return { config: out, state: { version: STATE_VERSION, extensions: nixExtensions, fallbackChainKeys: Object.keys(nixChains).sort() } };
}

function sameFile(path, data) {
  try {
    const stat = lstatSync(path);
    return stat.isFile() && (stat.mode & 0o777) === 0o600 && readFileSync(path, "utf8") === data;
  } catch {
    return false;
  }
}

// Same-directory temp file + rename: never writes through a symlink (the link
// itself, e.g. into the store, is replaced) and readers never see a partial file.
function writeAtomic(path, data) {
  if (sameFile(path, data)) return false;
  const tmp = join(dirname(path), `.${basename(path)}.${process.pid}.${randomBytes(4).toString("hex")}.tmp`);
  let fd;
  try {
    fd = openSync(tmp, "wx", 0o600);
    writeFileSync(fd, data);
    fsyncSync(fd);
    closeSync(fd);
    fd = undefined;
    chmodSync(tmp, 0o600);
    renameSync(tmp, path);
    return true;
  } catch (error) {
    if (fd !== undefined) try { closeSync(fd); } catch {}
    try { unlinkSync(tmp); } catch {}
    throw new SyncError(`${basename(path)}: cannot be written (${error.code ?? "error"})`);
  }
}

export function sync({ agentDir, config: configSrc, models: modelsSrc = null, mcp: mcpSrc = null }) {
  if (!agentDir || !configSrc) throw new SyncError("usage: --agent-dir DIR --config FILE [--models FILE] [--mcp FILE]");
  const at = name => join(agentDir, name);
  const baseProfiles = JSON.parse(readFileSync(new URL("./_router/profiles.json", import.meta.url), "utf8"));

  // Phase 1: read and validate every input. Nothing is written here.
  const localModels = validateModelsDoc(parseYaml(readOptional(at("models.local.yml")), "models.local.yml"), "models.local.yml");
  const localConfig = validateConfigDoc(parseYaml(readOptional(at("config.local.yml")), "config.local.yml"), "config.local.yml");
  const routing = validateRoutingDoc(parseYaml(readOptional(at("routing.local.yml")), "routing.local.yml"), "routing.local.yml");
  let profiles;
  try {
    profiles = mergeProfiles(baseProfiles, routing);
  } catch {
    throw bad("routing.local.yml", "invalid routing overlay");
  }
  const liveConfig = validateConfigDoc(parseYaml(readOptional(at("config.yml")), "config.yml"), "config.yml");

  const configText = readManaged(configSrc);
  const modelsText = modelsSrc ? readManaged(modelsSrc) : null;
  const deferred = configText === null || (modelsSrc && modelsText === null);

  const writes = [];
  const report = { written: [], deferred: [] };

  // mcp.json needs no secrets, so it updates even when the templates are missing.
  if (mcpSrc) {
    const managedServers = parseJson(readManaged(mcpSrc), basename(mcpSrc));
    if (!isObject(managedServers)) throw bad(basename(mcpSrc), "top level must be a mapping");
    const live = parseJson(readOptional(at("mcp.json")), "mcp.json");
    if (!isObject(live)) throw bad("mcp.json", "top level must be a mapping");
    if (live.mcpServers !== undefined && !isObject(live.mcpServers)) throw bad("mcp.json", "mcpServers must be a mapping");
    const next = { ...live };
    next.$schema ??= SCHEMA;
    next.mcpServers = { ...(live.mcpServers ?? {}), ...managedServers };
    writes.push(["mcp.json", `${JSON.stringify(next, null, 2)}\n`]);
  }

  if (deferred) {
    report.deferred.push("config.yml", ...(modelsSrc ? ["models.yml"] : []));
  } else {
    const managedConfig = validateConfigDoc(parseYaml(configText, basename(configSrc)), basename(configSrc));
    const managedModels = modelsSrc
      ? validateModelsDoc(parseYaml(modelsText, basename(modelsSrc)), basename(modelsSrc)) : {};
    const catalog = mergeModels(managedModels, localModels);
    const state = readState(at(STATE_FILE));
    const modelsManaged = !!(Object.keys(managedModels).length || Object.keys(localModels).length || state?.modelsManaged);

    // Once adopted, an empty catalog clears the last retired model too. A user
    // with no sources and no prior ownership retains their native file.
    if (modelsManaged)
      writes.push(["models.yml", Bun.YAML.stringify(catalog, null, 2)]);

    let built;
    try {
      built = buildConfig({
        live: liveConfig, managed: managedConfig, local: localConfig, catalog, profiles,
        state,
      });
    } catch (error) {
      if (error instanceof SyncError) throw error;
      throw new SyncError("model catalog: cannot generate fallback chains from the configured models; nothing was changed");
    }
    built.state.modelsManaged = modelsManaged;
    writes.push(["config.yml", Bun.YAML.stringify(built.config, null, 2)]);
    writes.push([STATE_FILE, `${JSON.stringify(built.state)}\n`]);
  }

  // Phase 2: write. The directory is created 0700 only when missing.
  if (writes.length && !existsSync(agentDir)) mkdirSync(agentDir, { recursive: true, mode: 0o700 });
  // State last: a crash in between keeps the older (superset-safe) ownership view.
  const order = ["models.yml", "config.yml", STATE_FILE, "mcp.json"];
  for (const [name, data] of writes.sort((a, b) => order.indexOf(a[0]) - order.indexOf(b[0])))
    if (writeAtomic(at(name), data) && name !== STATE_FILE) report.written.push(name);
  return report;
}

function parseArgs(argv) {
  const flags = { "--agent-dir": "agentDir", "--config": "config", "--models": "models", "--mcp": "mcp" };
  const options = {};
  for (let i = 0; i < argv.length; i += 2) {
    const key = flags[argv[i]];
    if (!key || argv[i + 1] === undefined) throw new SyncError(`unknown or incomplete argument ${argv[i]}`);
    options[key] = argv[i + 1];
  }
  return options;
}

export function main(argv) {
  try {
    const report = sync(parseArgs(argv));
    if (report.deferred.length)
      console.error(`omp-sync-config: deferred ${report.deferred.join(", ")}: managed files not rendered yet, keeping current files`);
    return 0;
  } catch (error) {
    console.error(`omp-sync-config: ${error instanceof SyncError ? error.message : "unexpected failure; check native files before retrying"}`);
    return 1;
  }
}

if (import.meta.main) process.exit(main(process.argv.slice(2)));
