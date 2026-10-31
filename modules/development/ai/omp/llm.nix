_: {
  # CLIProxyAPI (ds00, reached through the Cloudflare tunnel) as omp's model
  # provider, with role assignments and fallback chains. Each user brings its own
  # client key from sops; everything else is shared.
  flake.modules.homeManager.base =
    { config, lib, ... }:
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
      # The Coding Plan serves every GLM id as glm-5.3 or glm-5.3-flash.
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
        else if lib.hasPrefix "gpt-" id then
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

        # Limits follow the proxy's model catalog (the serving layer); where omp's
        # bundled catalog is smaller, the smaller value is used. Top tiers (Claude
        # Fable, GPT-6 Astra, Gemini Argon) are left out: they drain quota too fast.
        my.omp.models.providers.llm = {
          baseUrl = "https://llm.dangre.co/v1";
          apiKey = config.sops.placeholder.${cfg.apiKeySecret};
          # Plain API-key shaping on Messages: the proxy applies its own Claude Code cloak.
          auth = "apiKey";
          models = [
            (claude "claude-opus-5-5" "Claude Opus 5.5" 1000000 128000 vision adaptive { })
            (claude "claude-sonnet-5-5" "Claude Sonnet 5.5" 1000000 128000 vision adaptive { })
            (claude "claude-haiku-5-5" "Claude Haiku 5.5" 1000000 128000 vision adaptive { })
            # Same Claude models on the Google AI (Antigravity) quota.
            (claude "claude-opus-5-5-high" "Claude Opus 5.5 (Antigravity)" 1000000 64000 vision budget { })
            (claude "claude-sonnet-5-5-high" "Claude Sonnet 5.5 (Antigravity)" 1000000 64000 vision budget { })
            # ChatGPT Plus: smallest quota, kept for the advisor and fallbacks.
            (gpt "gpt-6.1-sol" "GPT-6.1 Sol" 272000 128000 vision gptEfforts { })
            (chat "gemini-3.8-flash-high" "Gemini 3.8 Flash" 1048576 65536 vision geminiHigh { })
            (chat "gemini-3-flash" "Gemini 3 Flash" 1048576 65536 vision geminiEfforts { })
            (chat "gemini-3.1-flash-lite" "Gemini 3.1 Flash Lite" 1048576 65535 vision geminiEfforts { })
            (chat "glm-5.3" "GLM-5.3" 1000000 131072 text glmEfforts glmCompat)
            (chat "glm-5.3-flash" "GLM-5.3 Flash" 1000000 131072 vision glmEfforts glmCompat)
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

        # Model-keyed chains apply in every role. Every role's chain reaches each
        # upstream account behind the proxy (Anthropic, Antigravity, ChatGPT, Z.AI),
        # so one account going down never leaves a role without a model. Same-size
        # context first; GPT (272K) is last for the 1M Claude roles.
        my.omp.settings.retry.fallbackChains = lib.mapAttrs (_: lib.mkDefault) {
          "llm/claude-opus-5-5" = [
            "llm/claude-opus-5-5-high:high"
            "llm/glm-5.3:high"
            "llm/gpt-6.1-sol:high"
          ];
          "llm/claude-sonnet-5-5" = [
            "llm/claude-sonnet-5-5-high:medium"
            "llm/glm-5.3:high"
            "llm/gpt-6.1-sol:medium"
          ];
          "llm/claude-haiku-5-5" = [
            "llm/gemini-3-flash:low"
            "llm/glm-5.3-flash:low"
            "llm/gpt-6.1-sol:low"
          ];
          # Advisor: GPT first, then Opus on both Claude accounts.
          "llm/gpt-6.1-sol" = [
            "llm/claude-opus-5-5:high"
            "llm/claude-opus-5-5-high:high"
            "llm/glm-5.3:high"
          ];
          "llm/gemini-3.1-flash-lite" = [
            "llm/glm-5.3-flash:low"
            "llm/claude-haiku-5-5:low"
            "llm/gpt-6.1-sol:low"
          ];
          "llm/gemini-3-flash" = [
            "llm/glm-5.3-flash:low"
            "llm/claude-haiku-5-5:low"
            "llm/gpt-6.1-sol:low"
          ];
        };

        # Keep that invariant when roles or chains are edited later.
        assertions =
          let
            inherit (config.my.omp.settings) modelRoles;
            chains = config.my.omp.settings.retry.fallbackChains or { };
            missing =
              role:
              let
                primary = modelOf modelRoles.${role};
                chain = chains.${primary} or [ ];
                covered = lib.unique (map (s: accountOf (modelOf s)) ([ primary ] ++ chain));
              in
              lib.subtractLists covered accounts;
          in
          map (role: {
            assertion = missing role == [ ];
            message = "my.omp.llm: role `${role}` (${modelRoles.${role}}) has no fallback on: ${lib.concatStringsSep ", " (missing role)}";
          }) (lib.attrNames modelRoles);
      };
    };
}
