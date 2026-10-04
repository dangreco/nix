{
  config,
  inputs,
  ...
}:
let
  master = config.keys.master;
  nixos = config.flake.modules.nixos;
  hm = config.flake.modules.homeManager;
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
        nixos.disk
        nixos.impermanence
        nixos.secure-boot
        nixos.sops
        nixos.flatpak
        nixos.podman
        nixos.openssh
        nixos.dan
        (modulesPath + "/profiles/qemu-guest.nix")
      ];

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

  flake.homeConfigurations."dan@smoke" = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    modules = [ hm.dan ];
  };
}
