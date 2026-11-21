_: {
  perSystem =
    { pkgs, ... }:
    {
      checks.omp-router =
        pkgs.runCommand "omp-router-tests"
          {
            nativeBuildInputs = [ pkgs.bun ];
          }
          ''
            mkdir omp
            cp -r ${../development/ai/omp/_router} omp/_router
            cp ${../development/ai/omp/_sync.mjs} omp/_sync.mjs
            cp ${../development/ai/omp/_sync.test.mjs} omp/_sync.test.mjs
            chmod -R u+w omp
            cd omp
            export HOME=$TMPDIR
            bun test ./_router/*.test.mjs ./_sync.test.mjs
            touch $out
          '';
    };
}
