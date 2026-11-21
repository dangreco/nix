import { test, expect } from "bun:test";
import { extendFallbackChains, mergeProfiles } from "./catalog.mjs";

const score = (benchmark, value = 50) => ({ benchmark, score: value, unit: "% accuracy", setup: "vendor run", source: "https://example.test/eval" });
const definition = { description: "Agentic tasks.", caveat: "Vendor harness.", source: "https://example.test/bench" };
const base = () => ({
  researchedAt: "2026-11-21", policy: "operator policy",
  benchmarks: { Bench: definition },
  models: {
    "claude-opus-5-5": { tier: "smart", capabilities: "1M context", identityNote: "Anthropic id", sources: ["https://a.test"], benchmarks: [score("Bench", 70)] },
    "gpt-6.1-sol": { tier: "smart", capabilities: "400K context", identityNote: "OpenAI id", sources: [], benchmarks: [] },
  },
});

test("base ids become llm-qualified and other providers never inherit same-id evidence", () => {
  const input = base();
  const snapshot = structuredClone(input);
  const merged = mergeProfiles(input, { models: { "proxy/claude-opus-5-5": { tier: "dumb" } } });
  expect(Object.keys(merged.models)).toEqual(["llm/claude-opus-5-5", "llm/gpt-6.1-sol", "proxy/claude-opus-5-5"]);
  expect(merged.models["llm/claude-opus-5-5"]).toEqual(snapshot.models["claude-opus-5-5"]);
  const custom = merged.models["proxy/claude-opus-5-5"];
  expect(custom.tier).toBe("dumb");
  expect(custom.benchmarks).toEqual([]);
  expect(custom.sources).toEqual([]);
  expect(custom.capabilities).not.toContain("1M");
  expect(merged.policy).toBe("operator policy");
  expect(merged.researchedAt).toBe("2026-11-21");
  expect(input).toEqual(snapshot);
});

test("absent or empty local routing only qualifies the base", () => {
  for (const local of [undefined, null, {}, { models: {}, benchmarks: {} }]) {
    const merged = mergeProfiles(base(), local);
    expect(Object.keys(merged.models)).toEqual(["llm/claude-opus-5-5", "llm/gpt-6.1-sol"]);
    expect(merged.benchmarks).toEqual({ Bench: definition });
  }
});

test("local tier override of a built-in keeps the remaining researched profile", () => {
  const merged = mergeProfiles(base(), { models: { "llm/claude-opus-5-5": { tier: "genius" } } });
  expect(merged.models["llm/claude-opus-5-5"]).toEqual({ ...base().models["claude-opus-5-5"], tier: "genius" });
  const noteOnly = mergeProfiles(base(), { models: { "llm/gpt-6.1-sol": { identityNote: "Mine" } } });
  expect(noteOnly.models["llm/gpt-6.1-sol"]).toEqual({ ...base().models["gpt-6.1-sol"], identityNote: "Mine" });
});

test("custom models carry tier, capabilities, sources and benchmark evidence with definitions", () => {
  const merged = mergeProfiles(base(), {
    benchmarks: { Mine: { description: "Internal suite.", caveat: "Not comparable.", source: "internal wiki" } },
    models: { "local/qwen": { tier: "average", capabilities: "Runs locally", identityNote: "GGUF", sources: ["https://q.test"], benchmarks: [score("Mine", 12.5), score("Bench", 3)] } },
  });
  expect(merged.benchmarks.Mine.caveat).toBe("Not comparable.");
  expect(merged.benchmarks.Bench).toEqual(definition);
  expect(merged.models["local/qwen"]).toEqual({ tier: "average", capabilities: "Runs locally", identityNote: "GGUF", sources: ["https://q.test"], benchmarks: [score("Mine", 12.5), score("Bench", 3)] });
  // Local definition replaces a built-in one of the same name.
  const replaced = mergeProfiles(base(), { benchmarks: { Bench: { ...definition, caveat: "Mine" } } });
  expect(replaced.benchmarks.Bench.caveat).toBe("Mine");
  // Local scores replace the built-in list for that model only when provided.
  const rescored = mergeProfiles(base(), { models: { "llm/claude-opus-5-5": { benchmarks: [score("Bench", 1)] } } });
  expect(rescored.models["llm/claude-opus-5-5"].benchmarks).toEqual([score("Bench", 1)]);
});

