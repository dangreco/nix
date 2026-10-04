_: {
  # Keeps each user's GNOME picture (AccountsService icon) equal to their GitHub
  # avatar, for every user in my.githubUsers. Runs as root; see _sync.sh.
  flake.modules.nixos.github-avatar =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      sync = pkgs.writeShellApplication {
        name = "github-avatar-sync";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
          pkgs.diffutils
          pkgs.jq
          pkgs.systemd
        ];
        text = builtins.readFile ./_sync.sh;
      };

      pairs = lib.mapAttrsToList (user: login: "${user}=${login}") config.my.githubUsers;
    in
    {
      config = lib.mkIf (config.my.githubUsers != { }) {
        systemd.services.github-avatar-sync = {
          description = "Set user pictures from GitHub avatars";
          wants = [ "network-online.target" ];
          after = [
            "network-online.target"
            "accounts-daemon.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe sync} ${lib.escapeShellArgs pairs}";
            RuntimeDirectory = "github-avatar";
            ProtectSystem = "strict";
            ProtectHome = true;
            NoNewPrivileges = true;
          };
          # Offline at boot is common: the next timer run retries.
          unitConfig.StartLimitIntervalSec = 0;
        };

        systemd.timers.github-avatar-sync = {
          description = "Daily GitHub avatar sync";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "2min";
            OnCalendar = "daily";
            RandomizedDelaySec = "1h";
            Persistent = true;
          };
        };
      };
    };
}
