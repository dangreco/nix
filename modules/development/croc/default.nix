_: {
  # croc: send files and text to another machine with a one-time code phrase.
  # User-only: home-manager.users.<name>.my.croc.enable.
  flake.modules.homeManager.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.my.croc.enable = lib.mkEnableOption "croc, encrypted file and text transfer between machines";

      config = lib.mkIf config.my.croc.enable {
        home.packages = [ pkgs.croc ];
      };
    };
}
