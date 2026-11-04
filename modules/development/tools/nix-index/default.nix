{ inputs, ... }:
{
  # Part of my.devTools (../default.nix): nix-index with the prebuilt weekly database
  # from nix-index-database, so nothing is indexed locally.
  #  - fish's command-not-found handler names the package providing a missing command;
  #  - `nix-locate bin/foo` searches every file nixpkgs ships;
  #  - `, foo args` (comma) runs foo from whichever package provides it, without
  #    installing anything.
  # The database is a store path linked into ~/.cache/nix-index on activation, so it
  # needs no persistence and updates with `nix flake update nix-index-database`.
  flake.modules.homeManager.base =
    { config, ... }:
    {
      imports = [ inputs.nix-index-database.homeModules.default ];

      # The imported module turns nix-index on for everyone (mkDefault); follow
      # my.devTools instead.
      programs.nix-index.enable = config.my.devTools.enable;
      programs.nix-index-database.comma.enable = config.my.devTools.enable;
    };
}
