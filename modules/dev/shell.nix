{ config, ... }:
let
  inherit (config) keys;
in
{
  perSystem =
    {
      config,
      pkgs,
      ...
    }:
    {
      devShells.default = pkgs.mkShell {
        inputsFrom = [ config.pre-commit.devShell ];
        packages = [
          pkgs.sops
          pkgs.age
          pkgs.ssh-to-age
          pkgs.mkpasswd
          pkgs.jq
          pkgs.yq-go
          pkgs.git
        ];
        SOPS_AGE_SSH_PRIVATE_KEY_CMD = "op read \"${keys.masterOpRef}\"";
      };
    };
}
