_: {
  # GNOME settings, as dconf keys. Group new keys by schema path (the part before the
  # last slash) so related settings stay together, and add a comment when a key is not
  # self-explanatory. `gsettings list-recursively` or dconf-editor shows the current values.
  flake.modules.homeManager.gnome =
    { lib, ... }:
    {
      # Shell extensions live in ./extensions, one file per extension. Each file adds its
      # package to programs.gnome-shell.extensions and sets its own dconf keys under
      # org/gnome/shell/extensions/<name>. This list is authoritative: an extension enabled
      # only through the Extensions app is disabled again on the next switch.
      programs.gnome-shell.enable = true;

      dconf.settings = {
        "org/gnome/settings-daemon/plugins/media-keys" = {
          # The paths of this user's custom keybindings.
          custom-keybindings = [
            "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/terminal/"
          ];
        };
        "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/terminal" = {
          binding = "<Super>Return";
          command = "ptyxis --new-window";
          name = "Terminal";
        };
        "org/gnome/desktop/interface" = {
          show-battery-percentage = true;
        };
        "org/gnome/desktop/peripherals/touchpad" = {
          tap-to-click = false;
        };
        "org/gnome/desktop/wm/preferences" = {
          # Leading colon puts the buttons on the right: minimize, maximize, close.
          button-layout = ":minimize,maximize,close";
        };
        "org/gnome/desktop/session" = {
          # Seconds of inactivity before the session counts as idle; 0 never idles.
          idle-delay = lib.hm.gvariant.mkUint32 0;
        };
        "org/gnome/settings-daemon/plugins/power" = {
          idle-dim = true;
          power-saver-profile-on-low-battery = true;
          # On battery: suspend after 15 minutes (seconds). On AC: never suspend.
          sleep-inactive-battery-type = "suspend";
          sleep-inactive-battery-timeout = 900;
          sleep-inactive-ac-type = "nothing";
        };
        "org/gnome/shell" = {
          # Dock contents, in order. Desktop file IDs: Files, then Firefox.
          favorite-apps = [
            "org.gnome.Nautilus.desktop"
            "firefox.desktop"
          ];
        };
      };
    };
}
