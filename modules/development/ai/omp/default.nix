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
      target = "${config.home.homeDirectory}/.omp/agent/config.yml";

      managed = (pkgs.formats.yaml { }).generate "omp-managed.yml" cfg.settings;

      # Deep-merges the declared settings over the live config.yml. omp keeps
      # write access to the file and to every key not declared here; declared
      # keys are reasserted on each activation. Objects merge, arrays and
      # scalars are replaced (same rules as omp's own layer merge).
      sync = pkgs.writeShellApplication {
        name = "omp-sync-config";
        runtimeInputs = with pkgs; [
          coreutils
          jq
          yq-go
        ];
        text = ''
          target=${lib.escapeShellArg target}
          mkdir -p "$(dirname "$target")"

          live='{}'
          if [ -s "$target" ]; then
            live=$(yq -o=json '.' "$target")
          fi
          # A leftover store symlink from the old home.file setup is replaced
          # by a writable regular file.
          [ -L "$target" ] && rm -f "$target"

          tmp=$(mktemp "$target.XXXXXX")
          jq -n --argjson live "$live" --argjson managed "$(yq -o=json '.' ${managed})" \
            '($live // {}) * $managed' | yq -p=json -o=yaml '.' > "$tmp"
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
          default = {
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
          description = ''
            omp settings owned by nix. Deep-merged into ~/.omp/agent/config.yml on
            every home-manager activation: declared keys always win, all other keys
            stay writable by omp itself (/settings, /model, omp config set). Removing
            a key here does not delete it from the live file.
          '';
        };
      };

      config = lib.mkIf (cfg.enable && osConfig.my.omp.enable) {
        home.activation.ompConfig = lib.mkIf (cfg.settings != { }) (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            run ${lib.getExe sync}
          ''
        );

        # The upstream installer links the CLI to ~/.local/bin/omp.
        home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];

        # omp's state; the binary sits in ~/.local/bin, persisted in storage/impermanence.
        home.persistence."/persist".directories = [
          ".omp"
        ];
      };
    };
}
