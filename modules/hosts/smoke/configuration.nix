{
  config,
  inputs,
  ...
}:
let
  master = config.keys.master;
  nixos = config.flake.modules.nixos;
in
{
  keys.hosts.smoke = {
    age = "age17ky9djzzhgrng078w82rk2vdgdfwmduqlyt735d8vt786t0ptansj3vpnt";
    opItem = "nix-host-smoke";
  };

  flake.modules.nixos.smoke =
    { modulesPath, ... }:
    {
      imports = [
        nixos.base
        nixos.dan
        (modulesPath + "/profiles/qemu-guest.nix")
      ];

      my = {
        disk.enable = true;
        impermanence.enable = true;
        secureBoot.enable = true;
        flatpak.enable = true;
        podman.enable = true;
        openssh.enable = true;
      };

      networking.hostName = "smoke";
      nixpkgs.hostPlatform = "x86_64-linux";
      my.disk.device = "/dev/vda";

      boot.kernelParams = [
        "console=tty1"
        "console=ttyS0,115200"
      ];

      users.users.root.openssh.authorizedKeys.keys = [ master ];
    };

  flake.nixosConfigurations.smoke = inputs.nixpkgs.lib.nixosSystem {
    modules = [ nixos.smoke ];
  };
}
