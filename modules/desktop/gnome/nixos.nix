_: {
  flake.modules.nixos.gnome =
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
      services.displayManager.gdm.enable = true;
      services.desktopManager.gnome.enable = true;
      services.gnome.gnome-initial-setup.enable = false;

      environment.systemPackages = [ pkgs.ptyxis ];
      environment.persistence."/persist" = {
        directories = [
          "/var/lib/bluetooth"
          # User pictures (AccountsService); GDM shows them before any timer runs.
          "/var/lib/AccountsService"
          # GDM 49 keeps the greeter's config (incl. monitors.xml) in seat0/config and wipes it on any boot where its .migrated-dyn-users stamp is missing.
          "/var/lib/gdm"
        ]
        # Enrolled fingerprints and Thunderbolt authorisations live here.
        ++ lib.optional config.services.fprintd.enable "/var/lib/fprint"
        ++ lib.optional config.services.hardware.bolt.enable "/var/lib/boltd";
        users = lib.genAttrs config.my.users (_: {
          directories = [
            ".config/dconf"
            {
              directory = ".local/share/keyrings";
              mode = "0700";
            }
          ];
        });
      };

      # monitors.xml is not persisted through impermanence: mutter's
      # rename-replace save breaks its symlink and bind mount. See _monitors-sync.sh.
      systemd.services = unitsOf "services";
      systemd.paths = unitsOf "paths";
    };
}
