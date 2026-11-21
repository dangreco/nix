_: {
  # Upstream omp, installed per user into ~/.local/bin. The host turns it on
  # (my.omp.enable); each user who opts in (home-manager.users.<name>.my.omp.enable)
  # gets the install service and settings.
  flake.modules.nixos.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      install = pkgs.writeShellApplication {
        name = "omp-install";
        runtimeInputs = with pkgs; [
          bash
          coreutils
          curl
          gnugrep
          gnused
        ];
        text = builtins.readFile ./_install.sh;
      };

      users = lib.attrNames (lib.filterAttrs (_: hm: hm.my.omp.enable) config.home-manager.users);
    in
    {
      options.my.omp.enable = lib.mkEnableOption "upstream omp installs";

      # One service per opted-in user. Installs only when missing.
      config = lib.mkIf config.my.omp.enable {
        systemd.services = lib.listToAttrs (
          map (
            name:
            let
              home = config.users.users.${name}.home;
            in
            lib.nameValuePair "omp-install-${name}" {
              description = "Install upstream omp for ${name} if missing";
              wantedBy = [ "multi-user.target" ];
              wants = [ "network-online.target" ];
              after = [ "network-online.target" ];
              unitConfig = {
                RequiresMountsFor = "${home}/.local/bin";
                ConditionPathExists = "!${home}/.local/bin/omp";
                StartLimitIntervalSec = 0;
              };
              serviceConfig = {
                Type = "oneshot";
                User = name;
                ExecStart = lib.getExe install;
                RemainAfterExit = true;
                Restart = "on-failure";
                RestartSec = "30s";
                TimeoutStartSec = "10m";
                NoNewPrivileges = true;
                PrivateTmp = true;
                SyslogIdentifier = "omp-install-${name}";
              };
            }
          ) users
        );
      };
    };

  flake.modules.homeManager.base =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      cfg = config.my.omp;
      agentDir = "${config.home.homeDirectory}/.omp/agent";

      # Load the whole Pi package: its manifest supplies the bootstrap extension
      # and skills, whose helper scripts rely on the original directory layout.
      superpowers = pkgs.fetchFromGitHub {
        owner = "obra";
        repo = "superpowers";
        rev = "v7.0.2";
        hash = "sha256-rP5YsyGuPd9YSW/Fj3aukrq1bLuV+nwwQMK4JaZQgkI=";
      };

      # Shared by every user; my.omp.settings is layered on top.
      baseSettings = {
        setupVersion = 2;
        symbolPreset = "ascii";
        extensions = [ "${superpowers}" ];

        theme = {
          dark = "anthracite";
        };

        composer = {
          shape = "box";
        };

        statusLine = {
          separator = "ascii";
        };

        memory = {
          backend = "mnemopi";
        };

        startup = {
          quiet = true;
        };

        display = {
          showTurnTime = true;
        };

        update = {
          auto = true;
        };
      };

      # Objects merge, arrays and scalars are replaced (omp's own layer rules).
      userSettings = lib.recursiveUpdate baseSettings cfg.settings;
      settings =
        userSettings
        // lib.optionalAttrs cfg.router.enable {
          extensions = lib.unique ((userSettings.extensions or [ ]) ++ [ "${./_router}/index.ts" ]);
        };

      # Shared MCP servers; my.omp.mcpServers adds to or replaces these by name.
      baseMcpServers = {
        # NixOS/Home Manager options and nixpkgs packages from the live search
        # indexes, so agents look option names up instead of guessing them.
        nixos = {
          type = "stdio";
          command = lib.getExe pkgs.mcp-nixos;
        };
      };
      mcpServers = baseMcpServers // cfg.mcpServers;
      mcpSrc = pkgs.writeText "omp-mcp.json" (builtins.toJSON mcpServers);

      # With sops secrets declared, the files are rendered as sops-nix templates
      # (placeholders substituted) once sops-nix.service has decrypted them.
      # Without, the sources are plain store files.
      hasSecrets = config.sops.secrets != { };

      configSrc =
        if hasSecrets then
          config.sops.templates."omp-config.yml".path
        else
          pkgs.writeText "omp-config.json" (builtins.toJSON settings);

      modelsSrc =
        if hasSecrets then
          config.sops.templates."omp-models.yml".path
        else
          pkgs.writeText "omp-models.json" (builtins.toJSON cfg.models);

      # Bun CLI (_sync.mjs, which imports _router/catalog.mjs and profiles.json, so
      # the whole module directory is referenced) merges everything before it
      # writes anything. Native files: mcp.json gets each declared server replaced by
      # name; config.yml deep-merges managed settings and config.local.yml over the
      # live file; models.yml is rebuilt from my.omp.models + models.local.yml.
      # See the my.omp option descriptions for the user-owned *.local.yml files.
      # Runs from activation and, with secrets, from omp-config.service after sops-nix;
      # also installed as `omp-sync-config` (extra flags, e.g. --agent-dir, override
      # the defaults). flock serializes concurrent runs (activation vs. the service).
      sync = pkgs.writeShellApplication {
        name = "omp-sync-config";
        runtimeInputs = [
          pkgs.bun
          pkgs.coreutils
          pkgs.util-linux
        ];
        text = ''
          umask 077
          lockDir="''${XDG_RUNTIME_DIR:-$HOME/.cache}/omp"
          mkdir -p "$lockDir"
          exec 9>"$lockDir/config-sync.lock"
          flock 9
          exec bun ${./.}/_sync.mjs \
            --agent-dir ${lib.escapeShellArg agentDir} \
            --config ${lib.escapeShellArg configSrc} \
            ${lib.optionalString (cfg.models != { }) "--models ${lib.escapeShellArg modelsSrc}"} \
            ${lib.optionalString (mcpServers != { }) "--mcp ${lib.escapeShellArg mcpSrc}"} \
            "$@"
        '';
      };
    in
    {
      options.my.omp = {
        enable = lib.mkEnableOption "upstream omp";

        router.enable = lib.mkEnableOption "judge-driven routing across configured chat models";

        settings = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          example = lib.literalExpression ''
            {
              theme.dark = "nord";
              modelRoles.default = "my-gateway/claude-sonnet";
              compaction.remoteEndpoint = "https://summarizer.example/v1/chat/completions";
            }
          '';
          description = ''
            Per-user omp settings, layered over the shared defaults of this module
            (objects merge, arrays and scalars replace) and deep-merged into
            ~/.omp/agent/config.yml on every home-manager activation. Declared keys
            win over live runtime settings, but config.local.yml overrides them.
            Other keys stay writable by omp (/settings, /model, omp config set).
            Removing an ordinary key here does not delete it from the live file.

            Shared defaults load obra/superpowers (pinned above) as a Pi-compatible
            package: all skills plus the using-superpowers bootstrap on each model
            request. Setting `extensions` here replaces that package list; use
            `extensions = []` to opt out of Superpowers. The task router is appended
            separately when `my.omp.router.enable` is true. See this module's README
            for routing, fallback policy and benchmark sources. Update Superpowers'
            revision and hash together.

            Values may embed sops secrets via `config.sops.placeholder."<secret>"`
            (the secret must be declared under `sops.secrets`). The value is
            substituted into a JSON string, so it must not contain `"` or `\`.

            User-owned overlay ~/.omp/agent/config.local.yml (never written by Nix)
            is deep-merged over these settings and wins. `extensions` of both are
            unioned. Fallback chains are generated for every configured chat model
            (catalog.mjs, from the merged models and optional routing.local.yml),
            then explicit `retry.fallbackChains` entries of config.local.yml
            override per selector. Ownership of extension paths and chain selectors
            is recorded in ~/.omp/agent/.omp-sync-state.json (no secrets): later
            runs remove paths and chains Nix no longer provides, but keep plugins
            and chains added at runtime. The first run after the upgrade has no
            record and keeps everything except an obsolete store copy of the
            managed router. If the sops templates are not rendered yet, config.yml
            and models.yml stay as they are (reported as deferred) while mcp.json
            still updates.
          '';
        };

        models = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          example = lib.literalExpression ''
            {
              providers.my-gateway = {
                baseUrl = "https://gateway.example.com/v1";
                api = "openai-completions";
                apiKey = config.sops.placeholder."omp/gateway-key";
              };
            }
          '';
          description = ''
            Managed contents of ~/.omp/agent/models.yml. The native file is rebuilt
            whole on every run from this option plus the optional user-owned
            ~/.omp/agent/models.local.yml (same schema; never written by Nix):
            providers deep-merge, each provider's `models` list merges by `id` with
            local fields winning, so models retired here disappear and local ones
            stay. With this option empty and no local models, a never-managed native
            file is left alone; a previously adopted catalog is cleared. With only
            a local file it is generated from that. Malformed local YAML, a
            non-mapping root or repeated model ids abort the sync before writing.
            Same secret placeholder rules as `settings`.
          '';
        };

        mcpServers = lib.mkOption {
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
          default = { };
          example = lib.literalExpression ''
            {
              github = {
                type = "http";
                url = "https://api.githubcopilot.com/mcp/";
                headers.Authorization = "!printf 'Bearer %s' \"$(gh auth token)\"";
              };
            }
          '';
          description = ''
            Per-user MCP servers, added to the shared ones of this module (an entry
            with the same name replaces the shared one) and merged into
            ~/.omp/agent/mcp.json on every home-manager activation: each declared
            server replaces the live entry of that name, all other servers and keys
            stay writable by omp (/mcp add, /mcp disable). Removing a server here
            does not delete it from the live file. Field reference: omp's
            mcp-config docs. The file is written from the Nix store, so keep secrets
            out of it: use omp's `!command` or environment-variable indirection in
            `env`/`headers`. There is no local overlay for MCP: servers added with
            /mcp add are already preserved.
          '';
        };
      };

      config = lib.mkIf (cfg.enable && osConfig.my.omp.enable) {
        sops.templates = lib.mkIf hasSecrets (
          {
            "omp-config.yml".content = builtins.toJSON settings;
          }
          // lib.optionalAttrs (cfg.models != { }) {
            "omp-models.yml".content = builtins.toJSON cfg.models;
          }
        );

        home.packages = [ sync ];

        # Always-apply rules (subagents included); the worktree layout and cleanup
        # they describe come from ../../worktrees.
        home.file.".omp/agent/rules/worktrees.md".source = ./_rules/worktrees.md;

        # Invalid local inputs fail visibly before native configuration is changed.
        home.activation.ompConfig =
          lib.hm.dag.entryAfter ([ "writeBoundary" ] ++ lib.optional hasSecrets "sops-nix")
            ''
              run ${lib.getExe sync}
            '';

        # Activation cannot render secrets when the user manager is down (boot, and
        # every boot on impermanence); sops-nix.service decrypts at login, then this runs.
        systemd.user.services.omp-config = lib.mkIf hasSecrets {
          Unit = {
            Description = "Write omp config.yml, models.yml and mcp.json (with sops templates)";
            Wants = [ "sops-nix.service" ];
            After = [ "sops-nix.service" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = lib.getExe sync;
          };
          Install.WantedBy = [ "default.target" ];
        };

        # The upstream installer links the CLI to ~/.local/bin/omp.
        home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];

        # omp's state; the binary sits in ~/.local/bin, persisted in storage/impermanence.
        home.persistence."/persist".directories = [
          ".omp"
        ];
      };
    };
}
