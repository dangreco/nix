_: {
  flake.modules.nixos.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.my.hibernate.enable = lib.mkEnableOption "suspend-then-hibernate to the disk swapfile";

      config = lib.mkIf config.my.hibernate.enable {
        assertions = [
          {
            assertion = config.my.disk.swapSize != null;
            message = "my.hibernate needs my.disk.swapSize (disk swapfile for the hibernation image).";
          }
          {
            assertion = !config.security.protectKernelImage;
            message = "security.protectKernelImage adds nohibernate; it can't be combined with my.hibernate.";
          }
        ];

        # Resume goes through the HibernateLocation EFI variable in the systemd
        # initrd; boot.resumeDevice must stay unset (it would add resume= with
        # offset 0, wrong for a swapfile).
        systemd.sleep.settings.Sleep.HibernateDelaySec = "2h";

        # Every suspend (lid, GNOME idle, menu) becomes suspend-then-hibernate.
        systemd.services.systemd-suspend.serviceConfig.ExecStart = [
          ""
          "${config.systemd.package}/lib/systemd/systemd-sleep suspend-then-hibernate"
        ];

        environment.etc."systemd/system-sleep/hibernate-boot-current".source =
          pkgs.writeShellScript "hibernate-boot-current" ''
            # Before hibernating, point the next boot at the running generation so the
            # image is resumed by the same kernel; clear it again afterwards.
            # SYSTEMD_SLEEP_ACTION is the phase actually running (suspend-then-hibernate
            # runs "suspend", then "hibernate").
            case "$1:''${SYSTEMD_SLEEP_ACTION:-$2}" in
              pre:hibernate | pre:hybrid-sleep)
                exec ${config.systemd.package}/bin/bootctl set-oneshot @current ;;
              post:hibernate | post:hybrid-sleep | post:suspend-after-failed-hibernate)
                exec ${config.systemd.package}/bin/bootctl set-oneshot "" ;;
            esac
          '';
      };
    };
}
