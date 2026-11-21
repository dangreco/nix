# OMP task routing

Enabled for Dan and Work with `my.omp.router.enable = true`; requires OMP 19.1.0 or later.
Like OMP itself, activation requires both host and user `my.omp.enable`. Disabled
hosts do not evaluate fallback assertions or require OMP secret placeholders.
The module appends `_router/index.ts` to the configured extensions without replacing
Superpowers or other user extensions. Activate the Nix/Home Manager configuration,
then start a new OMP session. No credentials are stored in the extension or Nix store.

Dan and Work use the same Google judge key, encrypted separately in their own
SOPS files; judge quota and revocation are therefore shared. Their proxy keys and
user-owned local configuration files remain separate.

## Managed rules

`_rules/worktrees.md` is linked to `~/.omp/agent/rules/worktrees.md` as an
always-apply rule, so subagents get it too. It tells agents to manage git worktrees
only with worktrunk (`wt`), using `<ticket>-<slug>` branch names. Worktree placement
(`<repo>/.worktrees/<branch>`), automatic `wt step prune` and the global `.worktrees/`
ignore come from `modules/development/worktrees`, which covers every user on every
host. Add your own rules as other files in `~/.omp/agent/rules/`.

## Local customization without Nix edits

Every enabled OMP user gets `omp-sync-config`. Keep customizations in these
user-owned files under `~/.omp/agent/`:

| File | Purpose |
|---|---|
| `models.local.yml` | Add providers/models or override fields of an existing provider/model. |
| `config.local.yml` | Override settings and roles, add plugins, or specify exact fallback chains. |
| `routing.local.yml` | Assign custom model tiers/capabilities, optionally supply sourced benchmark evidence, and set model priority/exclusions. |

Nix, Home Manager and `omp-config.service` **never rewrite these files**. They live
inside the already-persisted `.omp` directory, so they survive impermanence reboots.
Do not put them in the Nix repository. Use mode `0600` when they contain private
configuration; prefer credential indirection instead of plaintext API keys.

After editing, run:

```sh
omp-sync-config
```

Then start a new OMP session to load changed settings/plugins/fallback chains.
No Nix edit, rebuild or Home Manager switch is needed. Activation runs the same
command automatically. The default target is `~/.omp/agent`; advanced users can
pass `--agent-dir PATH` to compose another profile with the same managed defaults.
Routing metadata itself is reread on each task.

### Example: a local model

If an Ollama server already serves `qwen3:8b`, add this to `models.local.yml`.
Set context/output limits to those actually supported by your running server:

```yaml
providers:
  personal:
    api: openai-completions
    baseUrl: http://127.0.0.1:11434/v1
    apiKey: ollama
    models:
      - id: qwen3:8b
        name: Personal Qwen
        reasoning: false
        input: [text]
        contextWindow: 32768
        maxTokens: 8192
```

For an authenticated remote endpoint, use its API, URL and exact model ID.
OMP accepts an environment-variable name as `apiKey`, or a command such as
`apiKey: "!cat ~/.config/omp/personal-api-key"`. The sync command preserves that
expression; OMP resolves it at runtime. Missing environment variables fall back
to the literal string, so command-backed credentials are preferable when an
unset variable should fail closed.
[Upstream credential resolution](https://raw.githubusercontent.com/can1357/oh-my-pi/main/packages/coding-agent/src/config/resolve-config-value.ts).

Optionally describe the model in `routing.local.yml`:

```yaml
models:
  personal/qwen3:8b:
    tier: average
    capabilities: "Local text-only model for bounded edits. Operator-assigned tier, not measured benchmark equivalence."
    benchmarks: []
    sources: []
```

Profiles are keyed by the **full `provider/model` selector**. A similarly named
model on another provider does not inherit the proxy's benchmark scores. A new
profile needs a tier; an override of an existing researched profile only needs
the fields being changed. Omit the profile entirely to keep the model eligible
as `unclassified`, without invented benchmark evidence.

Optional score entries use `benchmark`, numeric `score`, `unit`, `setup` and
`source`. Each referenced benchmark must have a definition under top-level
`benchmarks`, with `description`, `caveat` and `source`. Existing glossary names
can be reused only for the exact same benchmark/version/setup interpretation.
Local evidence is operator-supplied, not independently verified. Descriptions
and scores are sent to the decision model; do not put secrets in them.

### Priority and exclusions

To prefer some models over others, or to stop using some entirely, list
`provider/model` globs in `routing.local.yml` (`*` matches anything). The
provider is the key under `providers` in `models.yml`:

```yaml
priority: [personal/*, llm/claude-*, llm/gpt-*]
exclude: [llm/claude-*-high]
```

`priority` is most preferred first; a model takes the position of the first glob
it matches, and unmatched models rank after all matched ones, equally.

- **Task routing:** capability still comes first. The judge picks the task tier
  and the tier fallback as usual. Within that tier, only the earliest priority
  group with a **profiled** model there competes; the judge chooses among that
  group's models. If the group has no eligible model in the tier (none declared,
  or excluded by context or image needs), the next group is used. An unprofiled
  model competes only alongside its own group's profiled models in that tier, so
  it cannot draw work from tiers its group has no profiled model in: profile it
  to make it count.
- **Generated fallback chains** are reordered (stably) by the same priority, so
  preferred models are tried first.
- **`exclude`d models** are never routed to, are removed from generated chains,
  and are never picked to cover an account; another model of that account is
  used instead. You can still select them by hand, and explicit
  `retry.fallbackChains` in `config.local.yml` are left as written.

