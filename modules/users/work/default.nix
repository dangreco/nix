{ config, self, ... }:
let
  master = config.keys.master;
in
{
  keys.users.work = "age1n9qy2004um4ka960r03vsegmgg6530kx5gh3966nt9z3ky8vg46s37fw7r";

  flake.modules.nixos.work =
    { config, lib, ... }:
    {
      my.users = [ "work" ];

      programs.git.enable = true;
      programs.ssh.knownHosts."github.com".publicKey =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

      sops.secrets."users/work/password" = {
        sopsFile = self + "/secrets/users/work.yaml";
        neededForUsers = true;
      };
      sops.secrets."users/work/age-key" = {
        sopsFile = self + "/secrets/users/work.yaml";
        owner = "work";
      };

      users.users.work = {
        isNormalUser = true;
        uid = 1001;
        description = "Work";
        extraGroups = [
          "wheel"
          "networkmanager"
        ];
        hashedPasswordFile = config.sops.secrets."users/work/password".path;
        openssh.authorizedKeys.keys = [ master ];
      };

      home-manager.users.work =
        { config, pkgs, ... }:
        {
          # Features; each also needs the host side on (my.<feature>.enable) to apply.
          my = {
            gnome.enable = true;
            onepassword.enable = true;
            devTools.enable = true;
            zed.enable = true;
            omp.enable = true;
            gitid.enable = true;
          };

          # Own client key for llm.dangre.co (separate from dan's, revocable on its own).
          my.omp.llm = {
            enable = true;
            apiKeySecret = "users/work/home/omp/llm-api-key";
          };

          # Same native judge as Dan; credentials are encrypted for this user's
          # own sops recipients. Chat inference keeps Work's separate proxy key.
          my.omp.models.providers.gemini-decisions = {
            baseUrl = "https://generativelanguage.googleapis.com/v1beta";
            api = "google-decisions";
            apiKey = config.sops.placeholder."users/work/home/omp/gemini-decisions-api-key";
            auth = "apiKey";
            models = [
              {
                id = "gemini-decision-1";
                name = "Gemini Decision 1";
                kind = "judge";
                reasoning = false;
                input = [
                  "text"
                  "image"
                ];
                contextWindow = 262144;
              }
            ];
          };
          my.omp.settings.modelRoles.judge = lib.mkDefault "gemini-decisions/gemini-decision-1";
          my.omp.router.enable = true;

          home.packages = [
            pkgs.gh
            pkgs.worktrunk
          ];

          # Extra config from the sops-held git-credentials file and an unmanaged config.local.
          # useConfigOnly: outside a gitid-mapped directory git refuses to commit instead of
          # inventing work@mezcal as the author.
          programs.git = {
            enable = true;
            settings.user.useConfigOnly = true;
            includes = [
              { path = config.sops.secrets."git-credentials".path; }
              { path = "~/.config/git/config.local"; }
            ];
          };

          sops = {
            age.keyFile = "/run/secrets/users/work/age-key";
            defaultSopsFile = self + "/secrets/users/work.yaml";
            secrets."git-credentials" = { };
            secrets."users/work/home/omp/gemini-decisions-api-key" = { };
          };

          dconf.settings."org/gnome/shell" = {
            favorite-apps = lib.mkAfter [ "com.slack.Slack.desktop" ];
          };

          home.persistence."/persist".directories = [
            "Documents"
            "Downloads"
            "Music"
            "Pictures"
            "Videos"
            "projects"
            {
              directory = ".ssh";
              mode = "0700";
            }
          ];
        };
    };
}
