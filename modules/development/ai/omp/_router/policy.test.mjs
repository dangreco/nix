import { test, expect } from "bun:test";
import { bounded, candidatesFrom, googleJudge, route, validateChoice } from "./policy.mjs";

const model = (id, extra = {}) => ({ id, provider: "proxy", name: id, input: ["text", "image"],
  contextWindow: 200000, kind: "chat", ...extra });
const choice = (key, options) => ({ type: "choice", choice: key, confidence: 0.95,
  probabilities: Object.fromEntries(Object.keys(options).map(option => [option, option === key ? 1 : 0])) });

test("only declared available chat models with sufficient context and modality are candidates", () => {
  const models = [model("new"), model("short", { contextWindow: 1000 }), model("image", { kind: "image" }),
    model("text", { input: ["text"] }), model("ambient"), model("unknown-window", { contextWindow: null })];
  const config = { providers: { proxy: { models: models.filter(m => m.id !== "ambient") } } };
  const result = candidatesFrom(config, models, { models: {} }, 3000, true);
  expect(result.map(c => c.model.id)).toEqual(["new"]);
  expect(result[0].profile.tier).toBe("unclassified");
  expect(candidatesFrom({ providers: {} }, models, { models: {} }, 0, false)).toEqual([]);
});

test("new model is considered without a researched profile and deleted models disappear", () => {
  const available = [model("existing"), model("new")];
  const profiles = { models: { "proxy/existing": { tier: "smart" } } };
  expect(candidatesFrom({ providers: { proxy: { models: [{ id: "new" }] } } }, available, profiles, 0, false)
    .map(c => c.model.id)).toEqual(["new"]);
});

test("profiles describe the exact provider/model, not a similarly named backend", () => {
  const available = [model("shared"), model("shared", { provider: "custom" })];
  const config = { providers: { proxy: { models: [{ id: "shared" }] }, custom: { models: [{ id: "shared" }] } } };
  const profile = { tier: "genius", benchmarks: [{ benchmark: "verified", score: 99 }] };
  const result = candidatesFrom(config, available, { models: { "proxy/shared": profile } }, 0, false);
  expect(result[0].profile).toEqual(profile);
  expect(result[1].profile.tier).toBe("unclassified");
  expect(result[1].profile.benchmarks).toEqual([]);
});

test("invalid distributions and unknown choices cannot select a model", () => {
  const options = { a: "a", b: "b" };
  for (const answer of [null, { ...choice("a", options), choice: "injected" },
    { ...choice("a", options), probabilities: { a: 0.2, b: 0.8 } },
    { ...choice("a", options), probabilities: { a: 1, b: 1 } },
    { ...choice("a", options), confidence: NaN },
    { ...choice("a", options), probabilities: { a: 1, b: 0, surprise: 0 } }]) {
    expect(() => validateChoice(answer, options)).toThrow();
  }
});

test("deadline bounds a hung credential resolver, aborts work, and ignores late results", async () => {
  let signal;
  await expect(bounded(s => { signal = s; return new Promise(() => {}); }, 10)).rejects.toThrow("deadline");
  expect(signal.aborted).toBe(true);
});

test("HTTP failures and malformed JSON propagate to the default-model fallback", async () => {
  const judgeModel = { baseUrl: "https://example.invalid/v1beta", id: "decision" };
  for (const status of [401, 403, 429, 500, 503]) {
    await expect(googleJudge(judgeModel, "test", async () => new Response("private error", { status }))(
      "task", {}, new AbortController().signal)).rejects.toThrow(`HTTP ${status}`);
  }
  await expect(googleJudge(judgeModel, "test", async () => new Response("not JSON"))(
    "task", {}, new AbortController().signal)).rejects.toThrow();
});

test("same tier is preferred; unavailable tier escalates before downgrading", async () => {
  const candidates = [{ model: model("smart"), profile: { tier: "smart" } },
    { model: model("dumb"), profile: { tier: "dumb" } }];
  const result = await route({ candidates, prompt: "Implement pagination", previous: "", benchmarks: {},
    judge: async (_state, question) => choice("average", question.criteria) });
  expect(result.model.id).toBe("smart");
  expect(result.requestedTier).toBe("average");
});

test("judge can select a newly declared model over a researched same-tier model", async () => {
  const candidates = [{ model: model("known"), profile: { tier: "smart", benchmarks: [] } },
    { model: model("new"), profile: { tier: "unclassified", benchmarks: [] } }];
  let calls = 0;
  const result = await route({ candidates, prompt: "Diagnose a race", previous: "", benchmarks: {},
    judge: async (_state, question) => choice(++calls === 1 ? "smart" : "m1", question.criteria) });
  expect(result.model.id).toBe("new");
});

