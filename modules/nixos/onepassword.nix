_: {
  flake.modules.nixos.onepassword =
    { config, lib, ... }:
    {
      programs._1password.enable = true;
      programs._1password-gui = {
        enable = true;
        polkitPolicyOwners = config.my.users;
      };

      environment.persistence."/persist".users = lib.genAttrs config.my.users (_: {
        directories = [ ".config/1Password" ];
      });
    };

  flake.modules.homeManager.onepassword = {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings."*".IdentityAgent = "~/.1password/agent.sock";
    };
  };
}
