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

  flake.modules.homeManager.onepassword =
    { config, lib, ... }:
    let
      items = config.my.onepassword.sshAgentItems;
    in
    {
      options.my.onepassword.sshAgentItems = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Items in the nix-hosts vault the 1Password SSH agent exposes, next to the
          Private vault. Normally this host's own key item, so the key the installer
          registered on GitHub is the one offered.
        '';
      };

      config = {
        programs.ssh = {
          enable = true;
          enableDefaultConfig = false;
          settings."*".IdentityAgent = "~/.1password/agent.sock";
        };

        # Setting this file replaces the agent's default key list, so keep Private.
        xdg.configFile."1Password/ssh/agent.toml" = lib.mkIf (items != [ ]) {
          force = true;
          text = ''
            [[ssh-keys]]
            vault = "Private"
          ''
          + lib.concatMapStrings (item: ''

            [[ssh-keys]]
            vault = "nix-hosts"
            item = "${item}"
          '') items;
        };
      };
    };
}