test("invalid local routing throws", () => {
  const bad = [
    "text", [], { extra: 1 }, { models: [] }, { benchmarks: [] },
    { models: { noslash: { tier: "smart" } } }, { models: { "/id": { tier: "smart" } } }, { models: { "p/": { tier: "smart" } } },
    { models: { "p/x": null } }, { models: { "p/x": {} } }, { models: { "p/x": { tier: "godlike" } } },
    { models: { "llm/claude-opus-5-5": { tier: "unclassified" } } },
    { models: { "p/x": { tier: "smart", capabilities: "" } } }, { models: { "p/x": { tier: "smart", typo: 1 } } },
    { models: { "p/x": { tier: "smart", sources: "https://a.test" } } }, { models: { "p/x": { tier: "smart", sources: [1] } } },
    { models: { "p/x": { tier: "smart", benchmarks: {} } } },
    { models: { "p/x": { tier: "smart", benchmarks: [score("Missing")] } } },
    { models: { "p/x": { tier: "smart", benchmarks: [{ ...score("Bench"), score: NaN }] } } },
    { models: { "p/x": { tier: "smart", benchmarks: [{ ...score("Bench"), score: Infinity }] } } },
    { models: { "p/x": { tier: "smart", benchmarks: [{ ...score("Bench"), score: "70" }] } } },
    ...["unit", "setup", "source"].map(field => ({ models: { "p/x": { tier: "smart", benchmarks: [{ ...score("Bench"), [field]: "" }] } } })),
    ...["description", "caveat", "source"].map(field => ({ benchmarks: { New: { ...definition, [field]: undefined } } })),
    { benchmarks: { New: "text" } }, { benchmarks: { New: { ...definition, extra: 1 } } },
  ];
  for (const local of bad) expect(() => mergeProfiles(base(), local)).toThrow();
  expect(() => mergeProfiles(null, {})).toThrow();
  expect(() => mergeProfiles({ benchmarks: {} }, {})).toThrow();
  expect(() => mergeProfiles({ models: {}, benchmarks: [] }, {})).toThrow();
});

test("priority and exclude are lists of unique provider/model globs", () => {
  for (const local of [{}, { priority: [], exclude: [] }]) {
    const merged = mergeProfiles(base(), local);
    expect(merged.priority).toEqual([]);
    expect(merged.exclude).toEqual([]);
  }
  const local = { priority: ["work/*", "llm/claude-*"], exclude: ["llm/*-high"] };
  const merged = mergeProfiles(base(), local);
  expect(merged.priority).toEqual(["work/*", "llm/claude-*"]);
  expect(merged.exclude).toEqual(["llm/*-high"]);
  local.priority.push("late/*");
  expect(merged.priority).toEqual(["work/*", "llm/claude-*"]);
  for (const field of ["priority", "exclude"]) {
    for (const value of ["work/*", [""], ["work/*", "work/*"], ["work"], ["/x"], [" work/x"], ["work/x y"], [1]]) {
      expect(() => mergeProfiles(base(), { [field]: value })).toThrow();
    }
  }
});

// ---- fallback chains ----

