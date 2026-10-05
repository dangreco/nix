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
      # names nix-ld as the NixOS compatibility layer. vulkan-loader joins the
      # module's default library set (lists merge): the nixpkgs-patched loader
      # discovers GPU drivers under /run/opengl-driver.
      programs.nix-ld = {
        enable = true;
        libraries = [ pkgs.vulkan-loader ];
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
