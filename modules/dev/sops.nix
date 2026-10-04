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
      sopsConfig = pkgs.writeText "sops.yaml" (
        builtins.toJSON {
          creation_rules = lib.mapAttrsToList (user: userAge: {
            path_regex = "secrets/users/${user}\\.yaml$";
            key_groups = [
              {
                age = [ keys.master ] ++ lib.mapAttrsToList (_: h: h.age) keys.hosts ++ [ userAge ];
              }
            ];
          }) keys.users;
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
              for f in secrets/users/*.yaml; do sops updatekeys --yes "$f"; done
            '';
          }
        );
      };

      checks.sops-config =
        pkgs.runCommand "sops-config-check" { }
          "diff -u ${sopsConfig} ${self + "/.sops.yaml"} && touch $out";
    };
}
