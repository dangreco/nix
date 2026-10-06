_: {
  flake.modules.nixos.base =
    { config, lib, ... }:
    {
      options.my.flatpakApps.enable = lib.mkEnableOption "the default desktop Flatpak apps";

      config = lib.mkIf config.my.flatpakApps.enable {
        services.flatpak.packages = [
          "io.github.kolunmi.Bazaar"
          "com.spotify.Client"
          "org.gimp.GIMP"
          "org.libreoffice.LibreOffice"
        ];
      };
    };
}
