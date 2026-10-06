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
          autoPrune.enable = true;
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
