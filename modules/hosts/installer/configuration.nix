{
  config,
  inputs,
  self,
  ...
}:
let
  master = config.keys.master;
  nixos = config.flake.modules.nixos;
in
{
  flake.modules.nixos.installer =
    {
      lib,
      pkgs,
      modulesPath,
      ...
    }:
    {
      imports = [
        (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
        nixos.dan-git
      ];

      networking.hostName = "installer";
      nixpkgs.hostPlatform = "x86_64-linux";
      nixpkgs.config.allowUnfree = true;

      # Latest kernel for MT7925 Wi-Fi and Ryzen AI 300; ZFS breaks against it.
      boot.kernelPackages = pkgs.linuxPackages_latest;
      boot.supportedFilesystems.zfs = lib.mkForce false;
      boot.kernelParams = [
        "console=tty0"
        "console=ttyS0,115200"
      ];

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      users.users.root.openssh.authorizedKeys.keys = [ master ];

      environment.systemPackages = [
        pkgs.git
        pkgs.sbctl
        pkgs._1password-cli
        pkgs.nixos-facter
        self.packages.x86_64-linux.nix-install
      ];

      services.getty.helpLine = lib.mkForce "Run: sudo nix-install";
    };

  flake.nixosConfigurations.installer = inputs.nixpkgs.lib.nixosSystem {
    modules = [ nixos.installer ];
  };
}
