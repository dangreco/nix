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

      # Shared by every user; my.omp.settings is layered on top.
      baseSettings = {
        setupVersion = 2;
        symbolPreset = "ascii";

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
      };

      # Objects merge, arrays and scalars are replaced (omp's own layer rules).
      settings = lib.recursiveUpdate baseSettings cfg.settings;

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

      # config.yml: deep-merges the declared settings over the live file. omp keeps
      # write access to the file and to every key not declared here; declared keys
      # are reasserted on each run.
      # models.yml: written whole from my.omp.models; only touched when that is non-empty.
      # Runs from activation and, with secrets, from omp-config.service after sops-nix.
      sync = pkgs.writeShellApplication {
        name = "omp-sync-config";
        runtimeInputs = with pkgs; [
          coreutils
          jq
          yq-go
        ];
        text = ''
          agentDir=${lib.escapeShellArg agentDir}
          mkdir -p "$agentDir"

          # Rendered templates only exist after sops-nix.service ran; omp-config.service retries then.
          need() {
            [ -r "$1" ] || { echo "omp-sync-config: $1 not rendered yet, skipping" >&2; exit 0; }
          }

          src=${configSrc}
          target="$agentDir/config.yml"
          need "$src"

          live='{}'
          if [ -s "$target" ]; then
            live=$(yq -o=json '.' "$target")
          fi
          # A leftover store symlink from the old home.file setup is replaced
          # by a writable regular file.
          [ -L "$target" ] && rm -f "$target"

          tmp=$(mktemp "$target.XXXXXX")
          jq -n --argjson live "$live" --argjson managed "$(yq -o=json '.' "$src")" \
            '($live // {}) * $managed' | yq -p=json -o=yaml '.' > "$tmp"
          chmod 600 "$tmp"
          mv -f "$tmp" "$target"
        ''
        + lib.optionalString (cfg.models != { }) ''

          src=${modelsSrc}
          target="$agentDir/models.yml"
          need "$src"

          tmp=$(mktemp "$target.XXXXXX")
          yq -p=json -o=yaml '.' "$src" > "$tmp"
          chmod 600 "$tmp"
          mv -f "$tmp" "$target"
        '';
      };
    in
    {
      options.my.omp = {
        enable = lib.mkEnableOption "upstream omp";

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
            ~/.omp/agent/config.yml on every home-manager activation: declared keys
            always win, all other keys stay writable by omp itself (/settings, /model,
            omp config set). Removing a key here does not delete it from the live file.

            Values may embed sops secrets via `config.sops.placeholder."<secret>"`
            (the secret must be declared under `sops.secrets`). The value is
            substituted into a JSON string, so it must not contain `"` or `\`.
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
            Contents of ~/.omp/agent/models.yml. Empty leaves the file alone; otherwise
            the file is rewritten whole on every activation (omp does not write it, so
            removed keys disappear). Same secret placeholder rules as `settings`.
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

        home.activation.ompConfig =
          lib.hm.dag.entryAfter ([ "writeBoundary" ] ++ lib.optional hasSecrets "sops-nix")
            ''
              run ${lib.getExe sync}
            '';

        # Activation cannot render secrets when the user manager is down (boot, and
        # every boot on impermanence); sops-nix.service decrypts at login, then this runs.
        systemd.user.services.omp-config = lib.mkIf hasSecrets {
          Unit = {
            Description = "Write omp config.yml and models.yml from sops templates";
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
