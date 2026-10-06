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
      ...
    }:
    let
      cfg = config.my.omp;
    in
    {
      options.my.omp = {
        enable = lib.mkEnableOption "upstream omp";

        settings = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = ''
            omp user settings, written verbatim to ~/.omp/agent/config.yml as YAML.
          '';
        };
      };

      config = lib.mkIf (cfg.enable && osConfig.my.omp.enable) {
        home.file.".omp/agent/config.yml" = lib.mkIf (cfg.settings != { }) {
          text = lib.generators.toYAML { } cfg.settings;
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
