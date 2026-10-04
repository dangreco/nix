_: {
  flake.modules.homeManager.base = {
    home.stateVersion = "26.05";
    programs.home-manager.enable = true;
    nix.assumeXdg = true;
  };
}
