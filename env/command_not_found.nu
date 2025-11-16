use ./consts.nu *
export def main [
    cmd: path
] {
    (
        ^nix-locate
        "--db" $CNF_DB
        "--minimal"
        "--no-group"
        "--type" "x"
        "--type" "s"
        "--whole-name"
        "--at-root"
        $"/bin/($cmd)"
    )
    | lines
    | where {|s| $s !~ '\..*\.'}
    | compact --empty
    | sort-by -c {|a, b|
        if $a == $cmd {
            true
        } else if $b == $cmd {
            false
        } else {
            $a < $b
        }
    }
}
export-env {
    $env.cnf.maxpkgs = $env.cnf?.maxpkgs? | default 3
    $env.cnf.registry = $env.cnf?.registry? | default "nixpkgs"
    let cnf = {|pkgs|
        let has_extras = if ($pkgs | length) > ($env.cnf.maxpkgs) {
            ["  ..."]
        }
        [
            $"The program is currently not installed. Use one of the following:"
            ...(
                $pkgs
                | first $env.cnf.maxpkgs
                | each {|pkg| $"  ($env.cnf.registry)#($pkg)"}
            )
            ...($has_extras)
        ] | str join "\n"
    }
    $env.config.hooks.command_not_found = { |cmd_name|
        if not ($CNF_DB | path exists) {
            error make -u {
                msg: "Please use `nix create-index` to build the index"
                label: {
                    text: $"Directory not found: ($CNF_DB)"
                    span: (metadata $CNF_DB).span
                }
            }
        }
        match (main $cmd_name) {
            null => {
                return $"Command not found: ($cmd_name)"
            }
            $x => { return (do $cnf $x) }
        }
    }
}
