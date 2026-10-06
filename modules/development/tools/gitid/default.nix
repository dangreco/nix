{ self, ... }:
{
  # gitid (package.nix): switches git identities per directory through a fish hook.
  # User-only: home-manager.users.<name>.my.gitid.enable.
  flake.modules.homeManager.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      gitid = self.packages.${pkgs.stdenv.hostPlatform.system}.gitid;
    in
    {
      options.my.gitid.enable = lib.mkEnableOption "gitid, per-directory git identities";

      config = lib.mkIf config.my.gitid.enable {
        home.packages = [ gitid ];

        programs.fish.interactiveShellInit = ''
          ${lib.getExe gitid} hook fish | source
          ${lib.getExe gitid} completions fish | source
          ${lib.getExe gitid} sync >/dev/null 2>&1
        '';

        # The identities and directory mappings.
        home.persistence."/persist".directories = [
          ".config/gitid"
          ".local/share/gitid"
        ];
      };
    };
}