const vision = ["text", "image"];
const levels = ["low", "medium", "high", "xhigh", "max"];
const m = (id, extra = {}) => ({ id, input: vision, contextWindow: 200000, thinking: { efforts: levels }, ...extra });
const catalog = () => ({
  providers: {
    llm: { models: [
      m("claude-opus-5-5", { contextWindow: 1000000 }),
      m("claude-sonnet-5-5", { contextWindow: 1000000 }),
      m("claude-haiku-5-5", { thinking: { efforts: ["low", "medium", "high"] } }),
      m("claude-opus-5-5-high", { thinking: { efforts: ["low", "medium", "high"] } }),
      m("gpt-6.1-sol", { contextWindow: 400000 }),
      m("gpt-6.1-terra", { contextWindow: 400000, thinking: { efforts: ["low", "medium", "high"] } }),
      m("gemini-3-flash", { contextWindow: 1000000, thinking: { efforts: ["minimal", "low", "medium", "high"] } }),
      m("glm-5", { input: ["text"], thinking: { efforts: ["low", "high", "max"] } }),
      { id: "gpt-image-2", kind: "image", input: vision },
    ] },
    google: { models: [{ id: "gemini-judge", kind: "judge", input: ["text"] }] },
  },
});
const tiersOf = {
  "claude-opus-5-5": "smart", "claude-sonnet-5-5": "average", "claude-haiku-5-5": "dumb", "claude-opus-5-5-high": "smart",
  "gpt-6.1-sol": "smart", "gpt-6.1-terra": "average", "gemini-3-flash": "average", "glm-5": "average",
};
const profiles = (extra = {}) => ({ models: { ...Object.fromEntries(Object.entries(tiersOf).map(([id, tier]) => [`llm/${id}`, { tier }])), ...extra } });
const strip = selector => selector.replace(/:(off|minimal|low|medium|high|xhigh|max)$/, "");

test("four proxy accounts: every chat model reaches every other account, once, without judges or images", () => {
  const chains = extendFallbackChains(catalog(), profiles(), {});
  expect(Object.keys(chains)).toEqual(Object.keys(tiersOf).map(id => `llm/${id}`));
  const account = id => /^glm-/.test(id) ? "zai" : /^gpt-/.test(id) ? "chatgpt" : /^gemini-|-high$/.test(id) ? "antigravity" : "anthropic";
  for (const [source, chain] of Object.entries(chains)) {
    const ids = chain.map(item => strip(item).slice(4));
    const own = account(source.slice(4));
    expect(ids).not.toContain(source.slice(4));
    expect(new Set(ids).size).toBe(ids.length);
    expect(ids.map(account).includes(own)).toBe(false);
    expect(new Set(ids.map(account)).size).toBe(ids.length);
    for (const id of ids) expect(id).not.toMatch(/image|judge/);
    // Text-only glm has no vision-compatible peer for image sources; all other accounts are reached.
    const expected = ["anthropic", "antigravity", "chatgpt", "zai"].filter(a => a !== own && !(a === "zai" && source !== "llm/glm-5"));
    expect(ids.map(account).sort()).toEqual(expected.sort());
  }
  expect(chains["llm/claude-opus-5-5"]).toEqual(["llm/claude-opus-5-5-high:high", "llm/gpt-6.1-sol:high"]);
  expect(chains["llm/glm-5"]).toEqual(["llm/claude-sonnet-5-5:medium", "llm/gpt-6.1-terra:medium", "llm/gemini-3-flash:medium"]);
});

test("same tier beats stronger, stronger beats weaker, weaker is the last resort", () => {
  const catalogue = {
    providers: {
      src: { models: [{ id: "a" }] },
      p1: { models: [{ id: "strong" }, { id: "weak" }, { id: "same" }] },
      p2: { models: [{ id: "weak" }, { id: "strong" }] },
      p3: { models: [{ id: "weakest" }, { id: "weak" }] },
    },
  };
  const tierMap = { "src/a": "average", "p1/strong": "smart", "p1/weak": "dumb", "p1/same": "average", "p2/weak": "dumb", "p2/strong": "genius", "p3/weakest": "dumb", "p3/weak": "dumb" };
  const chains = extendFallbackChains(catalogue, { models: Object.fromEntries(Object.entries(tierMap).map(([k, tier]) => [k, { tier }])) }, {});
  expect(chains["src/a"]).toEqual(["p1/same", "p2/strong", "p3/weakest"]);
  // Weaker tiers: average beats dumb for a smart source; closest stronger wins over farther.
  const smart = extendFallbackChains({ providers: { src: { models: [{ id: "a" }] }, p: { models: [{ id: "dumb" }, { id: "avg" }] } } },
    { models: { "src/a": { tier: "smart" }, "p/dumb": { tier: "dumb" }, "p/avg": { tier: "average" } } }, {});
  expect(smart["src/a"]).toEqual(["p/avg"]);
  const stronger = extendFallbackChains({ providers: { src: { models: [{ id: "a" }] }, p: { models: [{ id: "gen" }, { id: "smart" }] } } },
    { models: { "src/a": { tier: "average" }, "p/gen": { tier: "genius" }, "p/smart": { tier: "smart" } } }, {});
  expect(stronger["src/a"]).toEqual(["p/smart"]);
});

