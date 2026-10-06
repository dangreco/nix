_: {
  # A laptop/desktop install: encrypted impermanent disk, Secure Boot, GNOME and the
  # usual apps. Hosts can still turn any single feature off. Users pick their own
  # Home Manager features in users/<name>/default.nix.
  flake.modules.nixos.base =
    { config, lib, ... }:
    {
      options.my.profiles.desktop.enable = lib.mkEnableOption "the desktop profile";

      config.my = lib.mkIf config.my.profiles.desktop.enable (
        lib.genAttrs
          [
            "disk"
            "impermanence"
            "secureBoot"
            "bootSplash"
            "networkConnections"
            "gnome"
            "githubAvatar"
            "firefox"
            "firefoxGnomeTheme"
            "onepassword"
            "flatpak"
            "flatpakApps"
            "podman"
            "zed"
            "omp"
            "microcontrollers"
          ]
          (_: {
            enable = lib.mkDefault true;
          })
      );
    };
}
