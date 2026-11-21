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

test("uncertain task classification rejects rather than silently choosing a cheap model", async () => {
  await expect(route({ candidates: [{ model: model("cheap"), profile: { tier: "dumb" } }],
    prompt: "Change it", previous: "", benchmarks: {}, judge: async () => ({ type: "choice", choice: "dumb",
      confidence: 0.4, probabilities: { genius: 0.1, smart: 0.2, average: 0.3, dumb: 0.4 } }) })).rejects.toThrow("uncertain");
});
