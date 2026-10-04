{ inputs, ... }:
{
  flake.modules.nixos.impermanence =
    { config, lib, ... }:
    {
      imports = [ inputs.impermanence.nixosModules.impermanence ];

      fileSystems."/persist".neededForBoot = true;

      boot.initrd.systemd.services.rollback-root = {
        description = "Reset btrfs root subvolume";
        wantedBy = [ "initrd.target" ];
        requires = [ "dev-mapper-crypted.device" ];
        after = [
          "dev-mapper-crypted.device"
          "systemd-cryptsetup@crypted.service"
        ];
        before = [ "sysroot.mount" ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";
        script = ''
          mkdir -p /btrfs_tmp
          mount -t btrfs -o subvol=/ /dev/mapper/crypted /btrfs_tmp
          delete_subvolume_recursively() {
            IFS=$'\n'
            for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
              delete_subvolume_recursively "/btrfs_tmp/$i"
            done
            btrfs subvolume delete "$1"
          }
          if [ -e /btrfs_tmp/old_root ]; then delete_subvolume_recursively /btrfs_tmp/old_root; fi
          if [ -e /btrfs_tmp/root ]; then mv /btrfs_tmp/root /btrfs_tmp/old_root; fi
          btrfs subvolume create /btrfs_tmp/root
          umount /btrfs_tmp
        '';
      };

      environment.persistence."/persist" = {
        hideMounts = true;
        directories = [
          "/var/log"
          "/var/lib/nixos"
          "/var/lib/systemd"
          "/etc/NetworkManager/system-connections"
          "/var/lib/NetworkManager"
        ];
        files = [ "/etc/machine-id" ];
        users = lib.genAttrs config.my.users (_: {
          directories = [
            ".local/state/nix"
            ".local/state/home-manager"
          ];
        });
      };

      systemd.services = lib.listToAttrs (
        map (
          name:
          let
            home = config.users.users.${name}.home;
          in
          lib.nameValuePair "home-manager-restore-${name}" {
            description = "Re-activate last standalone Home Manager generation for ${name}";
            wantedBy = [ "multi-user.target" ];
            wants = [ "nix-daemon.socket" ];
            after = [ "nix-daemon.socket" ];
            before = [
              "systemd-user-sessions.service"
              "display-manager.service"
            ];
            unitConfig.RequiresMountsFor = "${home}/.local/state/nix ${home}/.local/state/home-manager";
            path = [ config.nix.package ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              User = name;
              TimeoutStartSec = "5m";
              SyslogIdentifier = "hm-restore-${name}";
            };
            script = ''
              for p in "${home}/.local/state/nix/profiles/home-manager" "/nix/var/nix/profiles/per-user/${name}/home-manager"; do
                if [ -x "$p/activate" ]; then exec "$p/activate" --driver-version 1; fi
              done
              echo "no Home Manager generation for ${name}; nothing to restore"
            '';
          }
        ) config.my.users
      );
    };
}
