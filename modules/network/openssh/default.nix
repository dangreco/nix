_: {
  flake.modules.nixos.base =
    { config, lib, ... }:
    {
      options.my.openssh.enable = lib.mkEnableOption "the OpenSSH server";

      config = lib.mkIf config.my.openssh.enable {
        services.openssh = {
          enable = true;
          hostKeys = [
            {
              path = "/persist/etc/ssh/ssh_host_ed25519_key";
              type = "ed25519";
            }
          ];
          settings = {
            PasswordAuthentication = false;
            KbdInteractiveAuthentication = false;
            PermitRootLogin = "prohibit-password";
          };
        };
      };
    };
}
