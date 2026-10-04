{
  config,
  inputs,
  self,
  ...
}:
let
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.dan = {
    imports = [
      hm.base
      inputs.sops-nix.homeManagerModules.sops
    ];

    home.username = "dan";
    home.homeDirectory = "/home/dan";

    programs.git = {
      enable = true;
      settings.user = {
        name = "Dan Greco";
        email = "git@dangre.co";
      };
    };

    sops = {
      age.keyFile = "/run/secrets/users/dan/age-key";
      defaultSopsFile = self + "/secrets/users/dan.yaml";
      secrets."users/dan/home/smoke" = { };
    };
  };
}
