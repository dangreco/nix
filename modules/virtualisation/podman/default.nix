{
  flake.modules.nixos.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.my.podman.enable = lib.mkEnableOption "rootless Podman with Docker compatibility";

      config = lib.mkIf config.my.podman.enable {
        virtualisation.podman = {
          enable = true;
          dockerCompat = true;
          defaultNetwork.settings.dns_enabled = true;
          autoPrune = {
            enable = true;
            # Images no container uses go too, once they are a week old; plain prune
            # only drops dangling layers, so pulled-and-forgotten images would pile up.
            flags = [
              "--all"
              "--filter"
              "until=168h"
            ];
          };
        };

        # autoPrune only covers root's store (/var/lib/containers); every user's
        # rootless store under ~/.local/share/containers gets the same weekly prune.
        systemd.user.services.podman-prune = {
          description = "Prune rootless podman resources";
          unitConfig.ConditionUser = "!@system";
          # newuidmap/newgidmap for the rootless user namespace.
          path = [ "/run/wrappers" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.escapeShellArgs (
              [
                (lib.getExe config.virtualisation.podman.package)
                "system"
                "prune"
                "--force"
              ]
              ++ config.virtualisation.podman.autoPrune.flags
            );
          };
        };
        systemd.user.timers.podman-prune = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = config.virtualisation.podman.autoPrune.dates;
            Persistent = true;
            RandomizedDelaySec = 1800;
          };
        };

        # Provider behind `podman compose` / `docker compose`.
        environment.systemPackages = [ pkgs.podman-compose ];

        # Point Docker-API clients at the rootless user socket (enabled by nixpkgs).
        # dockerSocket.enable stays off: that socket is rootful, and `podman`
        # group membership is root-equivalent.
        environment.extraInit = ''
          if [ -n "''${XDG_RUNTIME_DIR:-}" ]; then
            export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
          fi
        '';

        environment.persistence."/persist".directories = [ "/var/lib/containers" ];
        # Rootless images and containers.
        home-manager.sharedModules = [
          { home.persistence."/persist".directories = [ ".local/share/containers" ]; }
        ];
      };
    };
}
