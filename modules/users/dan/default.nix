{ config, self, ... }:
let
  master = config.keys.master;
  nixos = config.flake.modules.nixos;

  git = {
    name = "Dan Greco";
    email = "git@dangre.co";
  };
in
{
  keys.users.dan = "age1z623ah3syzzae9lauvukws96w3lsr99tq2a05cc8w7ktnv7mv3lq2sj50p";

  # System-wide git identity and GitHub host key; also used by the installer ISO.
  flake.modules.nixos.dan-git = {
    programs.git = {
      enable = true;
      config.user = git;
    };
    programs.ssh.knownHosts."github.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  };

  flake.modules.nixos.dan =
    { config, ... }:
    {
      imports = [ nixos.dan-git ];

      my.users = [ "dan" ];
      my.githubUsers.dan = "dangreco";

      sops.secrets."users/dan/password" = {
        sopsFile = self + "/secrets/users/dan.yaml";
        neededForUsers = true;
      };
      sops.secrets."users/dan/age-key" = {
        sopsFile = self + "/secrets/users/dan.yaml";
        owner = "dan";
      };

      users.users.dan = {
        isNormalUser = true;
        uid = 1000;
        description = "Dan Greco";
        extraGroups = [
          "wheel"
          "networkmanager"
        ];
        hashedPasswordFile = config.sops.secrets."users/dan/password".path;
        openssh.authorizedKeys.keys = [ master ];
      };

      home-manager.users.dan =
        { config, ... }:
        let
          # Same model shape for all three; only the limits differ.
          proxyModel = id: name: contextWindow: maxTokens: {
            inherit
              id
              name
              contextWindow
              maxTokens
              ;
            compat.maxTokensField = "max_tokens";
          };
        in
        {
          # Features; each also needs the host side on (my.<feature>.enable) to apply.
          my = {
            gnome.enable = true;
            onepassword.enable = true;
            devTools.enable = true;
            zed.enable = true;
            omp.enable = true;
          };

          # URL and key come from sops; omp renders them into models.yml.
          my.omp.models.providers.proxy = {
            baseUrl = config.sops.placeholder."users/dan/home/omp/base-url";
            api = "openai-completions";
            apiKey = config.sops.placeholder."users/dan/home/omp/api-key";
            models = [
              (proxyModel "opus" "Opus" 1000000 131072)
              (proxyModel "sonnet" "Sonnet" 1000000 131072)
              (proxyModel "haiku" "Haiku" 200000 65536)
            ];
          };

          # Bundled z.ai catalog; only the key is overridden, from sops.
          my.omp.models.providers.zai.apiKey = config.sops.placeholder."users/dan/home/omp/zai-api-key";

          # Claude (via proxy) -> GLM. A model-keyed chain applies in every role.
          # Context sizes are matched: 1M models fall back to 1M GLMs, haiku to 200K.
          # glm-5.2/5.3 only take high/max thinking, so the suffix is explicit.
          my.omp.settings.retry.fallbackChains = {
            "proxy/opus" = [
              "zai/glm-5.3:high"
              "zai/glm-5.2:high"
            ];
            "proxy/sonnet" = [
              "zai/glm-5.2:high"
              "zai/glm-5.1"
            ];
            "proxy/haiku" = [
              "zai/glm-5-turbo"
              "zai/glm-4.7-flashx"
            ];
          };

          programs.git = {
            enable = true;
            settings.user = git;
          };

          sops = {
            age.keyFile = "/run/secrets/users/dan/age-key";
            defaultSopsFile = self + "/secrets/users/dan.yaml";
            secrets = {
              "users/dan/home/smoke" = { };
              "users/dan/home/omp/base-url" = { };
              "users/dan/home/omp/api-key" = { };
              "users/dan/home/omp/zai-api-key" = { };
            };
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
