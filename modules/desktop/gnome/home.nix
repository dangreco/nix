_: {
  # GNOME settings, as dconf keys. Group new keys by schema path (the part before the
  # last slash) so related settings stay together, and add a comment when a key is not
  # self-explanatory. `gsettings list-recursively` or dconf-editor shows the current values.
  flake.modules.homeManager.gnome = {
    dconf.settings = {
      "org/gnome/desktop/interface" = {
        show-battery-percentage = true;
      };
    };
  };
}
