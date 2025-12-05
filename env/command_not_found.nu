const nix_db_: path = [$nu.cache-dir "nix-not-found"] | path join
const nix_db: path = [$nu.cache-dir "nix-not-found.db"] | path join
const pacman_db: path = [$nu.cache-dir "pacman-not-found.db"] | path join
const DB: path = $nu.cache-dir | path join "command-not-found.db"

use std/log

# Locate a binary
@example "find a package" {cmd locate nix ls} --result [
    uutils-coreutils-noprefix
    busybox
    toybox
    coreutils
    ...
]
export def "cmd locate" [
    manager: string@[pacman nix]
    cmd_name: string
    --verbose
    --db: path = $DB
]: [
    nothing -> list<string>
    nothing -> table
] {
    if not ($db | path exists) {
        error make {
            msg: $"Command `($cmd_name)` not found"
            labels: [
                {text: "" span: (metadata $cmd_name).span}
                {text: $"File not found: ($db)" span: (metadata $db).span}
            ]
            help: $"Please use `($manager) create-index ($db)` to build the index"
        }
    }
    let manager = match $manager {
        nix => "nixpkgs"
        pacman => "pacman"
        _ => {error make {msg: "invalid manager"}}
    }
    let pkgs = open $db
    | (
        query db --params [$'bin/($cmd_name)' $'usr/bin/($cmd_name)'] # already have all binaries, just need last item
        $"select * from ($manager) where files = ? or files = ?"
    )
    if $verbose {
        $pkgs
    } else {
        $pkgs
        | get package
    }
}



# Creates the nix-locate database
#
# Makes a very quickly queriable database that only stores the binaries.
@example "Create the initial index" {nix create-index}
@example "Create the initial index at a specific location" {nix create-index /tmp/db/}
export def "nix create-index" [
    db: path = $nix_db
]: nothing -> nothing {
    log info "Updating the file data..."
    let backup_db = $"($db).(date now | format date '%J%Q')"
    if ($db | path exists) {
        log info $"Backing up current db to ($backup_db)"
        mv $db $backup_db
    }
    try {
        if ($nix_db_ | path join "files" | path exists) {
            log info "Already have a database, using that."
        } else {
            (
                nix-index
                --db $nix_db_
                -f https://github.com/NixOS/nixpkgs/archive/refs/heads/nixos-unstable.tar.gz
                -c 3
                --filter-prefix '/bin/'
            )
        }
        log info "Locating all files in the nix-index files database"
        nix-locate --db $nix_db_ --regex '' --all --type x --type s --no-group
        | from ssv --noheaders --minimum-spaces 1
        | rename package size type path
        | each {|p|
          if $p.package !~ '\(.+\)' {
            let path_parts = $p.path | path split
            let store = $path_parts | take 3 | path join
            let hash_ver = $path_parts.3 | split row '-' --number 2
            let hash = $hash_ver.0
            let ver = $hash_ver.1
            let file = $path_parts | skip 4 | path join
            {
              repo: "nixpkgs"
              package: ($p.package | split row '.' | drop | str join '.')
              version: $ver
              files: $file
              hash: $hash
            }
          }
        }
        | into sqlite $db --table-name "nixpkgs"

        log debug "Optimizing table."
        open $db
        | query db "CREATE INDEX idx_nixpkgs
            ON nixpkgs(files);"

    } catch {|e|
        if ($backup_db | path exists) {
            log error $"Restoring database..."
            mv $backup_db $db
        }
        error make {
            msg: "Failed to update the file info for nixpkgs"
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
# Uses the small version of the database created by `nix create-index`. The
# ordering of the results is not guaranteed.
@example "find a package" {nix locate ls} --result [
    uutils-coreutils-noprefix
    busybox
    ...
]
export def "nix locate" [
    cmd_name: string # command name to search for
    --db: directory = $nix_db # directory of the database to use
]: nothing -> list<string> {
    cmd locate nix $cmd_name --db $db
}

# Create an index of pacman packages
#
# Saves pacman packages to an sqlite database for easy, fast queries. Squashes
# it a little bit by grouping things by repo/package/version. Only stores the
# binary paths, using this both core and extra it's only about 0.75mb.
@example "Create the initial index" {pacman create-index}
@example "Create the initial index at a specific location" {pacman create-index /tmp/db}
export def "pacman create-index" [
    db: path = $pacman_db # file to use as the pacman database
]: nothing -> nothing {
    log info "Updating the pacman file data..."
    let backup_db = $"($db).(date now | format date '%J%Q')"
    if ($db | path exists) {
        log info $"Backing up current db to ($backup_db)"
        mv $db $backup_db
    }
    mkdir ($db | path dirname)
    try {
        let tmpfiles = mktemp -t -d
        log info "^pamcan --files --refresh"
        ^pamcan --files --refresh --dbpath $tmpfiles --logfile /dev/null --root $tmpfiles
        log info "Getting all files in common executable file locations"
        ^pacman -Fx '^(|usr)/s?bin/.+' --machinereadable
        | lines
        | split column (char nul) repo package version file
        | into sqlite $db -t pacman
        log info $"Saved to sqlite database ($db)"

        log debug "Optimizing table."
        open $db
        | query db "CREATE INDEX idx_pacman
            ON pacman(files);"
    } catch {|e|
        if ($backup_db | path exists) {
            log error $"Restoring database..."
            mv $backup_db $db
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
@example "find a package" {pacman locate ls} --result [ coreutils ]
export def "pacman locate" [
    cmd_name: string # command name to search for
    --db: path = $pacman_db # location of the database
]: nothing -> list<string> {
    cmd locate pacman $cmd_name --db $db
}

# Find command in package managers that are installed on the system
@example "find a package" {provided-by ls} --result [
    "nix profile add nixpkgs#_9base",
    "pacman -S coreutils"
    ...
]
export def provided-by [
    cmd_name: string # command to search for
]: nothing -> list<string> {
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

export def "main" [
    cmd_name: string
    --span (-s): record<start: int, end: int>
]: nothing -> error {
    let span = $span | default (metadata $cmd_name | get span)
    if ($cmd_name | str contains '/') {
        error make {
            code: "nu::shell::cmd_file"
            msg: (
                if ($cmd_name | path exists) {"Path is not runnable."
                } else {"File doesn't exist."}
            )
            labels: [
                {text: "" span: $span}
            ]
        }
    }
    error make {
        code: "nu::shell::cmd_not_found"
        msg: $"Command `($cmd_name)` not found"
        labels: [
            {text: "" span: $span}
        ]
        help: (
            match (provided-by $cmd_name) {
                [] => null
                $pkgs => {
                    let has_extras = if ($pkgs | length) > ($env.cnf.maxpkgs) { ["  ..."] }
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
            }
        )
    }
}

export-env {
    $env.cnf.maxpkgs = $env.cnf?.maxpkgs? | default 3
    $env.cnf.auto = false
    $env.cnf.registry = $env.cnf?.registry? | default "nixpkgs"
    $env.config.hooks.command_not_found = {|cmd_name|
        let span: record = metadata $cmd_name | get span
        main $cmd_name --span $span
    }
}


