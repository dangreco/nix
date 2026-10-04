_: {
  # rafaelmardojai/firefox-gnome-theme, kept current for every user and every Firefox
  # profile they have.
  #
  # Two parts:
  #  - Firefox policy sets the preferences the theme needs, for all profiles (also ones
  #    created later) and without touching any user.js.
  #  - A per-user systemd timer downloads the newest theme and copies it into each
  #    profile's chrome/ directory (see _sync.sh). A path unit re-applies the cached
  #    copy when profiles are added, so new profiles are themed without waiting.
  flake.modules.nixos.firefox-gnome-theme =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.my.firefoxGnomeTheme;

      sync = pkgs.writeShellApplication {
        name = "firefox-gnome-theme-sync";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
          pkgs.findutils
          pkgs.gawk
          pkgs.git
          pkgs.gnutar
          pkgs.gzip
          pkgs.util-linux
        ];
        text = builtins.readFile ./_sync.sh;
      };

      # Firefox only reads these directories at startup of each profile; %h is the user's home.
      firefoxRoots = [
        "%h/.config/mozilla/firefox"
        "%h/.mozilla/firefox"
      ];
    in
    {
      options.my.firefoxGnomeTheme.ref = lib.mkOption {
        type = lib.types.str;
        default = "master";
        description = ''
          Branch or tag of the theme repository to follow. The author keeps master on the
          current Firefox stable and leaves older Firefox versions as tags (v149, v150, ...),
          so pin a tag only if master breaks.
        '';
      };

      config = {
        programs.firefox.policies.Preferences = {
          # "user" because Firefox needs these before policies are applied as defaults.
          "toolkit.legacyUserProfileCustomizations.stylesheets" = {
            Value = true;
            Status = "user";
          };
          "svg.context-properties.content.enabled" = {
            Value = true;
            Status = "user";
          };
          # The rest of the theme's configuration/user.js.
          "browser.uidensity" = {
            Value = 0;
            Status = "default";
            Type = "number";
          };
          "browser.theme.dark-private-windows" = {
            Value = false;
            Status = "default";
          };
          "widget.gtk.rounded-bottom-corners.enabled" = {
            Value = true;
            Status = "default";
          };
        };

        # Runs on whichever user manager is up, so each user themes their own profiles.
        systemd.user.services.firefox-gnome-theme-update = {
          description = "Update the Firefox GNOME theme and apply it to every Firefox profile";
          environment.FIREFOX_GNOME_THEME_REF = cfg.ref;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe sync} update";
            Nice = 10;
            IOSchedulingClass = "idle";
            TimeoutStartSec = "15min";
          };
          # Offline at login is common: retry later instead of leaving the unit failed.
          unitConfig.StartLimitIntervalSec = 0;
        };

        systemd.user.timers.firefox-gnome-theme-update = {
          description = "Daily Firefox GNOME theme update";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnStartupSec = "2min";
            OnCalendar = "daily";
            RandomizedDelaySec = "1h";
            Persistent = true;
          };
        };

        systemd.user.services.firefox-gnome-theme-apply = {
          description = "Apply the cached Firefox GNOME theme to every Firefox profile";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe sync} apply";
            Nice = 10;
          };
          unitConfig.StartLimitIntervalSec = 0;
        };

        systemd.user.paths.firefox-gnome-theme-apply = {
          description = "Re-apply the Firefox GNOME theme when Firefox profiles change";
          wantedBy = [ "paths.target" ];
          pathConfig = {
            PathModified = firefoxRoots;
            Unit = "firefox-gnome-theme-apply.service";
          };
        };

        # The downloaded theme survives reboots; the profiles' own copies do too.
        environment.persistence."/persist".users = lib.genAttrs config.my.users (_: {
          directories = [ ".local/share/firefox-gnome-theme" ];
        });
      };
    };
}