Empty or missing lists keep the default behavior.

### Settings, plugins and fallback policy

`config.local.yml` uses OMP's normal settings shape. For example:

```yaml
theme:
  dark: nord
```

Add plugin paths to its `extensions` list; those are combined with the managed
extensions, not substituted for them. The plugin files must exist. Plugins
added directly to live `config.yml` also survive activation. Managed plugins
still require changing their Nix option to disable them.

Fallback chains are composed from the **merged catalog**, including local
providers as both sources and targets. The four proxy accounts remain distinct;
each other provider name is treated as another account. The generator selects
compatible alternatives using tiers, image support and declared context capacity.
Unprofiled models use conservative `smart` ordering for fallbacks, but remain
`unclassified` in routing. Unknown capacity is not assumed sufficient.

Usually no manual chains are needed. To take full control, set
`retry.fallbackChains` in `config.local.yml`: keys are source `provider/model`
selectors, values are ordered lists of target selectors with optional `:effort`.
Each local entry **replaces that source's entire generated chain**, including
when the value is `[]`. You are responsible for its compatibility and account
coverage. Other sources retain generated chains. Normal `retry.enabled`,
`retry.modelFallback` and `retry.fallbackOn` settings still apply.

Distinct provider names do not prove independent infrastructure or credentials.
Use a genuinely separate endpoint/account to protect against a proxy-wide outage;
two names pointing at the same proxy are not independent backups.

### Ownership and merge rules

- `models.yml` is generated from **Nix + `models.local.yml`**, not from the previous
  generated file. Provider objects merge deeply; model lists merge by `id`;
  local fields win. Other arrays replace. Removing a Nix model removes it unless
  it is explicitly declared locally. Removing the last adopted catalog clears
  it too. With no model sources and no prior ownership, an existing native
  `models.yml` is left alone.
- Put durable model additions in `models.local.yml`, **not directly in
  `models.yml`**. Before adopting this setup, move any existing hand-written
  additions to the local file. Do not copy the entire generated catalog there
  unless you intend to pin every managed model yourself.
- Settings precedence is **live `config.yml` < Nix defaults < `config.local.yml`**.
  Objects merge, arrays/scalars replace, except the additive plugin list and
  per-selector fallback-chain policy above. Removing an ordinary local-only
  setting does not erase its previously written live value; remove it from both
  files when you want OMP's own default again.
- `.omp-sync-state.json` tracks owned plugin paths, chain keys and catalog
  ownership, not provider credentials. It lets upgrades remove obsolete managed
  plugin paths and retired chains without deleting unrelated runtime additions.
  Keep this file with the agent directory. On first migration, unidentified
  existing plugins/chains are preserved; known old router paths are removed to
  avoid loading two routers. An old Superpowers path cannot be reliably identified
  without prior state, so remove any unwanted old copy once by hand.
- MCP behavior is unchanged: servers added through `/mcp add` survive activation.
- Local input parsing and structural validation finish before any native file is
  written. Invalid input fails visibly and leaves native files unchanged; OMP
  still validates its complete provider/settings schema when loading them.
  Native files use atomic replacement at mode `0600`; local inputs are never
  chmodded or rewritten. The packaged command serializes concurrent syncs.
- If managed sops templates are not available yet, config/model updates are
  deferred without overwriting existing files. The login service retries after
  sops renders them; MCP can update independently.

## Selection

At each new top-level task, the extension rereads the active profile's `models.yml`
and intersects explicitly declared models with OMP's available **chat** models.
It refreshes the registry when the file changes. Image/judge runners, disabled or
unauthenticated models, insufficient context windows, and models unable to accept
images already in the conversation are excluded. It reserves 8,192 context tokens
and conservatively counts the new prompt's characters in addition to OMP's current
context estimate. This is a guard, not exact tokenization; OMP still owns compaction.

