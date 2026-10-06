{ inputs, ... }:
{
  # Always on: user passwords and age keys come from sops. Home Manager users get the
  # sops-nix HM module too, for secrets decrypted with their own age key.
  flake.modules.nixos.base = {
    imports = [ inputs.sops-nix.nixosModules.sops ];

    sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
    sops.gnupg.sshKeyPaths = [ ];

    home-manager.sharedModules = [ inputs.sops-nix.homeManagerModules.sops ];
  };
}
