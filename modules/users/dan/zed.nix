{
  flake.modules.homeManager.dan-zed = {
    # Dan's Zed settings, carried over from the old dotfiles repo's zed feature.
    # hm.zed (modules/development/zed/home.nix) serializes these verbatim to
    # ~/.config/zed/settings.json. Fonts referenced here are installed on the
    # NixOS side of the zed module; themes come from the auto-installed
    # catppuccin extensions below.
    my.zed.settings = {
      auto_update = true;
      ui_font_family = "Inter";
      ui_font_size = 16;
      buffer_font_family = "JetBrains Mono";
      buffer_font_size = 15;
      cli_default_open_behavior = "new_window";
      rounded_selection = false;
      icon_theme = "Catppuccin Latte";
      theme = {
        mode = "system";
        light = "Catppuccin Latte";
        dark = "Catppuccin Mocha";
      };

      cursor_shape = "bar";
      load_direnv = "direct";
      format_on_save = "on";

      title_bar = {
        show_onboarding_banner = false;
        show_user_picture = false;
        show_sign_in = false;
      };

      telemetry = {
        diagnostics = false;
        metrics = false;
        anthropic_retention = false;
      };

      auto_install_extensions = {
        html = true;
        nix = true;
        toml = true;
        catppuccin = true;
        catppuccin-icons = true;
      };
      session.trust_all_worktrees = true;

      project_panel = {
        button = true;
        dock = "left";
        starts_open = true;
        file_icons = true;
        entry_spacing = "comfortable";
        hide_gitignore = false;
        diagnostic_badges = false;
      };

      git_panel = {
        button = true;
        dock = "left";
      };

      outline_panel = {
        button = true;
        dock = "left";
      };

      debugger = {
        button = true;
        dock = "bottom";
      };

      terminal = {
        button = true;
        dock = "bottom";
      };

      collaboration_panel = {
        button = false;
        dock = "right";
      };

      agent = {
        button = false;
        dock = "right";
      };
    };
  };
}
