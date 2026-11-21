import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { getAgentDir } from "@oh-my-pi/pi-utils";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";
import profiles from "./profiles.json";
import { bounded, candidatesFrom, googleJudge, route, selector } from "./policy.mjs";
import { mergeProfiles } from "./catalog.mjs";

// No credentials or task text are journaled. The only persisted router data is
// the chosen route and a bounded reason, visible through /router and notifications.
// The status line shows just the route's tier emoji while routing is on.
const tierEmoji: Record<string, string> = { genius: "🧠", smart: "🤓", average: "😐", dumb: "🥴" };

export default function router(pi: ExtensionAPI) {
  let enabled = true;
  let expectedModel: string | undefined;
  let expectedEffort: string | undefined;
  let previous = "";
  let generation = 0;
  let status = "Router: ready";
  let inFlight = false;
  let running = false;
  let routingProfiles = mergeProfiles(profiles, {});

  function show(ctx: ExtensionContext, text: string, notify = false, model = expectedModel) {
    status = `Router: ${text}`;
    const tier = model ? routingProfiles.models[model]?.tier : undefined;
    ctx.ui.setStatus("model-router", enabled && tier ? tierEmoji[tier] : undefined);
    if (notify) ctx.ui.notify(status, "info");
  }
  function remember(ctx: ExtensionContext) {
    expectedModel = ctx.model && selector(ctx.model);
    expectedEffort = pi.getThinkingLevel();
  }
  const z = pi.zod;
  const catalogSchema = z.object({
    providers: z.record(z.string(), z.object({ models: z.array(z.object({ id: z.string() })).optional() })).optional(),
  });
  const settingsSchema = z.object({
    modelRoles: z.record(z.string(), z.union([z.string(), z.array(z.string())])).optional(),
  });

  async function fallback(ctx: ExtensionContext, reason: string) {
    // Resolve @default afresh: never retain yesterday's cheap route on failure.
    try {
      const primary = ctx.models.resolve("@default");
      if (primary && await pi.setModel(primary)) {
        pi.setThinkingLevel("high");
        expectedModel = selector(primary);
        expectedEffort = pi.getThinkingLevel();
        const tier = routingProfiles.models[selector(primary)]?.tier ?? "unclassified";
        show(ctx, `${tier} | ${selector(primary)} | fallback: ${reason}`, true);
        pi.appendEntry("model-router", { model: selector(primary), tier, fallback: reason });
        return;
      }
    } catch { /* An unavailable default must not mask the original route failure. */ }
    // No usable default: do not make an arbitrary downgrade. OMP's active
    // model and native retry/fallback machinery remain available.
    remember(ctx);
    show(ctx, `${expectedModel ?? "no model"} | default unavailable; kept active model (${reason})`, true);
  }

  function reset(_event: unknown, ctx: ExtensionContext) {
    generation++;
    previous = "";
    running = false;
    remember(ctx);
    const primary = ctx.models.resolve("@default");
    enabled = !primary || expectedModel === selector(primary);
    show(ctx, enabled ? "ready | /router off to pin a model" : "manual model | /router on to enable");
  }
  pi.on("session_start", reset);
  pi.on("session_switch", reset);
  pi.on("session_before_switch", () => { generation++; });
  pi.on("session_shutdown", () => { generation++; });

  pi.registerCommand("router", {
    description: "Task model router: on, off, status (default); scores and benchmark definitions are in the Nix router docs",
    handler: async (args, ctx) => {
      const action = args.trim() || "status";
      if (action === "on" || action === "off") {
        generation++;
        enabled = action === "on";
        remember(ctx);
        show(ctx, enabled ? "enabled for next task" : `off | pinned ${expectedModel}`, true);
      } else if (action === "status") ctx.ui.notify(status, "info");
      else ctx.ui.notify("Usage: /router [on|off|status]", "warning");
    },
  });

  pi.on("agent_start", () => { running = true; });
  pi.on("before_agent_start", async (event, ctx) => {
    if (ctx.agent.kind !== "main" || event.reason !== "prompt" || !event.prompt.trim()
      || !enabled || inFlight || running) return;
    // An explicit model/effort change wins. Native provider fallbacks update
    // the expected selection below, and therefore do not disable routing.
    if ((ctx.model && selector(ctx.model) !== expectedModel) || pi.getThinkingLevel() !== expectedEffort) {
      enabled = false;
      remember(ctx);
      show(ctx, `manual model | ${expectedModel} | /router on to resume`, true);
      return;
    }
    if (ctx.sessionModes?.getState().plan.status === "active") return;
    const version = ++generation;
    const startingModel = ctx.model && selector(ctx.model);
    const startingEffort = pi.getThinkingLevel();
    inFlight = true;
    show(ctx, "selecting model...");
    const stillCurrent = () => version === generation && enabled
      && (!ctx.model || selector(ctx.model) === startingModel) && pi.getThinkingLevel() === startingEffort;
    try {
      const chosen = await bounded(async signal => {
        const [catalogText, settingsText, routingText] = await Promise.all([
          readFile(join(getAgentDir(), "models.yml"), "utf8"),
          readFile(join(getAgentDir(), "config.yml"), "utf8"),
          readFile(join(getAgentDir(), "routing.local.yml"), "utf8").catch(error => {
            if (error.code === "ENOENT") return "{}";
            throw error;
          }),
        ]);
        const catalog = catalogSchema.parse(Bun.YAML.parse(catalogText));
        const settings = settingsSchema.parse(Bun.YAML.parse(settingsText));
        try {
          routingProfiles = mergeProfiles(profiles, Bun.YAML.parse(routingText) ?? {});
        } catch {
          throw new Error("invalid local routing profile");
        }
        await ctx.modelRegistry.refreshIfStale();
        if (signal.aborted) throw new Error("judge deadline exceeded");
        const judgeRole = settings.modelRoles?.judge;
        const judgeSelector = Array.isArray(judgeRole) ? judgeRole[0] : judgeRole;
        const judgeModel = ctx.modelRegistry.getAvailable("judge").find(model => selector(model) === judgeSelector);
        if (!judgeModel || judgeModel.api !== "google-decisions") throw new Error("native Gemini judge unavailable");
        const key = await ctx.modelRegistry.getApiKey(judgeModel, ctx.sessionManager.getSessionId(), { signal });
        if (!key) throw new Error("judge credentials unavailable");
        const tokens = (ctx.getContextUsage()?.tokens ?? 0) + event.prompt.length;
        const historyHasImages = ctx.sessionManager.getBranch().some(entry =>
          entry.type === "message" && Array.isArray(entry.message.content)
          && entry.message.content.some(block => block.type === "image"));
        const candidates = candidatesFrom(catalog, ctx.models.list(), routingProfiles, tokens,
          !!event.images?.length || historyHasImages);
        return route({ candidates, prompt: event.prompt, previous, benchmarks: routingProfiles.benchmarks,
          priority: routingProfiles.priority, judge: googleJudge(judgeModel, key), signal });
      });
      if (!stillCurrent()) return;
      if (!await pi.setModel(chosen.model)) throw new Error("selected model unavailable");
      const preferred = { genius: "high", smart: "high", average: "medium", dumb: "low" }[chosen.requestedTier];
      const efforts = chosen.model.thinking?.efforts ?? [];
      pi.setThinkingLevel(efforts.includes(preferred) ? preferred : efforts[0] ?? "off");
      expectedModel = selector(chosen.model);
      expectedEffort = pi.getThinkingLevel();
      const tier = chosen.profile.tier;
      const mismatch = tier !== chosen.requestedTier ? ` (task: ${chosen.requestedTier})` : "";
      show(ctx, `${tier}${mismatch} | ${expectedModel}`, true);
      pi.appendEntry("model-router", { model: expectedModel, tier, requestedTier: chosen.requestedTier });
    } catch (error) {
      if (!stillCurrent()) return;
      // Never echo provider response bodies, credentials, paths or request data.
      const message = error instanceof Error ? error.message : "";
      const safe = /^(judge HTTP \d{3}|judge deadline exceeded|native Gemini judge unavailable|judge credentials unavailable|selected model unavailable|invalid judge answer|inconsistent judge answer|uncertain task tier|no eligible configured models|unsupported candidate count|invalid local routing profile)$/.test(message)
        ? message : "routing service unavailable";
      await fallback(ctx, safe);
    } finally {
      if (version === generation) previous = event.prompt.slice(0, 8000);
      inFlight = false;
    }
  });

  pi.on("retry_fallback_applied", (event, ctx) => {
    if (ctx.agent.kind !== "main") return;
    remember(ctx);
    const model = event.to.replace(/:(off|minimal|low|medium|high|xhigh|max)$/, "");
    show(ctx, `${routingProfiles.models[model]?.tier ?? "unclassified"} | provider fallback | ${event.to}`, true, model);
  });
  pi.on("agent_end", (event, ctx) => {
    if (ctx.agent.kind !== "main") return;
    running = !!event.willContinue;
    if (!enabled) return;
    const reply = event.messages.findLast(message => message.role === "assistant");
    if (reply && Array.isArray(reply.content)) {
      previous += "\nPrevious reply: " + reply.content.filter(block => block.type === "text")
        .map(block => block.text).join("\n").slice(0, 4000);
    }
    // Do not adopt an unexplained model change: manual selection must win at
    // the next prompt. Native retry events above explicitly transfer ownership.
    if (ctx.model && selector(ctx.model) !== expectedModel) {
      show(ctx, `active | ${selector(ctx.model)}`, false, selector(ctx.model));
    }
  });
}
