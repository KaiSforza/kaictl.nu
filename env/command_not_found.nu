const nix_db = [$nu.cache-dir "nix-index-not-found"] | path join | path expand
const pacman_db = [$nu.cache-dir "pacman-not-found.db"] | path join | path expand

# Creates the nix-locate database
#
# Makes a very quickly queriable database that only stores the binaries.
export def "nix create-index" [
    db: path = $nix_db
]: nothing -> nothing {
    log info "Updating the file data..."
    mkdir $db
    let backup_db = $"($db).(date now | format date '%J%Q')"
    if ($db | path exists) {
        log info $"Backing up current db to ($backup_db)"
        mv -v $db $backup_db
        mkdir $db
    }
    try {
        cd $db
        (
            nix-index
            --db $db
            -c 3
            --filter-prefix '/bin/'
        )
    } catch {|e|
        if ($backup_db | path exists) {
            log error $"Restoring database..."
            mv -v $backup_db $db
        }
        error make {
            msg: "Failed to update the file info"
            # inner: [$e] # TODO: add this as a proper inner error
            inner: [($e.json | from json)]
            labels: [
                {text: "" span: (metadata $db).span}
            ]
        }
    }
}

# Find a nix package
#
# Uses the small version of the database created by `nix create-index`
export def "nix locate" [
    cmd_name: string # command name to search for
] {
    if not ($nix_db | path exists) {
        if $env.cnf.auto {
            nix create-index
        } else {
            error make {
                msg: $"Command `($cmd_name)` not found"
                labels: [
                    {text: "" span: (metadata $cmd_name).span}
                    {text: $"Directory not found: ($nix_db)" span: (metadata $nix_db).span}
                ]
                help: "Please use `nix create-index` to build the index"
            }
        }
    }
    (
        ^nix-locate
        "--db" $nix_db
        "--minimal"
        "--no-group"
        "--type" "x" "--type" "s"
        "--whole-name"
        "--at-root"
        $"/bin/($cmd_name)"
    )
    | lines
    | where {|s| $s !~ '\..*\.'}
    | parse '{p}.{_}'
    | get p
}

# Create an index of pacman packages
#
# Saves pacman packages to an sqlite database for easy, fast queries. Squashes
# it a little bit by grouping things by repo/package/version. Only stores the
# binary paths, using this both core and extra it's only about 0.75mb.
export def "pacman create-index" [
    db: path = $pacman_db
]: nothing -> nothing {
    log info "Updating the pacman file data..."
    mkdir ($db | path dirname)
    let backup_db = $"($db).(date now | format date '%J%Q')"
    if ($db | path exists) {
        log info $"Backing up current db to ($backup_db)"
        mv -v $db $backup_db
    }
    try {
        let tmpfiles = mktemp -d
        log info "^pamcan --files --refresh"
        ^pamcan --files --refresh --dbpath $tmpfiles --logfile /dev/null --root $tmpfiles
        log info "Getting all files in common executable file locations"
        ^pacman -Fx '^(|usr)/s?bin/.+' --machinereadable
        | lines
        | split column (char nul) repo package version file
        | group-by repo package version --to-table
        | rename --column {items: files}
        | upsert files {|i| $i.items.file? | default []}
        | into sqlite $db -t pacman
        log info $"Saved to sqlite database ($db)"
    } catch {|e|
        if ($backup_db | path exists) {
            log error $"Restoring database..."
            mv -v $backup_db $db
        }
        error make {
            msg: "Failed to update the file info"
            # inner: [$e] # TODO: add this as a proper inner error
            inner: [($e.json | from json)]
            labels: [
                {text: "" span: (metadata $db).span}
            ]
        }
    }
}

# A speedy version of `pacman -Fy`
#
# Backed by an sqlite database so that each `.files` file doesn't need to be
# extracted and then searched.
export def "pacman locate" [
    cmd_name: string # command name to search for
] {
    if not ($pacman_db | path exists) {
        if $env.cnf.auto {
            pacman create-index
        } else {
            error make {
                msg: $"Command `($cmd_name)` not found"
                labels: [
                    {text: "" span: (metadata $cmd_name).span}
                    {text: $"File not found: ($pacman_db)" span: (metadata $pacman_db).span}
                ]
                help: "Please use `pacman create-index` to build the index"
            }
        }
    }
    open $pacman_db
    | (
        query db --params [$'%/($cmd_name)"%'] # already have all binaries, just need last item
        "select package from pacman where files like ? "
    )
    | get package
}

export def main [
    cmd_name: string # command to search for
] {
    # find all the known checkers
    let checkers: list<string> = which -a ...[
        nix-locate
        pacman
    ]
    | where type == "external" # Only use external commands for this
    | get -o command
    | uniq # Get only one of each even though we used 'all'

    # Run each checker in parallel
    let cmds = $checkers
    | par-each --keep-order {|cmd|
        match $cmd {
            "nix-locate" => {mgr: nix pkgs: (nix locate $cmd_name) cmd: $"nix profile add ($env.cnf.registry)#"},
            "pacman" => {mgr: pacman pkgs: (pacman locate $cmd_name) cmd: "pacman -S "},
            # TODO fedora
            # TODO ubuntu
            # TODO ...others
            # Default empty
            _ => {},
        }
    }

    $cmds
    | each --flatten {|k|
        (
            $k.pkgs | sort-by -c {|a, b|
                if $a == $cmd_name {
                    true
                } else if $b == $cmd_name {
                    false
                } else {
                    $a < $b
                }
            }
            | each {|p| $"($k.cmd)($p)"}
            | enumerate
        )
    }
    | sort-by index item
    | get item
}

export-env {
    $env.cnf.maxpkgs = $env.cnf?.maxpkgs? | default 3
    $env.cnf.auto = true
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
                | each {|pkg| $"  ($pkg)"}
            )
            ...($has_extras)
        ] | str join "\n"
    }
    $env.config.hooks.command_not_found = { |cmd_name|
        if ($cmd_name | str contains '/') {
            error make {
                code: "nu::shell::cmd_file"
                msg: (
                    if ($cmd_name | path exists) {"Path is not runnable."
                    } else {"File doesn't exist."}
                )
                labels: [
                    {text: "" span: (metadata $cmd_name).span}
                ]
            }
        }
        error make {
            code: "nu::shell::cmd_not_found"
            msg: $"Command `($cmd_name)` not found"
            labels: [
                {text: "" span: (metadata $cmd_name).span}
            ]
            help: (
                match (main $cmd_name) {
                    [] => null
                    $x => (do $cnf $x)
                }
            )
        }
    }
}


