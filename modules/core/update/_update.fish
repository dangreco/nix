complete -c update -f
complete -c update -n 'not __fish_seen_argument -l pull' -l pull -d 'Fast-forward ~/projects/nix to the latest origin/dev first'
complete -c update -n 'not __fish_seen_argument -l verbose' -l verbose -d 'Print the full output of every step'
complete -c update -s h -l help -d 'Show usage'
