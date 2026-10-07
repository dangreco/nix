{ inputs, ... }:
{
  # Root is a fresh btrfs subvolume on every boot; only what features list under
  # /persist survives. The persistence options are always declared, so any feature can
  # list paths unconditionally; they only take effect while this is enabled.
  flake.modules.nixos.base =
    { config, lib, ... }:
    let
      cfg = config.my.impermanence;
    in
    {
      # Also hands every Home Manager user the home.persistence option.
      imports = [ inputs.impermanence.nixosModules.impermanence ];

      options.my.impermanence.enable = lib.mkEnableOption "the root wipe at boot and /persist";

      config = lib.mkMerge [
        {
          environment.persistence."/persist".enable = cfg.enable;
          home-manager.sharedModules = [
            {
              home.persistence."/persist" = {
                inherit (cfg) enable;
                # Keep the bind mounts out of Nautilus/gvfs as ejectable drives, like the system ones.
                hideMounts = true;
                # Bind mounts have a non-/ root, so GIO treats them as system-internal and refuses to trash; x-gvfs-trash overrides that.
                allowTrash = true;
                # Where upstream installers (zed, omp) put their binaries; one entry here
                # since impermanence rejects a path listed twice.
                directories = [ ".local/bin" ];
              };
            }
          ];
        }

        (lib.mkIf cfg.enable {
          fileSystems."/persist".neededForBoot = true;

          boot.initrd.systemd.services.rollback-root = {
            description = "Reset btrfs root subvolume";
            wantedBy = [ "initrd.target" ];
            requires = [ "dev-mapper-crypted.device" ];
            after = [
              "dev-mapper-crypted.device"
              "systemd-cryptsetup@crypted.service"
              # Never mutate the filesystem before a pending hibernation image is resumed.
              "systemd-hibernate-resume.service"
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

          # Home Manager needs nothing here: home-manager-<user>.service re-activates
          # the generation of the running system on every boot.
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
          };
        })
      ];
    };
}
