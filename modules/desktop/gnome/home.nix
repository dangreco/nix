_: {
  # GNOME settings, as dconf keys. Group new keys by schema path (the part before the
  # last slash) so related settings stay together, and add a comment when a key is not
  # self-explanatory. `gsettings list-recursively` or dconf-editor shows the current values.
  flake.modules.homeManager.gnome = {
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
    };
  };
}
