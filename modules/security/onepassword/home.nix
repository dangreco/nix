_: {
  flake.modules.homeManager.onepassword =
    { config, lib, ... }:
    let
      items = config.my.onepassword.sshAgentItems;
    in
    {
      options.my.onepassword.enable = lib.mkEnableOption "1password integration" // {
        default = true;
      };

      options.my.onepassword.sshAgentItems = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Items in the nix-hosts vault the 1Password SSH agent exposes, next to the
          Private vault. Normally this host's own key item, so the key the installer
          registered on GitHub is the one offered.
        '';
      };

      config = lib.mkIf config.my.onepassword.enable {
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