Gemini Decision 1 first chooses a task tier, then chooses among eligible models in
that tier. If the tier has no candidates, stronger tiers are considered before
weaker tiers. An optional `priority` narrows that tier's choice to the most
preferred group (see [Priority and exclusions](#priority-and-exclusions)). New models
without researched profiles remain eligible, explicitly labelled `unclassified`;
missing benchmark evidence is never treated as zero.
An unknown model's capabilities come from the live registry, not its name.

| Tier | Reference class | Intended work | Requested effort |
|---|---|---|---|
| genius | Fable-like | Unusually difficult novel research and deep multi-system reasoning | high |
| smart | Opus-like | Architecture, ambiguous diagnosis, concurrency, security, interacting invariants | high |
| average | Sonnet-like | Bounded implementation, tests, routine review/debugging | medium |
| dumb | Haiku-like | Mechanical edits, lookups, straightforward explanations/transforms | low |

These are **operator policy labels**, not claims of measured equivalence. Supported
effort levels constrain the request; when the preferred level is unavailable the
model's lowest supported level is used. Research scores often use higher effort
and are not promises about the router's chosen effort.

Routing happens before the model request, not on each tool iteration. Subagents,
revived subagents, active plan mode, and work delivered during a running task are
not rerouted. The prior task and last assistant reply provide bounded follow-up
context. Up to 24,000 characters of the current task and 8,000 characters of prior
context are sent to Google's Decisions API, alongside public model profiles.
The extension does not independently read repository files or send image bytes;
expanded prompts may already contain attached file contents. This is additional
Google API traffic even when the selected chat model is on another provider.

## Failure and manual controls

Both judge calls, catalog reads, registry refresh and credential lookup share a
**4-second deadline**. Missing credentials/model, HTTP errors (including quota),
network failure, invalid JSON, invalid or inconsistent choice distributions, and
unknown model choices all take the same fallback path. A task-tier probability
below 0.60 also falls back. Model-choice probability is not thresholded: equivalent
models can legitimately split that distribution.

On routing failure the extension resolves `@default` afresh and switches to it
with high effort. It never deliberately keeps a cheaper previous route just because
the judge failed. If the default itself cannot be selected, the UI explicitly says
so and keeps the current model, leaving OMP's inference recovery available. If
there are no usable chat credentials anywhere, routing cannot manufacture access.

Inference failure is separate: `llm.nix` supplies baseline chains covering all four
proxy accounts for every declared proxy chat model. `omp-sync-config` extends these
with compatible local providers and creates chains for custom models as well.
Same-tier replacements come first, then stronger, then weaker tiers when an account
lacks an equivalent. Image support is preserved; within a tier sufficient declared
context is preferred, and remaining ties go to the model declared first in the
catalog: declare each family newest first, as `llm.nix` does. `priority` then
reorders each generated chain and `exclude` removes models from it (see
[Priority and exclusions](#priority-and-exclusions)). A smaller-window fallback can
still require OMP compaction or be unusable for a very large conversation. The four
proxy accounts share one CLIProxyAPI endpoint: only a genuinely independent local
provider can cover that proxy/tunnel outage. Explicit local chains take precedence,
as described above.

OMP handles inference retries, cooldowns, signed reasoning and fallback restoration.
Transient provider errors can first spend time in the provider SDK's own retry loop;
the router's 4-second deadline bounds classification, not chat inference. An injected
503 inference outage exhausted a 30-second smoke deadline before OMP's fallback,
whereas an injected 401 immediately walked the cross-account chain.

- `/router status` (or `/router`): current route/fallback explanation.
- `/router off`: pin the current model; OMP's ordinary inference fallbacks still work.
- `/router on`: resume routing at the next task.
- Explicit startup `--model` different from `@default` starts with routing off.
- A later manual model/effort change is preserved and suspends routing on the next task.
- Controls are session-local, not persisted preferences. New sessions reset them.

While routing is on, the status line shows the active route's tier as an emoji just
before the model: 🧠 genius, 🤓 smart, 😐 average, 🥴 dumb. omp separates every
segment, so it reads `π > 🤓 > [high] Opus 5.5`. There is no emoji while routing is
off or the active model has no tier. To do this, the module sets a custom
`statusLine`: omp's `default` preset with a `status` segment before `model`, and
`showHookStatus: false` so extension statuses no longer get a footer line. Your own
`my.omp.settings.statusLine` or `config.local.yml` still overrides it.
Notifications and `/router status` give the full text, `Router: <tier> | <provider/model>`.
A judge failure adds `fallback: <reason>`. Native inference failovers show the actual
replacement and its tier, including any cross-tier change. The ordinary model chip
also follows OMP's active model. Router journal entries contain only model/tier and
sanitized failure reason, never credentials or task text. Direct Decisions API calls
are not currently included in OMP's built-in model-usage/cost ledger; Google bills
input tokens even though Decisions generates zero output tokens.

## Capability and benchmark evidence

Research snapshot: **2026-11-21**. `_router/profiles.json` contains all 44 chat-model
profiles, exact numeric observations, units, run/setup notes, source URLs and
benchmark definitions. It is a checked-in snapshot, not a live benchmark scraper.
Model membership is dynamic; researched evidence and policy tiers are maintained
separately. Every routing request includes benchmark explanations and setup caveats.
Live configured context/modality/effort limits take precedence over published API
specifications. Public API prices are not subscription quota prices.

Use scores as task-relevant evidence, **not a single sorted leaderboard**. Effort,
agent harness, tools, timeout, benchmark version, safeguards and grading change
results. Vendor runs and independent runs are labelled separately. For example,
Anthropic reports Opus 5.5 Terminal-Bench 4.0 at 66.4%, while Artificial Analysis
reports 59.6%; neither is silently substituted for the other. Intelligence Index
v4.1, v4.1.1 and v5.0.1 are not interchangeable.

Proxy caveats:

- Antigravity Claude `-high` variants have no independent measurements; base Claude
  scores are not copied onto them.
- Coding Plan maps `glm-5.2` and `glm-5.1` to GLM-5.3, and `glm-5-turbo` and `glm-4.7`
  to GLM-5.3-Flash. Their policy tiers follow the documented backend; original-name
  benchmarks are not attached to those aliases.
- Exact Coding Plan mappings for `glm-5`, `glm-4.6`, `glm-4.5`, and `glm-4.5-air`
  remain unverified. Their tiers are provisional and their scores are omitted.
- `codex-auto-review` has unresolved backend identity, and
  `gemini-3.8-flash-tiered` has no directly attributable published scores.
- Research raised a near-term retirement warning for Opus 4.5 (2026-11-24).
  This change does not remove catalog entries; inference fallback covers a rejection.

### Current policy assignments

| Model ID | Tier | Evidence note |
|---|---|---|
| `claude-fable-5` | genius | 7 sourced observations |
| `claude-fable-5-1` | genius | 7 sourced observations |
| `claude-opus-5-5` | smart | 14 sourced observations |
| `claude-opus-5` | smart | 10 sourced observations |
| `claude-opus-4-8` | smart | 4 sourced observations |
| `claude-opus-4-7` | smart | 1 sourced observations |
| `claude-opus-4-6` | smart | 2 sourced observations |
| `claude-opus-4-5-20251101` | smart | 1 sourced observations |
| `claude-sonnet-5-5` | average | 9 sourced observations |
| `claude-sonnet-5` | average | 8 sourced observations |
| `claude-sonnet-4-6` | average | 3 sourced observations |
| `claude-haiku-5-5` | dumb | 8 sourced observations |
| `claude-haiku-4-5-20251001` | dumb | 6 sourced observations |
| `claude-opus-5-5-high` | smart | No directly attributable numeric scores |
| `claude-sonnet-5-5-high` | average | No directly attributable numeric scores |
| `gpt-6.2-astra` | genius | 3 sourced observations |
| `gpt-6.2-sol` | smart | 3 sourced observations |
| `gpt-6.1-sol` | smart | 1 sourced observations |
| `gpt-6.1-terra` | average | 2 sourced observations |
| `gpt-6-astra` | genius | 5 sourced observations |
| `gpt-6-sol` | average | 5 sourced observations |
| `gpt-6-luna` | dumb | 2 sourced observations |
| `gpt-5.6-sol` | smart | 3 sourced observations |
| `gpt-5.6-terra` | average | 3 sourced observations |
| `gpt-5.6-luna` | dumb | 2 sourced observations |
| `codex-auto-review` | average | No directly attributable numeric scores |
| `gemini-4-argon-high` | smart | 9 sourced observations |
| `gemini-4-hydrogen-xhigh` | average | 7 sourced observations |
| `gemini-4-neon-xhigh` | smart | 15 sourced observations |
| `gemini-3.8-flash-high` | average | 7 sourced observations |
| `gemini-3.8-flash-tiered` | average | No directly attributable numeric scores |
| `gemini-3-flash` | average | 2 sourced observations |
| `gemini-3.5-flash-lite` | dumb | 6 sourced observations |
| `gemini-3.1-flash-lite` | dumb | 3 sourced observations |
| `glm-5.3` | smart | 13 sourced observations |
| `glm-5.3-flash` | average | 4 sourced observations |
| `glm-5.2` | smart | Backend alias: glm-5.3 |
| `glm-5.1` | smart | Backend alias: glm-5.3 |
| `glm-5-turbo` | average | Backend alias: glm-5.3-flash |
| `glm-5` | average | No directly attributable numeric scores |
| `glm-4.7` | average | Backend alias: glm-5.3-flash |
| `glm-4.6` | average | No directly attributable numeric scores |
| `glm-4.5` | average | No directly attributable numeric scores |
| `glm-4.5-air` | dumb | No directly attributable numeric scores |

## Benchmark glossary

Each name below matches the exact label used in the score rows. Variants are kept
separate even when they share a family description. Percentages generally mean
success/accuracy; Elo and composite index points have their own scales. Consult
the score row for units and the precise run conditions.

### AA-3D Elo

Human-judged blind preference for interactive 3D experiences.

**Caveat:** Elo from one AA run; small sample. The score row preserves the exact reported version, units, setup and source.

[Source](https://artificialanalysis.ai/articles/openai-has-the-2-model-in-the-intelligence-index-with-the-release-of-gpt-6-2-astra-and-gpt-6-2-sol)

### AA-Briefcase

Long-horizon knowledge work Elo (AA).

**Caveat:** Version v1.1 for current models. The score row preserves the exact reported version, units, setup and source.

[Source](https://artificialanalysis.ai/articles/claude-opus-5-5)

### AA-Briefcase v1.1

Long-horizon knowledge work Elo (AA).

**Caveat:** Version v1.1 for current models. The score row preserves the exact reported version, units, setup and source.

[Source](https://artificialanalysis.ai/articles/claude-opus-5-5)

### AA-Robotics v0.1

AA research-preview robotics planning and action tasks.

**Caveat:** Research preview, task set still expanding per AA. The score row preserves the exact reported version, units, setup and source.

[Source](https://artificialanalysis.ai/articles/openai-has-the-2-model-in-the-intelligence-index-with-the-release-of-gpt-6-2-astra-and-gpt-6-2-sol)

### Agents' Last Exam

Agentic exam benchmark; Z.AI uses ALE-CLI (105 tasks, Claude Code harness).

**Caveat:** Names vary across vendors (Agents' Last Exam v1.1, Agents' Last Exam ALE-CLI, Agent's Last Exam pass rate). Compare only within the same name and version. The score row preserves the exact reported version, units, setup and source.

[Source](https://z.ai/blog/glm-5.3)

### Agents' Last Exam ALE-CLI

Agentic exam benchmark; Z.AI uses ALE-CLI (105 tasks, Claude Code harness).

**Caveat:** Names vary across vendors (Agents' Last Exam v1.1, Agents' Last Exam ALE-CLI, Agent's Last Exam pass rate). Compare only within the same name and version. The score row preserves the exact reported version, units, setup and source.

[Source](https://z.ai/blog/glm-5.3)

### Agents' Last Exam v1.1

Agentic exam benchmark; Z.AI uses ALE-CLI (105 tasks, Claude Code harness).

**Caveat:** Names vary across vendors (Agents' Last Exam v1.1, Agents' Last Exam ALE-CLI, Agent's Last Exam pass rate). Compare only within the same name and version. The score row preserves the exact reported version, units, setup and source.

[Source](https://z.ai/blog/glm-5.3)

### Artificial Analysis Coding Agent Index

AA coding harness index (DeepSWE, Terminal-Bench v2, SWE-Atlas-QnA in the July article).

**Caveat:** Version and harness changed between reports. Only compare within one article. The score row preserves the exact reported version, units, setup and source.

[Source](https://artificialanalysis.ai/articles/gpt-5-6-has-landed)

### Artificial Analysis Intelligence Index

Composite measure of general reasoning, knowledge and agentic work across the suites in that index version; index points are not percent accuracy.

**Caveat:** Versions differ: v4.1 (GPT-5.6 article, July 2026), v4.1.1 (OpenAI table), v5.0.1 (current AA model pages). Scores across versions are not comparable. AA reports max effort unless noted. The score row preserves the exact reported version, units, setup and source.

[Source](https://artificialanalysis.ai/evaluations/artificial-analysis-intelligence-index)

### Artificial Analysis Intelligence Index v4.1

Composite measure of general reasoning, knowledge and agentic work across the suites in that index version; index points are not percent accuracy.

**Caveat:** Versions differ: v4.1 (GPT-5.6 article, July 2026), v4.1.1 (OpenAI table), v5.0.1 (current AA model pages). Scores across versions are not comparable. AA reports max effort unless noted. The score row preserves the exact reported version, units, setup and source.

[Source](https://artificialanalysis.ai/evaluations/artificial-analysis-intelligence-index)

### Artificial Analysis Intelligence Index v4.1.1

Composite measure of general reasoning, knowledge and agentic work across the suites in that index version; index points are not percent accuracy.

**Caveat:** Versions differ: v4.1 (GPT-5.6 article, July 2026), v4.1.1 (OpenAI table), v5.0.1 (current AA model pages). Scores across versions are not comparable. AA reports max effort unless noted. The score row preserves the exact reported version, units, setup and source.

[Source](https://artificialanalysis.ai/evaluations/artificial-analysis-intelligence-index)

### Artificial Analysis Intelligence Index v5

Composite measure of general reasoning, knowledge and agentic work across the suites in that index version; index points are not percent accuracy.

**Caveat:** Versions differ: v4.1 (GPT-5.6 article, July 2026), v4.1.1 (OpenAI table), v5.0.1 (current AA model pages). Scores across versions are not comparable. AA reports max effort unless noted. The score row preserves the exact reported version, units, setup and source.

[Source](https://artificialanalysis.ai/evaluations/artificial-analysis-intelligence-index)

### Artificial Analysis Intelligence Index v5.0.1

Composite measure of general reasoning, knowledge and agentic work across the suites in that index version; index points are not percent accuracy.

**Caveat:** Versions differ: v4.1 (GPT-5.6 article, July 2026), v4.1.1 (OpenAI table), v5.0.1 (current AA model pages). Scores across versions are not comparable. AA reports max effort unless noted. The score row preserves the exact reported version, units, setup and source.

[Source](https://artificialanalysis.ai/evaluations/artificial-analysis-intelligence-index)

### AutomationBench

End-to-end business workflow pass rate.

**Caveat:** Opus 5 card says 26.0, Opus 5.5 card says 26.9 for the same model. The score row preserves the exact reported version, units, setup and source.

[Source](https://www-cdn.anthropic.com/fc1b44717c85dc068bc6ba5024219938094694bd/Claude%20Opus%205.5%20System%20Card.pdf)

### AutomationBench 1.0.6

End-to-end business workflow pass rate.

**Caveat:** Opus 5 card says 26.0, Opus 5.5 card says 26.9 for the same model. The score row preserves the exact reported version, units, setup and source.

[Source](https://www-cdn.anthropic.com/fc1b44717c85dc068bc6ba5024219938094694bd/Claude%20Opus%205.5%20System%20Card.pdf)

### AutomationBench v1.0.6

End-to-end business workflow pass rate.

**Caveat:** Opus 5 card says 26.0, Opus 5.5 card says 26.9 for the same model. The score row preserves the exact reported version, units, setup and source.

[Source](https://www-cdn.anthropic.com/fc1b44717c85dc068bc6ba5024219938094694bd/Claude%20Opus%205.5%20System%20Card.pdf)

### AutomationBench-AA

End-to-end business workflow pass rate.

**Caveat:** Opus 5 card says 26.0, Opus 5.5 card says 26.9 for the same model. The score row preserves the exact reported version, units, setup and source.

[Source](https://www-cdn.anthropic.com/fc1b44717c85dc068bc6ba5024219938094694bd/Claude%20Opus%205.5%20System%20Card.pdf)

### Chartography

Visual chart recognition.

**Caveat:** No tools. The score row preserves the exact reported version, units, setup and source.

[Source](https://www.anthropic.com/claude-sonnet-5-5)

### CursorBench

Multi-file ambiguous coding tasks from real Cursor sessions.

**Caveat:** Versions 3.2 and 4.0 are not comparable. The score row preserves the exact reported version, units, setup and source.

[Source](https://www.anthropic.com/claude-sonnet-5-5)

### CursorBench 3.2.0

Multi-file ambiguous coding tasks from real Cursor sessions.

**Caveat:** Versions 3.2 and 4.0 are not comparable. The score row preserves the exact reported version, units, setup and source.

[Source](https://www.anthropic.com/claude-sonnet-5-5)

### CursorBench 4.0

Multi-file ambiguous coding tasks from real Cursor sessions.

**Caveat:** Versions 3.2 and 4.0 are not comparable. The score row preserves the exact reported version, units, setup and source.

[Source](https://www.anthropic.com/claude-sonnet-5-5)

### CursorBench 4.1

Multi-file ambiguous coding tasks from real Cursor sessions.

**Caveat:** Versions 3.2 and 4.0 are not comparable. The score row preserves the exact reported version, units, setup and source.

[Source](https://www.anthropic.com/claude-sonnet-5-5)

### CyberGym

Vulnerability discovery from white-box source (1,507 tasks for Z.AI).

**Caveat:** Z.AI harness with no web tools; setup differs from other cyber benchmarks. The score row preserves the exact reported version, units, setup and source.

[Source](https://z.ai/blog/glm-5.3)

### DeepSWE v1.1

Long-horizon software engineering in real codebases.

**Caveat:** OpenAI-reported launch numbers at max effort; not independently run here. The score row preserves the exact reported version, units, setup and source.

[Source](https://deepswe.datacurve.ai/)

### ExploitBench

Turning known V8/Chrome vulnerabilities into code execution.

**Caveat:** Measured without production safeguards; results may be inflated by public historical vulnerabilities. The score row preserves the exact reported version, units, setup and source.

[Source](https://openai.com/index/gpt-6-astra/)

### FrontierCode 1.1 (Main)

Whether an agent's code change would be merged (Cognition).

**Caveat:** Effort-dependent; rows vary by effort level. The score row preserves the exact reported version, units, setup and source.

[Source](https://www.anthropic.com/claude-sonnet-5-5)

### FrontierCode 1.1 (Main), Max

Whether an agent's code change would be merged (Cognition).

**Caveat:** Effort-dependent; rows vary by effort level. The score row preserves the exact reported version, units, setup and source.

[Source](https://www.anthropic.com/claude-sonnet-5-5)

### FrontierCode 1.1 (Main), Xhigh

Whether an agent's code change would be merged (Cognition).

**Caveat:** Effort-dependent; rows vary by effort level. The score row preserves the exact reported version, units, setup and source.

[Source](https://www.anthropic.com/claude-sonnet-5-5)

### FrontierCode 2.0

Long-horizon software-engineering benchmarks. FrontierCode 2.0 (Google) and FrontierSWE v2 (Google Argon) are not the same as Z.AI's FrontierSWE (Proximal dominance score).

**Caveat:** Names overlap across vendors. Do not merge rows. The score row preserves the exact reported version, units, setup and source.

[Source](https://z.ai/blog/glm-5.3)

### FrontierSWE

Long-horizon software-engineering benchmarks. FrontierCode 2.0 (Google) and FrontierSWE v2 (Google Argon) are not the same as Z.AI's FrontierSWE (Proximal dominance score).

**Caveat:** Names overlap across vendors. Do not merge rows. The score row preserves the exact reported version, units, setup and source.

[Source](https://z.ai/blog/glm-5.3)

### FrontierSWE v2

Long-horizon software-engineering benchmarks. FrontierCode 2.0 (Google) and FrontierSWE v2 (Google Argon) are not the same as Z.AI's FrontierSWE (Proximal dominance score).

**Caveat:** Names overlap across vendors. Do not merge rows. The score row preserves the exact reported version, units, setup and source.

[Source](https://z.ai/blog/glm-5.3)

### GDM-MRCR v2 (8-needle)

Long-context multi-needle retrieval.

**Caveat:** Report by context bucket (128k average, 1M pointwise). The score row preserves the exact reported version, units, setup and source.

[Source](https://deepmind.google/models/model-cards/gemini-3-1-flash-lite/)

### GDP.PDF

Expert PDF document comprehension benchmark.

**Caveat:** Different row from the Gemini 3.8 Flash card's GDP.PDF (same name, different run). The score row preserves the exact reported version, units, setup and source.

[Source](https://artificialanalysis.ai/articles/gemini-4-neon-intelligence-gain)

### GDP.pdf

Expert PDF document comprehension benchmark.

**Caveat:** Different row from the Gemini 3.8 Flash card's GDP.PDF (same name, different run). The score row preserves the exact reported version, units, setup and source.

[Source](https://artificialanalysis.ai/articles/gemini-4-neon-intelligence-gain)

### GDPval-AA

Artificial Analysis Elo on real professional tasks.

**Caveat:** v2 vs v2.1 vs earlier versions are not comparable. The score row preserves the exact reported version, units, setup and source.

[Source](https://artificialanalysis.ai/evaluations/gdpval-aa)

### GDPval-AA v2

Artificial Analysis Elo on real professional tasks.

**Caveat:** v2 vs v2.1 vs earlier versions are not comparable. The score row preserves the exact reported version, units, setup and source.

[Source](https://artificialanalysis.ai/evaluations/gdpval-aa)

### GDPval-AA v2.1

Artificial Analysis Elo on real professional tasks.

**Caveat:** v2 vs v2.1 vs earlier versions are not comparable. The score row preserves the exact reported version, units, setup and source.

[Source](https://artificialanalysis.ai/evaluations/gdpval-aa)

### GraphWalks

Long-context graph traversal (BFS F1) at stated context lengths.

**Caveat:** Context-length bucket matters (128k vs 256k-1M). The score row preserves the exact reported version, units, setup and source.

[Source](https://deepmind.google/models/model-cards/gemini-4-neon/)

### HLE w/ Tools

Humanity's Last Exam variants.

**Caveat:** Tool access, subsets and judge differ. Do not merge. The score row preserves the exact reported version, units, setup and source.

[Source](https://z.ai/blog/glm-5.3)

### HLE-Diamond

Humanity's Last Exam variants.

**Caveat:** Tool access, subsets and judge differ. Do not merge. The score row preserves the exact reported version, units, setup and source.

[Source](https://z.ai/blog/glm-5.3)

### HLE-Verified

Humanity's Last Exam variants.

**Caveat:** Tool access, subsets and judge differ. Do not merge. The score row preserves the exact reported version, units, setup and source.

[Source](https://z.ai/blog/glm-5.3)

### HealthBench Professional

Healthcare professional evaluation.

**Caveat:** Single Anthropic table. The score row preserves the exact reported version, units, setup and source.

[Source](https://www-cdn.anthropic.com/fc1b44717c85dc068bc6ba5024219938094694bd/Claude%20Opus%205.5%20System%20Card.pdf)

### Humanity's Last Exam

Humanity's Last Exam variants.

**Caveat:** Tool access, subsets and judge differ. Do not merge. The score row preserves the exact reported version, units, setup and source.

[Source](https://z.ai/blog/glm-5.3)

### MRCR v2 (8-needle, 1M)

Long-context multi-needle retrieval.

**Caveat:** Report by context bucket (128k average, 1M pointwise). The score row preserves the exact reported version, units, setup and source.

[Source](https://deepmind.google/models/model-cards/gemini-3-1-flash-lite/)

### OSWorld 2.0

Computer-use benchmarks.

**Caveat:** Versions and subsets differ (offline subset, partial score, batch tools). Do not merge. The score row preserves the exact reported version, units, setup and source.

[Source](https://deepmind.google/models/model-cards/gemini-4-hydrogen/)

### OSWorld 2.0 offline (partial)

Computer-use benchmarks.

**Caveat:** Versions and subsets differ (offline subset, partial score, batch tools). Do not merge. The score row preserves the exact reported version, units, setup and source.

[Source](https://deepmind.google/models/model-cards/gemini-4-hydrogen/)

### OSWorld 2.1

Computer-use benchmarks.

**Caveat:** Versions and subsets differ (offline subset, partial score, batch tools). Do not merge. The score row preserves the exact reported version, units, setup and source.

[Source](https://deepmind.google/models/model-cards/gemini-4-hydrogen/)

### OSWorld 2.1 (offline subset)

Computer-use benchmarks.

**Caveat:** Versions and subsets differ (offline subset, partial score, batch tools). Do not merge. The score row preserves the exact reported version, units, setup and source.

[Source](https://deepmind.google/models/model-cards/gemini-4-hydrogen/)

### OSWorld-2.0

Computer-use benchmarks.

**Caveat:** Versions and subsets differ (offline subset, partial score, batch tools). Do not merge. The score row preserves the exact reported version, units, setup and source.

[Source](https://deepmind.google/models/model-cards/gemini-4-hydrogen/)

### OSWorld-2.1

Computer-use benchmarks.

**Caveat:** Versions and subsets differ (offline subset, partial score, batch tools). Do not merge. The score row preserves the exact reported version, units, setup and source.

[Source](https://deepmind.google/models/model-cards/gemini-4-hydrogen/)

### OSWorld-Verified

Computer-use benchmarks.

**Caveat:** Versions and subsets differ (offline subset, partial score, batch tools). Do not merge. The score row preserves the exact reported version, units, setup and source.

[Source](https://deepmind.google/models/model-cards/gemini-4-hydrogen/)

### SWE-Bench Pro (Public)

Harder real-repository SWE-bench variant.

**Caveat:** Not comparable to Verified. The score row preserves the exact reported version, units, setup and source.

[Source](https://assets.claude.com/b514064af1408018e64b1ad24e7d5e75850b4ffd.pdf)

### SWE-bench Multilingual

Real repository issue resolution across multiple programming languages; broader language coverage than the Python-focused Verified set.

**Caveat:** Vendor-reported runs; harness not comparable across vendors. The score row preserves the exact reported version, units, setup and source.

[Source](https://docs.z.ai/guides/llm/glm-5.2)

### SWE-bench Pro

Harder real-repository SWE-bench variant.

**Caveat:** Not comparable to Verified. The score row preserves the exact reported version, units, setup and source.

[Source](https://assets.claude.com/b514064af1408018e64b1ad24e7d5e75850b4ffd.pdf)

### SWE-bench Verified

500 human-verified GitHub issue fixes.

**Caveat:** Many models saturated; prompt modifications change scores. The score row preserves the exact reported version, units, setup and source.

[Source](https://assets.claude.com/b514064af1408018e64b1ad24e7d5e75850b4ffd.pdf)

### SWE-bench Verified (prompt-modified)

500 human-verified GitHub issue fixes.

**Caveat:** Many models saturated; prompt modifications change scores. The score row preserves the exact reported version, units, setup and source.

[Source](https://assets.claude.com/b514064af1408018e64b1ad24e7d5e75850b4ffd.pdf)

### Terminal-Bench 2.0

Agentic multi-step tasks in a terminal: coding, debugging, tooling and system operations. Score is successful task completion; each version is a different task set.

**Caveat:** Compare only the same benchmark version, harness, effort, time budget and scoring policy. Vendor and independent runs differ. The score row preserves the exact reported version, units, setup and source.

[Source](https://www.anthropic.com/claude-sonnet-5-5)

### Terminal-Bench 2.1

Agentic multi-step tasks in a terminal: coding, debugging, tooling and system operations. Score is successful task completion; each version is a different task set.

**Caveat:** Compare only the same benchmark version, harness, effort, time budget and scoring policy. Vendor and independent runs differ. The score row preserves the exact reported version, units, setup and source.

[Source](https://www.anthropic.com/claude-sonnet-5-5)

### Terminal-Bench 3.0

Agentic multi-step tasks in a terminal: coding, debugging, tooling and system operations. Score is successful task completion; each version is a different task set.

**Caveat:** Compare only the same benchmark version, harness, effort, time budget and scoring policy. Vendor and independent runs differ. The score row preserves the exact reported version, units, setup and source.

[Source](https://www.anthropic.com/claude-sonnet-5-5)

### Terminal-Bench 4.0

Agentic multi-step tasks in a terminal: coding, debugging, tooling and system operations. Score is successful task completion; each version is a different task set.

**Caveat:** Compare only the same benchmark version, harness, effort, time budget and scoring policy. Vendor and independent runs differ. The score row preserves the exact reported version, units, setup and source.

[Source](https://www.anthropic.com/claude-sonnet-5-5)

### Terminal-Bench 4.0 (Artificial Analysis run)

Agentic multi-step tasks in a terminal: coding, debugging, tooling and system operations. Score is successful task completion; each version is a different task set.

**Caveat:** Compare only the same benchmark version, harness, effort, time budget and scoring policy. Vendor and independent runs differ. The score row preserves the exact reported version, units, setup and source.

[Source](https://www.anthropic.com/claude-sonnet-5-5)

### Terminal-Bench 4.1

Agentic multi-step tasks in a terminal: coding, debugging, tooling and system operations. Score is successful task completion; each version is a different task set.

**Caveat:** Compare only the same benchmark version, harness, effort, time budget and scoring policy. Vendor and independent runs differ. The score row preserves the exact reported version, units, setup and source.

[Source](https://www.anthropic.com/claude-sonnet-5-5)

### Terminal-Bench-Science 0.1

Agentic scientific research tasks.

**Caveat:** Standard error ±3.5–4.5 pts per model per Anthropic. The score row preserves the exact reported version, units, setup and source.

[Source](https://www.anthropic.com/claude-fable-and-mythos-5-1)

### Terminal-bench 2.1

Agentic multi-step tasks in a terminal: coding, debugging, tooling and system operations. Score is successful task completion; each version is a different task set.

**Caveat:** Compare only the same benchmark version, harness, effort, time budget and scoring policy. Vendor and independent runs differ. The score row preserves the exact reported version, units, setup and source.

[Source](https://www.anthropic.com/claude-sonnet-5-5)

### Terminal-bench 4.0

Agentic multi-step tasks in a terminal: coding, debugging, tooling and system operations. Score is successful task completion; each version is a different task set.

**Caveat:** Compare only the same benchmark version, harness, effort, time budget and scoring policy. Vendor and independent runs differ. The score row preserves the exact reported version, units, setup and source.

[Source](https://www.anthropic.com/claude-sonnet-5-5)

### Terminal-bench 4.1

Agentic multi-step tasks in a terminal: coding, debugging, tooling and system operations. Score is successful task completion; each version is a different task set.

**Caveat:** Compare only the same benchmark version, harness, effort, time budget and scoring policy. Vendor and independent runs differ. The score row preserves the exact reported version, units, setup and source.

[Source](https://www.anthropic.com/claude-sonnet-5-5)

### Toolathlon Verified

Tool-use benchmark, pass@1 averaged over 3 runs (Z.AI).

**Caveat:** Z.AI-run via official service. The score row preserves the exact reported version, units, setup and source.

[Source](https://z.ai/blog/glm-5.3)

### Z.ai Code Bench (in-house)

Z.AI private coding-agent benchmark across effort levels (task completion and checklist accuracy).

**Caveat:** Private, in-house. Version not stated for 5.3 page; Flash page cites v1.0 on Claude Code 2.1.207. Not publicly reproducible. The score row preserves the exact reported version, units, setup and source.

[Source](https://z.ai/blog/glm-5.3)

### Z.ai Code Bench v1.0

Z.AI private coding-agent benchmark across effort levels (task completion and checklist accuracy).

**Caveat:** Private, in-house. Version not stated for 5.3 page; Flash page cites v1.0 on Claude Code 2.1.207. Not publicly reproducible. The score row preserves the exact reported version, units, setup and source.

[Source](https://z.ai/blog/glm-5.3)

## Verification

`nix build --no-link path:.#checks.x86_64-linux.omp-router` runs deterministic
boundary tests for routing, provider-qualified profiles, cross-account fallback
generation and the executable sync CLI. Coverage includes repeated activation,
local precedence, plugin upgrades, retirement, malformed-input preservation,
sops deferral, native symlinks and file permissions.

Runtime smoke tests use isolated agent directories, never production settings.
The local-provider smoke runs actual OMP against deterministic HTTP endpoints,
verifying custom-model selection, rendered tier/model UI, an injected custom-provider
401 followed by successful cross-provider fallback, and judge HTTP 503 fallback.
Earlier live-account smoke tests also exercised the real configured providers.
