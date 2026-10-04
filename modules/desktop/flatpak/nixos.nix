{ inputs, ... }:
{
  flake.modules.nixos.flatpak =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ inputs.nix-flatpak.nixosModules.nix-flatpak ];

      services.flatpak = {
        enable = true;
        remotes = [
          {
            name = "flathub";
            location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
          }
        ];
        # Declarative app list, intentionally empty: apps installed through
        # GNOME Software or the flatpak CLI are kept.
        packages = [ ];
        uninstallUnmanaged = false;
        update.auto = {
          enable = true;
          onCalendar = "weekly";
        };
      };

      # services.flatpak asserts xdg.portal.enable. GNOME's own portals take
      # precedence on desktop hosts; on headless hosts these satisfy the
      # extraPortals != [ ] assertion.
      xdg.portal.enable = true;
      xdg.portal.extraPortals = lib.mkDefault [ pkgs.xdg-desktop-portal-gtk ];
      xdg.portal.config.common.default = lib.mkDefault "gtk";

      environment.persistence."/persist" = {
        directories = [ "/var/lib/flatpak" ];
        users = lib.genAttrs config.my.users (_: {
          directories = [
            ".local/share/flatpak"
            ".var/app"
          ];
        });
      };
    };
}
