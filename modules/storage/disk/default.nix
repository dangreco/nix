{ inputs, ... }:
{
  flake.modules.nixos.base =
    { config, lib, ... }:
    let
      cfg = config.my.disk;
      mountOptions = [
        "compress=zstd"
        "noatime"
      ];
    in
    {
      imports = [ inputs.disko.nixosModules.disko ];

      options.my.disk.enable = lib.mkEnableOption "the disko layout (ESP, LUKS, btrfs subvolumes)";

      options.my.disk.device = lib.mkOption {
        type = lib.types.str;
        description = "Block device the disko layout is installed on.";
      };

      options.my.disk.swapSize = lib.mkOption {
        type = lib.types.nullOr (lib.types.strMatching "^[0-9]+[KMGTP]$");
        default = null;
        example = "32G";
        description = "Size of the btrfs swapfile /swap/swapfile inside LUKS (hibernation target); null = no disk swap.";
      };

      config.disko.devices.disk.main = lib.mkIf cfg.enable {
        type = "disk";
        inherit (cfg) device;
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted";
                passwordFile = "/tmp/secret.key";
                settings.allowDiscards = true;
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    "/root" = {
                      mountpoint = "/";
                      inherit mountOptions;
                    };
                    "/nix" = {
                      mountpoint = "/nix";
                      inherit mountOptions;
                    };
                    "/persist" = {
                      mountpoint = "/persist";
                      inherit mountOptions;
                    };
                  }
                  // lib.optionalAttrs (cfg.swapSize != null) {
                    # No compress= here: swapfiles must not be compressed.
                    "/swap" = {
                      mountpoint = "/swap";
                      mountOptions = [ "noatime" ];
                      swap.swapfile.size = cfg.swapSize;
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
}
