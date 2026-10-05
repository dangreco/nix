_: {
  flake.modules.nixos.omp =
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
    in
    {
      # One service per managed user. Installs only when missing.
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
        ) config.my.users
      );

      # Persist the omp state directory.
      # Note: .local/bin is already persisted by other modules.
      environment.persistence."/persist".users = lib.genAttrs config.my.users (_: {
        directories = [
          ".omp"
        ];
      });
    };
}
