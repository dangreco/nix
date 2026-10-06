_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.gitid = pkgs.rustPlatform.buildRustPackage {
        pname = "gitid";
        version = "main";
        src = pkgs.fetchFromGitHub {
          owner = "dgreco-at-speer";
          repo = "gitid";
          rev = "3a1197147f61892fca7b31e0a7ad2aee827166ea";
          hash = "sha256-ITLEG1G4wWWiFwy239CuVivhTEr1w676YkltC4BtbUw=";
        };
        cargoHash = "sha256-QJwX2xegcQNzTulPAkcp2jHmdw2xZJqFNS3EycWbtAo=";
        nativeBuildInputs = [
          pkgs.openssh
          pkgs.git
          pkgs.installShellFiles
        ];
        postInstall = ''
          installShellCompletion --cmd gitid \
            --bash <($out/bin/gitid completions bash) \
            --fish <($out/bin/gitid completions fish) \
            --zsh <($out/bin/gitid completions zsh)
        '';
        meta = with pkgs.lib; {
          description = "Switch between git identities per directory";
          homepage = "https://github.com/dgreco-at-speer/gitid";
          license = licenses.mit;
          mainProgram = "gitid";
        };
      };
    };
}
