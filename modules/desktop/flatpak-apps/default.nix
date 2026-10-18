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

        # Spotify's CEF 146 draws Chromium's blue fallback titlebar on GNOME/Wayland
        # (flathub/com.spotify.Client#317; Mutter has no server-side decorations).
        # Fixed in CEF 149+, but Flathub still ships CEF 146. Run it under
        # XWayland, where Mutter draws the normal titlebar. Drop this override
        # once Flathub ships Spotify 1.3.x (CEF 151) and the bar looks native.
        services.flatpak.overrides."com.spotify.Client" = {
          Context.sockets = [
            "x11"
            "!wayland"
          ];
          # Chromium would otherwise pick Wayland from the session type and
          # fail to find a Wayland socket.
          Environment.XDG_SESSION_TYPE = "";
        };
      };
    };
}
