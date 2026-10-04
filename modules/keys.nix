{ config, lib, ... }:
{
  options.keys = {
    master = lib.mkOption {
      type = lib.types.str;
      description = "Public half of the 1Password-held master SSH key (ssh-ed25519 AAAA…, no comment).";
    };
    masterOpRef = lib.mkOption {
      type = lib.types.str;
      description = "op:// reference to the master private key in OpenSSH format.";
    };
    hosts = lib.mkOption {
      default = { };
      description = "Per-host sops recipients: ssh-to-age of the host's /persist/etc/ssh/ssh_host_ed25519_key, and its 1Password item in vault nix-hosts.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            age = lib.mkOption { type = lib.types.str; };
            opItem = lib.mkOption { type = lib.types.str; };
          };
        }
      );
    };
    users = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Per-user age recipient (public key of the age key stored at users/<u>/age-key).";
    };
  };

  config.keys = {
    master = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILPiUdiWhK0hUw/pk0yntIDEkIOXT74mZIuOxHPprTPV"; # 1Password: Private/master.2026.10.03
    masterOpRef = "op://Private/master.2026.10.03/private key?ssh-format=openssh";
  };

  config.flake.keys = config.keys;
}
