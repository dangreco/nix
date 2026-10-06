_: {
  # Upstream Zed, installed per user into ~/.local/zed.app (it updates itself).
  # The host provides the system prerequisites (my.zed.enable); each user who opts in
  # (home-manager.users.<name>.my.zed.enable) gets the install service and settings.
  flake.modules.nixos.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      install = pkgs.writeShellApplication {
        name = "zed-install";
        runtimeInputs = with pkgs; [
          curl
          findutils
          gzip
          gnutar
          coreutils
          gnused
        ];
        text = builtins.readFile ./_install.sh;
      };

      users = lib.attrNames (lib.filterAttrs (_: hm: hm.my.zed.enable) config.home-manager.users);
    in
    {
      options.my.zed.enable = lib.mkEnableOption "the system prerequisites for upstream Zed";

      config = lib.mkIf config.my.zed.enable {
        # Zed's upstream build expects a "traditional" Linux; zed.dev/docs/linux
        # names nix-ld as the NixOS compatibility layer. These join the module's
        # default set (lists merge). Sources: zed-editor's DT_NEEDED minus what
        # zed.app/lib already bundles (glib, alsa-lib + their deps), and Zed's
        # own nix/build.nix, which dlopens vulkan/wayland/libva at render time.
        programs.nix-ld = {
          enable = true;
          libraries = [
            pkgs.glib
            pkgs.pcre2 # glib
            pkgs.libffi # glib
            pkgs.alsa-lib
            pkgs.vulkan-loader # blade GPU renderer (dlopen)
            pkgs.wayland # winit Wayland backend (dlopen)
            pkgs.libva # video decode (dlopen)
            pkgs.libdrm # libva
          ];
        };

        # The default settings below use Inter for the UI and JetBrains Mono for
        # text; system-wide so the GNOME-launched editor resolves them (same
        # system-prereq role as nix-ld above).
        fonts.packages = [
          pkgs.inter
          pkgs.jetbrains-mono
        ];

        # Nix tooling for the editor (and shells, which share this PATH):
        # nixd because it evaluates real flake code (this repo's flake-parts +
        # import-tree idioms) rather than approximating it, and it embeds
        # nixfmt-based formatting. nixfmt matches the version the repo's
        # pre-commit hooks pin, so editor format-on-save agrees with CI-side
        # formatting. nil is deliberately absent: one server per language.
        environment.systemPackages = [
          pkgs.nixd
          pkgs.nixfmt
        ];

        # One service per opted-in user. Installs only when missing; afterwards Zed
        # updates itself (auto_update).
        systemd.services = lib.listToAttrs (
          map (
            name:
            let
              home = config.users.users.${name}.home;
            in
            lib.nameValuePair "zed-install-${name}" {
              description = "Install upstream Zed for ${name} if missing";
              wantedBy = [ "multi-user.target" ];
              wants = [ "network-online.target" ];
              after = [ "network-online.target" ];
              unitConfig = {
                RequiresMountsFor = "${home}/.local/zed.app";
                ConditionPathExists = "!${home}/.local/zed.app/bin/zed";
                StartLimitIntervalSec = 0;
              };
              serviceConfig = {
                Type = "oneshot";
                User = name;
                ExecStart = lib.getExe install;
                RemainAfterExit = true;
                Restart = "on-failure"; # offline at boot is common; retry until online
                RestartSec = "30s";
                TimeoutStartSec = "10m";
                NoNewPrivileges = true;
                PrivateTmp = true;
                SyslogIdentifier = "zed-install-${name}";
              };
            }
          ) users
        );
      };
    };

  flake.modules.homeManager.base =
    {
      config,
      lib,
      osConfig,
      ...
    }:
    let
      cfg = config.my.zed;
    in
    {
      options.my.zed = {
        enable = lib.mkEnableOption "upstream Zed";

        settings = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          description = ''
            Zed user settings, written verbatim to ~/.config/zed/settings.json as JSON.
            Keys and defaults follow Zed's settings reference:
            https://zed.dev/docs/configuring-zed
            Setting this replaces the defaults below; use lib.recursiveUpdate on
            options.my.zed.settings.default to change single keys.
          '';
          # Carried over from the old dotfiles repo's zed feature. Fonts referenced
          # here are installed on the NixOS side; themes come from the
          # auto-installed catppuccin extensions below.
          default = {
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

            # nixd over nil: real flake evaluation (see the NixOS side). "!nil"
            # removes the Nix extension's default server so they cannot both attach.
            languages.Nix = {
              language_servers = [
                "nixd"
                "!nil"
              ];
              # snake_case per Zed's Formatter enum
              # (crates/settings_content/src/language.rs); "language server"
              # with a space matches no variant and breaks settings parsing.
              formatter = "language_server";
            };

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
      };

      config = lib.mkIf (cfg.enable && osConfig.my.zed.enable) {
        xdg.configFile."zed/settings.json".text = builtins.toJSON cfg.settings;

        # The upstream installer links the CLI to ~/.local/bin/zed.
        home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];

        # The app (incl. zed's self-updates), the desktop entry the installer
        # wrote, and zed's state dir. ~/.local/bin (the CLI symlink) is persisted for
        # everyone in storage/impermanence.
        home.persistence."/persist".directories = [
          ".local/zed.app"
          ".local/share/applications"
          ".local/share/zed"
        ];
      };
    };
}
