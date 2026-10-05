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
  flake.modules.homeManager.work = {
    imports = [
      hm.base
      inputs.sops-nix.homeManagerModules.sops
      hm.work-git
      hm.work-zed
    ];

    home.username = "work";
    home.homeDirectory = "/home/work";

    sops = {
      age.keyFile = "/run/secrets/users/work/age-key";
      defaultSopsFile = self + "/secrets/users/work.yaml";
      secrets."users/work/home/smoke" = { };
    };
  };
}
