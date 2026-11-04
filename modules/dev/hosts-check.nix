{ self, ... }:
{
  # Every nixosConfiguration's system closure as a check, so `nix flake check` (and CI)
  # fails when any host stops evaluating or building.
  perSystem =
    { lib, system, ... }:
    {
      checks =
        lib.mapAttrs' (name: host: lib.nameValuePair "host-${name}" host.config.system.build.toplevel)
          (
            lib.filterAttrs (_: host: host.pkgs.stdenv.hostPlatform.system == system) self.nixosConfigurations
          );
    };
}