test("priority globs restrict the chosen tier to the earliest matching group", async () => {
  const candidates = [{ model: model("claude-opus", { provider: "personal" }), profile: { tier: "smart" } },
    { model: model("glm", { provider: "personal" }), profile: { tier: "smart" } },
    { model: model("sol", { provider: "work" }), profile: { tier: "smart" } },
    { model: model("other-sol", { provider: "spare" }), profile: { tier: "smart" } },
    { model: model("claude-fable", { provider: "personal" }), profile: { tier: "genius" } },
    { model: model("claude-mini", { provider: "personal" }), profile: { tier: "dumb" } }];
  const routeTo = async (tier, priority) => {
    let pool;
    const result = await route({ candidates, prompt: "Task", previous: "", benchmarks: {}, priority,
      judge: async (_state, question) => {
        if (question.criteria.genius) return choice(tier, question.criteria);
        pool = Object.values(question.criteria).map(option => JSON.parse(option).selector);
        return choice("m0", question.criteria);
      } });
    return { selected: `${result.model.provider}/${result.model.id}`, pool };
  };
  const order = ["work/*", "personal/claude-*", "personal/glm*"];
  // Only the work model competes for smart work: the judge is not even asked.
  expect(await routeTo("smart", order)).toEqual({ selected: "work/sol", pool: undefined });
  // Capability comes first: the work provider has no genius or dumb model.
  expect((await routeTo("genius", order)).selected).toBe("personal/claude-fable");
  expect((await routeTo("dumb", order)).selected).toBe("personal/claude-mini");
  // Groups within one provider: glm outranks Claude when listed first.
  expect((await routeTo("smart", ["personal/glm*", "personal/claude-*"])).selected).toBe("personal/glm");
  // Unmatched models rank after matched ones, equally with each other.
  expect((await routeTo("smart", ["missing/*"])).pool)
    .toEqual(["personal/claude-opus", "personal/glm", "work/sol", "spare/other-sol"]);
  // No priority keeps the judge's choice across every model of the tier.
  expect((await routeTo("smart", undefined)).pool)
    .toEqual(["personal/claude-opus", "personal/glm", "work/sol", "spare/other-sol"]);
});

test("an unprofiled preferred model joins only tiers where its group has a profiled model", async () => {
  const candidates = [{ model: model("opus", { provider: "personal" }), profile: { tier: "smart" } },
    { model: model("fable", { provider: "personal" }), profile: { tier: "genius" } },
    { model: model("sol", { provider: "work" }), profile: { tier: "smart" } },
    { model: model("new", { provider: "work" }), profile: { tier: "unclassified" } }];
  const poolFor = async tier => {
    let pool;
    const result = await route({ candidates, prompt: "Task", previous: "", benchmarks: {}, priority: ["work/*"],
      judge: async (_state, question) => {
        if (question.criteria.genius) return choice(tier, question.criteria);
        pool = Object.values(question.criteria).map(option => JSON.parse(option).selector);
        return choice("m0", question.criteria);
      } });
    return pool ?? [`${result.model.provider}/${result.model.id}`];
  };
  expect(await poolFor("smart")).toEqual(["work/sol", "work/new"]);
  expect(await poolFor("genius")).toEqual(["personal/fable"]);
});

test("excluded models are never routing candidates", () => {
  const available = [model("claude-opus"), model("claude-opus-high"), model("gemini", { provider: "other" })];
  const config = { providers: { proxy: { models: [{ id: "claude-opus" }, { id: "claude-opus-high" }] }, other: { models: [{ id: "gemini" }] } } };
  const ids = exclude => candidatesFrom(config, available, { models: {}, exclude }, 0, false)
    .map(c => `${c.model.provider}/${c.model.id}`);
  expect(ids(["proxy/*-high"])).toEqual(["proxy/claude-opus", "other/gemini"]);
  expect(ids(["other/*", "proxy/claude-opus"])).toEqual(["proxy/claude-opus-high"]);
  expect(ids(undefined)).toEqual(["proxy/claude-opus", "proxy/claude-opus-high", "other/gemini"]);
});

test("uncertain task classification rejects rather than silently choosing a cheap model", async () => {
  await expect(route({ candidates: [{ model: model("cheap"), profile: { tier: "dumb" } }],
    prompt: "Change it", previous: "", benchmarks: {}, judge: async () => ({ type: "choice", choice: "dumb",
      confidence: 0.4, probabilities: { genius: 0.1, smart: 0.2, average: 0.3, dumb: 0.4 } }) })).rejects.toThrow("uncertain");
});
