_: {
  flake.modules.nixos.flatpak-apps = {
    services.flatpak.packages = [
      "io.github.kolunmi.Bazaar"
      "com.spotify.Client"
      "org.gimp.GIMP"
      "org.libreoffice.LibreOffice"
    ];
  };
}
