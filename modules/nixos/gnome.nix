_: {
  flake.modules.nixos.gnome =
    { config, lib, ... }:
    {
      services.displayManager.gdm.enable = true;
      services.desktopManager.gnome.enable = true;
      services.gnome.gnome-initial-setup.enable = false;

      environment.persistence."/persist" = {
        directories = [ "/var/lib/bluetooth" ];
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
