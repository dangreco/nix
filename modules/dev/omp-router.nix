_: {
  perSystem =
    { pkgs, ... }:
    {
      checks.omp-router = pkgs.runCommand "omp-router-tests" { nativeBuildInputs = [ pkgs.bun ]; } ''
        cp -r ${../development/ai/omp/_router} router
        chmod -R u+w router
        bun test router/*.test.mjs
        touch $out
      '';
    };
}
