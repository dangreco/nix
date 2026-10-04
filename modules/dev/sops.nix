{ config, self, ... }:
let
  inherit (config) keys;
in
{
  perSystem =
    { pkgs, lib, ... }:
    let
      # JSON is valid YAML, so sops reads this as .sops.yaml.
      # Every host decrypts every user file: the password and age key are
      # NixOS-level secrets. The user's own age key lets Home Manager decrypt.
      # secrets/networks.yaml is shared by all users and hosts; only hosts and
      # the master key can decrypt it (NetworkManager runs as root).
      hostAges = lib.mapAttrsToList (_: h: h.age) keys.hosts;
      sopsConfig = pkgs.writeText "sops.yaml" (
        builtins.toJSON {
          creation_rules =
            lib.mapAttrsToList (user: userAge: {
              path_regex = "secrets/users/${user}\\.yaml$";
              key_groups = [
                {
                  age = [ keys.master ] ++ hostAges ++ [ userAge ];
                }
              ];
            }) keys.users
            ++ [
              {
                path_regex = "secrets/networks\\.yaml$";
                key_groups = [
                  {
                    age = [ keys.master ] ++ hostAges;
                  }
                ];
              }
            ];
        }
      );
    in
    {
      apps.sops-config = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "sops-config";
            runtimeInputs = [
              pkgs.sops
              pkgs.coreutils
            ];
            text = ''
              export SOPS_AGE_SSH_PRIVATE_KEY_CMD='op read "${keys.masterOpRef}"'
              install -m 0644 ${sopsConfig} .sops.yaml
              shopt -s nullglob
              for f in secrets/users/*.yaml secrets/networks.yaml; do sops updatekeys --yes "$f"; done
            '';
          }
        );
      };

      checks.sops-config =
        pkgs.runCommand "sops-config-check" { }
          "diff -u ${sopsConfig} ${self + "/.sops.yaml"} && touch $out";
    };
}
