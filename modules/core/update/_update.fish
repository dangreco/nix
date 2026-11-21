complete -c update -f
complete -c update -n 'not __fish_seen_argument -l local' -l local -d 'Apply ~/projects/dangreco/nix instead of the latest release'
complete -c update -n 'not __fish_seen_argument -l verbose' -l verbose -d 'Print the full output of every step'
complete -c update -s h -l help -d 'Show usage'
