{ self, ... }:
{
  flake.modules.nixos.work-git = {
    programs.git.enable = true;
    programs.ssh.knownHosts."github.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  };

  flake.modules.homeManager.work-git = { config, pkgs, ... }: {
    home.packages = [
      self.packages.${pkgs.system}.gitid
      pkgs.gh
      pkgs.worktrunk
    ];

    programs.git = {
      enable = true;
      includes = [
        { path = config.sops.secrets."git-credentials".path; }
        { path = "~/.config/git/config.local"; }
      ];
    };

    programs.fish.interactiveShellInit = ''
      ${self.packages.${pkgs.system}.gitid}/bin/gitid hook fish | source
    '';

    sops.secrets."git-credentials" = {
      sopsFile = self + "/secrets/users/work.yaml";
    };
  };
}
