let
  user = {
    name = "Dan Greco";
    email = "git@dangre.co";
  };
in
{
  flake.modules.nixos.dan-git = {
    programs.git = {
      enable = true;
      config.user = user;
    };
    programs.ssh.knownHosts."github.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  };

  flake.modules.homeManager.dan-git.programs.git = {
    enable = true;
    settings.user = user;
  };
}
