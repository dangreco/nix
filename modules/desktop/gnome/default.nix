_: {
  flake.modules.nixos.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      monitorsSync = pkgs.writeShellApplication {
        name = "monitors-sync";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.diffutils
        ];
        text = builtins.readFile ./_monitors-sync.sh;
      };

      # Per user: restore the saved layout at boot, save it whenever mutter
      # rewrites it. The primary user (first of my.users) also feeds GDM.
      monitorUnits =
        name:
        let
          u = config.users.users.${name};
          args = [
            name
            u.group
            u.home
          ]
          ++ lib.optional (name == lib.head config.my.users) "gdm";
          mounts = "/persist /var/lib/gdm";
        in
        [
          {
            kind = "services";
            name = "monitors-restore-${name}";
            value = {
              description = "Restore saved GNOME monitor layout for ${name}";
              wantedBy = [ "multi-user.target" ];
              before = [
                "systemd-user-sessions.service"
                "display-manager.service"
              ];
              unitConfig.RequiresMountsFor = mounts;
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${lib.getExe monitorsSync} restore ${lib.escapeShellArgs args}";
                SyslogIdentifier = "monitors-sync";
              };
            };
          }
          {
            kind = "services";
            name = "monitors-save-${name}";
            value = {
              description = "Save GNOME monitor layout for ${name}";
              after = [ "monitors-restore-${name}.service" ];
              unitConfig.RequiresMountsFor = mounts;
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${lib.getExe monitorsSync} save ${lib.escapeShellArgs args}";
                SyslogIdentifier = "monitors-sync";
              };
            };
          }
          {
            kind = "paths";
            name = "monitors-save-${name}";
            value = {
              wantedBy = [ "paths.target" ];
              pathConfig.PathChanged = "${u.home}/.config/monitors.xml";
            };
          }
        ];

      units = lib.concatMap monitorUnits config.my.users;
      unitsOf =
        kind:
        lib.listToAttrs (map (x: lib.nameValuePair x.name x.value) (lib.filter (x: x.kind == kind) units));
    in
    {
      options.my.gnome.enable = lib.mkEnableOption "the GNOME desktop with GDM";

      config = lib.mkIf config.my.gnome.enable {
        services.displayManager.gdm.enable = true;
        services.desktopManager.gnome.enable = true;
        services.gnome.gnome-initial-setup.enable = false;
        environment.systemPackages = [
          pkgs.ptyxis
          pkgs.lm_sensors
        ];
        environment.persistence."/persist" = {
          directories = [
            "/var/lib/bluetooth"
            # User pictures (AccountsService); GDM shows them before any timer runs.
            "/var/lib/AccountsService"
            # GDM 49 keeps the greeter's config (incl. monitors.xml) in seat0/config and wipes it on any boot where its .migrated-dyn-users stamp is missing.
            "/var/lib/gdm"
            # The power profile picked from GNOME's battery menu.
            "/var/lib/power-profiles-daemon"
            # Charge history; upower's time-remaining estimates are coarse without it.
            "/var/lib/upower"
            # ICC profiles installed through Settings → Color.
            "/var/lib/colord"
          ]
          # Enrolled fingerprints and Thunderbolt authorisations live here.
          ++ lib.optional config.services.fprintd.enable "/var/lib/fprint"
          ++ lib.optional config.services.hardware.bolt.enable "/var/lib/boltd"
          # fwupd's update history and cached LVFS metadata.
          ++ lib.optional config.services.fwupd.enable "/var/lib/fwupd";
        };

        # Session state every user who logs in builds up, whether or not they opt into
        # the settings below.
        home-manager.sharedModules = [
          {
            home.persistence."/persist" = {
              directories = [
                ".config/dconf"
                {
                  directory = ".local/share/keyrings";
                  mode = "0700";
                }
                # GNOME Online Accounts credentials (accounts.conf).
                {
                  directory = ".config/goa-1.0";
                  mode = "0700";
                }
                # Files sidebar bookmarks.
                ".config/gtk-3.0"
                # WirePlumber's saved state: default audio device, volumes, mutes.
                ".local/state/wireplumber"
                # Localsearch's index; without it every boot re-crawls the home directories.
                ".cache/tracker3"
              ];
              files = [ ".config/mimeapps.list" ];
            };
          }
        ];

        # monitors.xml is not persisted through impermanence: mutter's
        # rename-replace save breaks its symlink and bind mount. See _monitors-sync.sh.
        systemd.services = unitsOf "services";
        systemd.paths = unitsOf "paths";
      };
    };

  # GNOME settings, as dconf keys, for users who opt in
  # (home-manager.users.<name>.my.gnome.enable). Group new keys by schema path (the part
  # before the last slash) so related settings stay together, and add a comment when a
  # key is not self-explanatory. `gsettings list-recursively` or dconf-editor shows the
  # current values.
  flake.modules.homeManager.base =
    {
      config,
      lib,
      osConfig,
      ...
    }:
    {
      options.my.gnome.enable = lib.mkEnableOption "GNOME settings and shell extensions";

      config = lib.mkIf (config.my.gnome.enable && osConfig.my.gnome.enable) {
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
            # On battery: suspend after 15 minutes (seconds); hosts with my.hibernate turn this into suspend-then-hibernate. On AC: never suspend.
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
    };
}
