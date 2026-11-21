_: {
  # CLIProxyAPI (ds00, reached through the Cloudflare tunnel) as omp's model
  # provider, with role assignments and fallback chains. Each user brings its own
  # client key from sops; everything else is shared.
  flake.modules.homeManager.base =
    {
      config,
      lib,
      osConfig,
      ...
    }:
    let
      cfg = config.my.omp.llm;

      # One provider; each model names its wire: Claude on Messages, GPT on
      # Responses, the rest on Chat Completions.
      llmModel =
        api: id: name: contextWindow: maxTokens: input: thinking: extra:
        {
          inherit
            api
            id
            name
            contextWindow
            maxTokens
            input
            thinking
            ;
          reasoning = true;
        }
        // extra;
      claude = llmModel "anthropic-messages";
      gpt = llmModel "openai-responses";
      chat = llmModel "openai-completions";

      text = [ "text" ];
      vision = [
        "text"
        "image"
      ];
      image = id: name: {
        inherit id name;
        api = "openai-images";
        kind = "image";
        reasoning = false;
        input = vision;
      };
      efforts = mode: efforts: { inherit mode efforts; };
      # Claude 5.x: adaptive thinking; summarized display returns the text.
      adaptive =
        efforts "anthropic-adaptive" [
          "low"
          "medium"
          "high"
          "xhigh"
          "max"
        ]
        // {
          supportsDisplay = true;
        };
      # Antigravity's Claude "-high" ids take a token budget (max 64K).
      budget = efforts "budget" [
        "low"
        "medium"
        "high"
      ];
      legacyBudget = efforts "budget" [
        "minimal"
        "low"
        "medium"
        "high"
        "xhigh"
      ];
      gptEfforts = efforts "effort" [
        "low"
        "medium"
        "high"
        "xhigh"
        "max"
      ];
      geminiEfforts = efforts "effort" [
        "minimal"
        "low"
        "medium"
        "high"
      ];
      geminiHigh = efforts "effort" [
        "low"
        "medium"
        "high"
      ];
      # Coding Plan aliases retain their configured wire limits; profiles.json
      # distinguishes documented backend mappings from unresolved legacy aliases.
      glmEfforts = efforts "effort" [
        "low"
        "high"
        "max"
      ];
      # Coding-plan GLM pauses long mid-stream; omp only detects z.ai hosts itself.
      glmCompat.compat.streamIdleTimeoutMs = 300000;

      # Upstream accounts behind the proxy, and which one serves a model id.
      accounts = [
        "anthropic"
        "antigravity"
        "chatgpt"
        "zai"
      ];
      # "llm/claude-opus-5-5:high" -> "llm/claude-opus-5-5"
      modelOf = selector: lib.head (lib.splitString ":" selector);
      accountOf =
        model:
        let
          id = lib.removePrefix "llm/" model;
        in
        if lib.hasPrefix "glm-" id then
          "zai"
        else if lib.hasPrefix "gpt-" id || id == "codex-auto-review" then
          "chatgpt"
        # Antigravity serves Gemini and the "-high" Claude ids.
        else if lib.hasPrefix "gemini-" id || lib.hasSuffix "-high" id then
          "antigravity"
        else if lib.hasPrefix "claude-" id then
          "anthropic"
        else
          throw "my.omp.llm: unknown upstream account for ${model}";
    in
    {
      options.my.omp.llm = {
        enable = lib.mkEnableOption "CLIProxyAPI as omp's model provider";

        apiKeySecret = lib.mkOption {
          type = lib.types.str;
          example = "users/dan/home/omp/llm-api-key";
          description = ''
            Name of the sops secret (in the user's default sops file) holding this
            user's CLIProxyAPI client key. Each user gets its own key so it can be
            revoked on its own.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        sops.secrets.${cfg.apiKeySecret} = { };

        # All entries smoke-tested directly and through omp on 2026-11-21.
        # Retirement-filtered catalog: 44 chat and 4 image models. Excludes announced
        # shutdowns through 2027-02-19, not mere "not sooner than" lifecycle dates.
        # Sonnet 4.5 retires 2026-11-30:
        # https://platform.claude.com/docs/en/about-claude/model-deprecations
        # Antigravity's GPT-OSS 120B retires 2026-11-30:
        # https://antigravity.google/docs/models/
        # GPT Image 1.5 / 2 API shutdowns: 2026-12-01 / 2027-02-10 (subscription
        # backend dates may differ): https://developers.openai.com/api/docs/deprecations
        # Roles below stay conservative; premium models are selectable too.
        # Limits: https://github.com/router-for-me/models/blob/main/models.json
        # capped by omp's catalog where smaller. GLM aliases retain the Coding Plan
        # reasoning surface rather than their original upstream model's surface.
        # Advertised but unavailable (not selectable):
        # - 404/retired: claude-3-5-haiku-20241022, claude-3-7-sonnet-20250219,
        #   claude-opus-4-1-20250805, claude-opus-4-20250514, claude-sonnet-4-20250514.
        # - claude-fable-5-2: proxy's Claude Code 2.1.280 needs >= 2.1.290.
        # - gpt-6-chat-thinking: unsupported by the ChatGPT/Codex account.
        # - glm-5.3-flashx: subscription excludes it; glm-5.3-flashx-legal: no balance.
        my.omp.models.providers.llm = {
          baseUrl = "https://llm.dangre.co/v1";
          apiKey = config.sops.placeholder.${cfg.apiKeySecret};
          # Plain API-key shaping on Messages: the proxy applies its own Claude Code cloak.
          auth = "apiKey";
          models = [
            # Anthropic subscription.
            (claude "claude-fable-5" "Claude Fable 5" 1000000 128000 vision adaptive { })
            (claude "claude-fable-5-1" "Claude Fable 5.1" 1000000 128000 vision adaptive { })
            (claude "claude-opus-5-5" "Claude Opus 5.5" 1000000 128000 vision adaptive { })
            (claude "claude-opus-5" "Claude Opus 5" 1000000 128000 vision adaptive { })
            (claude "claude-opus-4-8" "Claude Opus 4.8" 1000000 128000 vision adaptive { })
            (claude "claude-opus-4-7" "Claude Opus 4.7" 1000000 128000 vision adaptive { })
            (claude "claude-opus-4-6" "Claude Opus 4.6" 1000000 128000 vision (efforts "anthropic-adaptive" [
              "low"
              "medium"
              "high"
              "max"
            ]) { })
            (claude "claude-opus-4-5-20251101" "Claude Opus 4.5" 200000 64000 vision (
              legacyBudget // { mode = "anthropic-budget-effort"; }
            ) { })
            (claude "claude-sonnet-5-5" "Claude Sonnet 5.5" 1000000 128000 vision adaptive { })
            (claude "claude-sonnet-5" "Claude Sonnet 5" 1000000 128000 vision adaptive { })
            (claude "claude-sonnet-4-6" "Claude Sonnet 4.6" 200000 64000 vision (efforts "anthropic-adaptive" [
              "low"
              "medium"
              "high"
            ]) { })
            (claude "claude-haiku-5-5" "Claude Haiku 5.5" 1000000 128000 vision adaptive { })
            (claude "claude-haiku-4-5-20251001" "Claude Haiku 4.5" 200000 64000 vision legacyBudget { })
            # Google AI / Antigravity quota.
            (claude "claude-opus-5-5-high" "Claude Opus 5.5 (Antigravity)" 1000000 64000 vision budget { })
            (claude "claude-sonnet-5-5-high" "Claude Sonnet 5.5 (Antigravity)" 1000000 64000 vision budget { })
            (chat "gemini-4-argon-high" "Gemini 4 Argon" 1048576 65536 vision geminiHigh { })
            (chat "gemini-4-hydrogen-xhigh" "Gemini 4 Hydrogen (XHigh)" 1048576 65536 vision geminiEfforts { })
            (chat "gemini-4-neon-xhigh" "Gemini 4 Neon (XHigh)" 1048576 65536 vision geminiEfforts { })
            (chat "gemini-3.8-flash-high" "Gemini 3.8 Flash" 1048576 65536 vision geminiHigh { })
            (chat "gemini-3.8-flash-tiered" "Gemini 3.8 Flash (Tiered)" 1048576 65536 vision geminiHigh { })
            (chat "gemini-3-flash" "Gemini 3 Flash" 1048576 65536 vision geminiEfforts { })
            (chat "gemini-3.5-flash-lite" "Gemini 3.5 Flash Lite" 1048576 65535 vision geminiEfforts { })
            (chat "gemini-3.1-flash-lite" "Gemini 3.1 Flash Lite" 1048576 65535 vision geminiEfforts { })
            # ChatGPT Plus, including all verified premium and review models.
            (gpt "gpt-6.2-astra" "GPT-6.2 Astra" 272000 128000 vision gptEfforts { })
            (gpt "gpt-6.2-sol" "GPT-6.2 Sol" 500000 128000 vision gptEfforts { })
            (gpt "gpt-6.1-sol" "GPT-6.1 Sol" 272000 128000 vision gptEfforts { })
            (gpt "gpt-6.1-terra" "GPT-6.1 Terra" 500000 128000 vision gptEfforts { })
            (gpt "gpt-6-astra" "GPT-6 Astra" 272000 128000 vision gptEfforts { })
            (gpt "gpt-6-sol" "GPT-6 Sol" 272000 128000 vision gptEfforts { })
            (gpt "gpt-6-luna" "GPT-6 Luna" 272000 128000 vision gptEfforts { })
            (gpt "gpt-5.6-sol" "GPT-5.6 Sol" 372000 128000 vision gptEfforts { })
            (gpt "gpt-5.6-terra" "GPT-5.6 Terra" 372000 128000 vision gptEfforts { })
            (gpt "gpt-5.6-luna" "GPT-5.6 Luna" 372000 128000 vision gptEfforts { })
            (gpt "codex-auto-review" "Codex Auto Review" 272000 128000 vision (efforts "effort" [
              "low"
              "medium"
              "high"
              "xhigh"
            ]) { })
            # Z.AI Coding Plan aliases.
            (chat "glm-5.3" "GLM-5.3" 1000000 131072 text glmEfforts glmCompat)
            (chat "glm-5.3-flash" "GLM-5.3 Flash" 1000000 131072 vision glmEfforts glmCompat)
            (chat "glm-5.2" "GLM-5.2" 1000000 131072 text glmEfforts glmCompat)
            (chat "glm-5.1" "GLM-5.1" 200000 131072 text glmEfforts glmCompat)
            (chat "glm-5-turbo" "GLM-5 Turbo" 200000 131072 text glmEfforts glmCompat)
            (chat "glm-5" "GLM-5" 204800 131072 text glmEfforts glmCompat)
            (chat "glm-4.7" "GLM-4.7" 204800 131072 text glmEfforts glmCompat)
            (chat "glm-4.6" "GLM-4.6" 204800 131072 text glmEfforts glmCompat)
            (chat "glm-4.5" "GLM-4.5" 131072 98304 text glmEfforts glmCompat)
            (chat "glm-4.5-air" "GLM-4.5 Air" 131072 98304 text glmEfforts glmCompat)
            # Image-only runners must not use Responses: the proxy requires Images.
            (image "gpt-image-2.5" "GPT Image 2.5")
            (image "gpt-image-2.5-flare" "GPT Image 2.5 Flare")
            (image "gpt-image-2.5-sunburst" "GPT Image 2.5 Sunburst")
            # Omp 18.14.2: omit generate_image.image_size for Gemini. It forwards
            # pixel dimensions, but this API requires 1K/2K/4K-style size values.
            {
              id = "gemini-3.1-flash-image";
              name = "Gemini 3.1 Flash Image";
              api = "google-generative-ai";
              baseUrl = "https://llm.dangre.co/v1beta";
              kind = "image";
              reasoning = false;
              input = vision;
              contextWindow = 65536;
              maxTokens = 65536;
            }
          ];
        };

        # Claude subscription carries the main work; small/background roles go to
        # Gemini so titles and memory do not spend Claude quota. The advisor is a
        # different model family on purpose. mkDefault: a user may re-point a role.
        my.omp.settings.modelRoles = lib.mapAttrs (_: lib.mkDefault) {
          default = "llm/claude-opus-5-5:high";
          slow = "llm/claude-opus-5-5:xhigh";
          plan = "llm/claude-opus-5-5:high";
          advisor = "llm/gpt-6.1-sol:high";
          task = "llm/claude-sonnet-5-5:medium";
          smol = "llm/claude-haiku-5-5:low";
          vision = "llm/claude-sonnet-5-5:medium";
          commit = "llm/claude-haiku-5-5:low";
          tiny = "llm/gemini-3.1-flash-lite:minimal";
          memory = "llm/gemini-3-flash:low";
        };

        my.omp.settings.retry = {
          enabled = lib.mkDefault true;
          modelFallback = lib.mkDefault true;
          fallbackOn = lib.mkDefault "any";
        };

        # Every chat model crosses all four upstream accounts. Prefer the same
        # policy tier, then stronger tiers, then weaker tiers when an account has
        # no equivalent. Keep image support and prefer enough context; OMP owns
        # runtime capacity checks, cooldowns and retry/fallback restoration.
        my.omp.settings.retry.fallbackChains =
          let
            profiles = (builtins.fromJSON (builtins.readFile ./_router/profiles.json)).models;
            tiers = [
              "genius"
              "smart"
              "average"
              "dumb"
            ];
            chatModels = builtins.filter (
              model: (model.kind or "chat") == "chat"
            ) config.my.omp.models.providers.llm.models;
            tierOf = model: profiles.${model.id}.tier or "smart";
            rank = tier: lib.lists.findFirstIndex (value: value == tier) 1 tiers;
            tierDistance =
              source: candidate:
              let
                delta = rank (tierOf candidate) - rank (tierOf source);
              in
              if delta == 0 then
                0
              else if delta < 0 then
                -delta
              else
                4 + delta;
            score =
              source: candidate:
              100 * tierDistance source candidate
              + (if candidate.contextWindow >= source.contextWindow then 0 else 10);
            targets =
              source:
              map (
                account:
                let
                  candidates = builtins.filter (
                    candidate:
                    accountOf "llm/${candidate.id}" == account
                    && (!(builtins.elem "image" source.input) || builtins.elem "image" candidate.input)
                  ) chatModels;
                  ordered = lib.sort (a: b: score source a < score source b) candidates;
                in
                if ordered == [ ] then
                  throw "my.omp.llm: no compatible fallback on ${account} for ${source.id}"
                else
                  lib.head ordered
              ) (builtins.filter (account: account != accountOf "llm/${source.id}") accounts);
            effortFor =
              model:
              let
                preferred =
                  {
                    genius = "high";
                    smart = "high";
                    average = "medium";
                    dumb = "low";
                  }
                  .${tierOf model};
                supported = model.thinking.efforts;
              in
              if builtins.elem preferred supported then preferred else lib.head supported;
          in
          lib.listToAttrs (
            map (
              source:
              lib.nameValuePair "llm/${source.id}" (
                lib.mkDefault (
                  map (target: "llm/${target.id}:${effortFor target}") (
                    lib.sort (a: b: score source a < score source b) (targets source)
                  )
                )
              )
            ) chatModels
          );

        # Native judges are separate. Check every selectable proxy chat model,
        # not merely the current role assignments, so dynamic routing is covered.
        assertions = lib.mkIf (config.my.omp.enable && osConfig.my.omp.enable) (
          let
            chatModels = builtins.filter (
              model: (model.kind or "chat") == "chat"
            ) config.my.omp.models.providers.llm.models;
            chains = config.my.omp.settings.retry.fallbackChains or { };
            missing =
              model:
              let
                primary = "llm/${model.id}";
                chain = chains.${primary} or [ ];
                covered = lib.unique (map (s: accountOf (modelOf s)) ([ primary ] ++ chain));
              in
              lib.subtractLists covered accounts;
          in
          map (model: {
            assertion = missing model == [ ];
            message = "my.omp.llm: model `${model.id}` has no fallback on: ${lib.concatStringsSep ", " (missing model)}";
          }) chatModels
        );
      };
    };
}
