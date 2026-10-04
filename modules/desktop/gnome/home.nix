_: {
  # GNOME settings, as dconf keys. Group new keys by schema path (the part before the
  # last slash) so related settings stay together, and add a comment when a key is not
  # self-explanatory. `gsettings list-recursively` or dconf-editor shows the current values.
  flake.modules.homeManager.gnome = {
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