test("image sources only get image-capable targets; text sources may get either", () => {
  const catalogue = { providers: {
    src: { models: [{ id: "eyes", input: vision }, { id: "text" }] },
    p: { models: [{ id: "blind" }, { id: "sighted", input: vision }] },
    q: { models: [{ id: "blind" }] },
  } };
  const chains = extendFallbackChains(catalogue, { models: {} }, {});
  expect(chains["src/eyes"]).toEqual(["p/sighted"]);
  expect(chains["src/text"]).toEqual(["p/blind", "q/blind"]);
  expect(chains["q/blind"]).toEqual(["src/eyes", "p/blind"]);
});

test("missing context is never preferred over explicit sufficient context", () => {
  const pick = (source, targets) => extendFallbackChains({ providers: {
    src: { models: [source] }, p: { models: targets },
  } }, { models: {} }, {})["src/a"];
  // Declared source window: explicit sufficient capacity beats an undeclared candidate regardless of order.
  expect(pick({ id: "a", contextWindow: 200000 }, [{ id: "a" }, { id: "z", contextWindow: 200000 }])).toEqual(["p/z"]);
  expect(pick({ id: "a", contextWindow: 200000 }, [{ id: "z", contextWindow: 200000 }, { id: "a" }])).toEqual(["p/z"]);
  // Exactly sufficient (boundary) is sufficient; one token short loses to it, and still ranks above undeclared.
  expect(pick({ id: "a", contextWindow: 200000 }, [{ id: "a", contextWindow: 199999 }, { id: "z", contextWindow: 200000 }])).toEqual(["p/z"]);
  expect(pick({ id: "a", contextWindow: 200000 }, [{ id: "a" }, { id: "z", contextWindow: 199999 }])).toEqual(["p/z"]);
  // Undeclared source: nothing is insufficient, so ties go to declaration order.
  expect(pick({ id: "a" }, [{ id: "a" }, { id: "z", contextWindow: 1000 }])).toEqual(["p/a"]);
  expect(pick({ id: "a" }, [{ id: "z" }, { id: "a" }])).toEqual(["p/z"]);
});

test("enough context is preferred and equal candidates go to the newest, declared first", () => {
  const enough = extendFallbackChains({ providers: {
    src: { models: [{ id: "a", contextWindow: 500000 }] },
    p: { models: [{ id: "small", contextWindow: 100000 }, { id: "big", contextWindow: 600000 }] },
    q: { models: [{ id: "tight", contextWindow: 100000 }, { id: "stronger", contextWindow: 900000 }] },
  } }, { models: { "q/tight": { tier: "smart" }, "q/stronger": { tier: "genius" }, "src/a": { tier: "smart" }, "p/small": { tier: "smart" }, "p/big": { tier: "smart" } } }, {});
  // p: same tier with enough context. q: short same-tier (+10) still beats stronger (+100).
  expect(enough["src/a"]).toEqual(["p/big", "q/tight"]);
  // Catalogs list each family newest first: an equally short newer model beats an older, larger one.
  const newest = extendFallbackChains({ providers: {
    src: { models: [{ id: "a", contextWindow: 1050000 }] },
    p: { models: [{ id: "claude-opus-5-5", contextWindow: 1000000 }, { id: "claude-opus-4-6", contextWindow: 1000000 }] },
    q: { models: [{ id: "gpt-6-luna", contextWindow: 272000 }, { id: "gpt-5.6-luna", contextWindow: 372000 }] },
  } }, { models: {} }, {});
  expect(newest["src/a"]).toEqual(["p/claude-opus-5-5", "q/gpt-6-luna"]);
  const unknown = { providers: { src: { models: [{ id: "a" }] }, p: { models: [{ id: "b" }, { id: "a" }] } } };
  expect(extendFallbackChains(unknown, { models: {} }, {})["src/a"]).toEqual(["p/b"]);
});

