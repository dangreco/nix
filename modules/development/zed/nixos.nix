_: {
  flake.modules.nixos.zed =
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
    in
    {
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

      # The default settings (dan-zed HM module) use Inter for the UI and
      # JetBrains Mono for text; system-wide so the GNOME-launched editor
      # resolves them (same system-prereq role as nix-ld above).
      fonts.packages = [
        pkgs.inter
        pkgs.jetbrains-mono
      ];

      # One service per managed user (pattern: home-manager-restore-<user> in
      # modules/storage/impermanence/nixos.nix). Installs only when missing;
      # afterwards Zed updates itself (auto_update).
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
        ) config.my.users
      );

      # /home is wiped at boot: keep the app (incl. zed's self-updates), the
      # symlink+desktop entry the installer wrote, and zed's state dir.
      environment.persistence."/persist".users = lib.genAttrs config.my.users (_: {
        directories = [
          ".local/zed.app"
          ".local/bin"
          ".local/share/applications"
          ".local/share/zed"
        ];
      });
    };
}
