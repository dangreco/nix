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
      hm.dan-git
      hm.dan-zed
    ];

    home.username = "dan";
    home.homeDirectory = "/home/dan";

    sops = {
      age.keyFile = "/run/secrets/users/dan/age-key";
      defaultSopsFile = self + "/secrets/users/dan.yaml";
      secrets."users/dan/home/smoke" = { };
    };
  };
}