test("priority orders whole chains and excluded models are dropped and replaced", () => {
  const catalogue = catalog();
  catalogue.providers.work = { models: [m("sol", { contextWindow: 1000000 })] };
  const ranked = {
    ...profiles(),
    priority: ["work/*", "llm/claude-*", "llm/gpt-*", "llm/glm-*", "llm/gemini-*"],
    exclude: ["llm/*-high"],
  };
  const existing = { "llm/claude-opus-5-5": ["llm/claude-opus-5-5-high:high", "llm/gpt-6.1-sol:high"] };
  const chains = extendFallbackChains(catalogue, ranked, existing);
  // The excluded antigravity model leaves; Gemini covers that account; work moves to the front.
  expect(chains["llm/claude-opus-5-5"]).toEqual(["work/sol:high", "llm/gpt-6.1-sol:high", "llm/gemini-3-flash:medium"]);
  expect(chains["work/sol"]).toEqual(["llm/claude-opus-5-5:high", "llm/gpt-6.1-sol:high", "llm/gemini-3-flash:medium"]);
  expect(Object.values(chains).flat().some(item => strip(item).endsWith("-high"))).toBe(false);
  // Without priority or exclusions, existing entries keep their order.
  expect(extendFallbackChains(catalogue, profiles(), existing)["llm/claude-opus-5-5"].slice(0, 2)).toEqual(existing["llm/claude-opus-5-5"]);
});

test("custom providers with minimal fields are sources and targets; no thinking suffix without efforts", () => {
  const catalogue = catalog();
  catalogue.providers.proxy = { models: [{ id: "m1" }, { id: "m2", thinking: { efforts: [] } }, { id: "m3", thinking: { mode: "budget" } }] };
  const chains = extendFallbackChains(catalogue, profiles(), {});
  // Default input is text only, so image sources never target it.
  expect(Object.values(chains).flat().some(item => item.startsWith("proxy/"))).toBe(true);
  expect(chains["llm/claude-opus-5-5"].some(item => item.startsWith("proxy/"))).toBe(false);
  expect(chains["llm/glm-5"].filter(item => item.startsWith("proxy/"))).toEqual(["proxy/m1"]);
  expect(chains["llm/glm-5"].at(-1)).toBe("proxy/m1");
  // Unclassified sources order as smart with unknown (0) context; one candidate per account.
  expect(chains["proxy/m1"]).toEqual([
    "llm/claude-opus-5-5:high", "llm/claude-opus-5-5-high:high", "llm/gpt-6.1-sol:high", "llm/glm-5:low",
  ]);
  expect(chains["proxy/m2"]).toEqual(chains["proxy/m1"].map(item => item));
  // Same provider is one account: m1/m2/m3 never chain to each other.
  for (const id of ["m1", "m2", "m3"]) expect(chains[`proxy/${id}`].some(item => item.startsWith("proxy/"))).toBe(false);
  expect(Object.keys(chains)).toContain("proxy/m3");
});

