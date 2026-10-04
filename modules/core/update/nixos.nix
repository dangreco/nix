{ self, ... }:
{
  # `update [--pull]`: apply ~/projects/nix to this machine. See _update.sh.
  flake.modules.nixos.update =
    { pkgs, ... }:
    {
      environment.systemPackages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.update ];
    };
}
