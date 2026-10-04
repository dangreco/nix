_: {
  flake.modules.nixos.gnome =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      services.displayManager.gdm.enable = true;
      services.desktopManager.gnome.enable = true;
      services.gnome.gnome-initial-setup.enable = false;

      environment.systemPackages = [ pkgs.ptyxis ];
      environment.persistence."/persist" = {
        directories = [
          "/var/lib/bluetooth"
          # User pictures (AccountsService); GDM shows them before any timer runs.
          "/var/lib/AccountsService"
        ]
        # Enrolled fingerprints and Thunderbolt authorisations live here.
        ++ lib.optional config.services.fprintd.enable "/var/lib/fprint"
        ++ lib.optional config.services.hardware.bolt.enable "/var/lib/boltd";
        users = lib.genAttrs config.my.users (_: {
          directories = [
            ".config/dconf"
            {
              directory = ".local/share/keyrings";
              mode = "0700";
            }
          ];
          files = [ ".config/monitors.xml" ];
        });
      };
    };
}