test("existing chains keep order and unknown selectors; only uncovered accounts are appended", () => {
  const existing = {
    "llm/claude-opus-5-5": ["llm/gpt-6.1-terra:low", "native/odd:high"],
    "native/odd": ["x/y"],
    "llm/gpt-image-2": ["llm/gpt-6.1-sol"],
  };
  const snapshot = structuredClone(existing);
  const chains = extendFallbackChains(catalog(), profiles(), existing);
  expect(chains["llm/claude-opus-5-5"]).toEqual(["llm/gpt-6.1-terra:low", "native/odd:high", "llm/claude-opus-5-5-high:high"]);
  expect(chains["native/odd"]).toEqual(["x/y"]);
  expect(chains["llm/gpt-image-2"]).toEqual(["llm/gpt-6.1-sol"]);
  expect(existing).toEqual(snapshot);
  // A chain that already reaches every account is untouched; effort suffix is ignored when matching.
  const full = { "llm/glm-5": ["llm/gpt-6.1-sol:max", "llm/claude-opus-5-5:low", "llm/gemini-3-flash"] };
  expect(extendFallbackChains(catalog(), profiles(), full)["llm/glm-5"]).toEqual(full["llm/glm-5"]);
  // A chain naming the source or duplicates is preserved verbatim and never extended with them.
  const odd = extendFallbackChains(catalog(), profiles(), { "llm/glm-5": ["llm/glm-5:low"] })["llm/glm-5"];
  expect(odd[0]).toBe("llm/glm-5:low");
  expect(odd.slice(1).map(strip)).not.toContain("llm/glm-5");
});

test("model ids containing a colon are matched exactly before effort parsing", () => {
  const catalogue = { providers: { a: { models: [{ id: "x" }] }, b: { models: [{ id: "qwen3:8b" }, { id: "qwen3" }] } } };
  const chains = extendFallbackChains(catalogue, { models: {} }, { "a/x": ["b/qwen3:8b"] });
  expect(chains["a/x"]).toEqual(["b/qwen3:8b"]);
});

test("empty catalogs and sources without alternatives return empty chains", () => {
  expect(extendFallbackChains({}, { models: {} }, {})).toEqual({});
  expect(extendFallbackChains(undefined, undefined, undefined)).toEqual({});
  expect(extendFallbackChains({ providers: {} }, { models: {} }, null)).toEqual({});
  expect(extendFallbackChains({ providers: { only: { models: [{ id: "a" }, { id: "b" }] } } }, { models: {} }, {}))
    .toEqual({ "only/a": [], "only/b": [] });
  expect(extendFallbackChains({ providers: { x: { models: [{ id: "j", kind: "judge" }] }, y: { models: [{ id: "a" }] } } }, { models: {} }, {}))
    .toEqual({ "y/a": [] });
});

test("duplicate declarations collapse and wrong shapes throw", () => {
  const dup = { providers: { a: { models: [{ id: "x" }, { id: "x" }] }, b: { models: [{ id: "y" }] } } };
  expect(extendFallbackChains(dup, { models: {} }, {})["a/x"]).toEqual(["b/y"]);
  const bad = [
    [[], {}, {}], [{ providers: [] }, {}, {}], [{ providers: { a: [] } }, {}, {}], [{ providers: { a: { models: {} } } }, {}, {}],
    [{ providers: { a: { models: [{}] } } }, {}, {}], [{ providers: { a: { models: [null] } } }, {}, {}],
    [{ providers: { a: { models: [{ id: "x", contextWindow: "big" }] } } }, {}, {}],
    [{ providers: { a: { models: [{ id: "x", contextWindow: -1 }] } } }, {}, {}],
    [{ providers: { a: { models: [{ id: "x", input: "text" }] } } }, {}, {}],
    [{ providers: { a: { models: [{ id: "x", thinking: { efforts: "high" } }] } } }, {}, {}],
    [{ providers: { a: { models: [{ id: "x", thinking: [] }] } } }, {}, {}],
    [{ providers: { a: { models: [{ id: "x", kind: 1 }] } } }, {}, {}],
    [{ providers: {} }, [], {}], [{ providers: {} }, { models: [] }, {}],
    [{ providers: {} }, {}, []], [{ providers: {} }, {}, { "a/x": "b/y" }], [{ providers: {} }, {}, { "a/x": [1] }],
  ];
  for (const [catalogue, profile, chains] of bad) {
    expect(() => extendFallbackChains(catalogue, profile.models === undefined && !Array.isArray(profile) ? { models: {} } : profile, chains)).toThrow();
  }
});
