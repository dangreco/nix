{ self, ... }:
{
  # `update [--local]`: apply the latest release (main), or the local checkout. See _update.sh.
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.update ];
    };
}
