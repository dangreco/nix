{ inputs, ... }:
{
  flake.modules.nixos.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ inputs.nix-flatpak.nixosModules.nix-flatpak ];

      options.my.flatpak.enable = lib.mkEnableOption "Flatpak with Flathub";

      config = lib.mkIf config.my.flatpak.enable {
        services.flatpak = {
          enable = true;
          remotes = [
            {
              name = "flathub";
              location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
            }
          ];
          # Desktop apps are declared in my.flatpakApps; apps installed through
          # GNOME Software or the flatpak CLI are kept.
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

        environment.persistence."/persist".directories = [ "/var/lib/flatpak" ];
        # Per-user installs and every app's own data.
        home-manager.sharedModules = [
          {
            home.persistence."/persist".directories = [
              ".local/share/flatpak"
              ".var/app"
            ];
          }
        ];
      };
    };
}
