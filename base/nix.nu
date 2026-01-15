# Nix command helpers
#
# Adds a few commands to `nix` so it can be used with some nushell types and
# outputs.

use ../lib *

# Regenerate the search db
export def 'nix s regen' [
    --all # Regenerate all flakes in `nix registry list`
    --flakes (-f): list<string> = ["nixpkgs"] # Regenerate just this flake
] {
    let flake_list: list<string> = if $all {
        nix registry list
        | from ssv --minimum-spaces 1 --noheaders
        | get column1
        | parse "{_}:{fname}"
        | get fname
    } else {
        $flakes
    }
    let get_data = {|flake|
        let flake_meta = nix flake metadata --json $flake
        | from json
        let flake_show = nix --option allow-import-from-derivation true flake show --json --legacy $flake
        | from json
        let update_time = $flake_meta.lastModified
        | into datetime --format "%s"

        if ($flake_show.packages? | is-not-empty) or ($flake_show.legacyPackages? | is-not-empty) {
            nix --option allow-import-from-derivation true search $flake '.*' --json --no-pretty
            | from json
            | items {|p, v|
                let extra_info = $p | split row '.'
                {
                    path: $p,
                    shortName: ($extra_info | skip 2 | str join '.')
                    arch: $extra_info.1
                    outLoc: $extra_info.0
                    flake: $flake
                    updated: $update_time
                } | merge $v
            }
        } else {
            null
        }
    }
    $flake_list | each --flatten {|f|
        print -e $"==> Getting data from ($f)..."
        do $get_data $f
    }
}

# Search in known nix flakes
export def "nix s" [
    --path (-p): path = $DB_NIX_S
    --exact (-e) # use exact search
    --flake: string = "n" # Which flake to search against
    --all-flakes (-a) # Search in all flakes
    --regen # Regenerate the DB
    query: string # Query
] {
    let db_path = $path | path expand
    let update_time = date now
    if $regen {
        # Check if we already have some data
        if ($db_path | path exists) {
            let old_data = open $db_path | get main
            mv $db_path ($db_path + "-old")
            $old_data
            | append (nix s regen --flakes [$flake])
            | uniq-by path flake version
        } else {
            nix s regen --flakes [$flake]
        }
        | into sqlite $db_path
    }
    let flake_filter = {||
        if $all_flakes { {||} } else { {|| $in.flake == $flake } }
    }

    open $db_path
    | if ($exact) {
        query db -p {query: $query} $"select * from main where shortName == :query"
    } else {
        query db -p {query: $"%($query)%"} $"select * from main where shortName like :query"
    }
    | select shortName version flake description
    | upsert install {|s| $"($s.flake)#($s.shortName)"}
    | where flake == $flake or $all_flakes
}

# Wipes all nix history in system and current user profile
#
# Defaults to saving only 1 day of history, but this can be changed. Does not
# allow negative durations. Setting `0day` is the same as deleting all history.
# Dates are granular to the day and are rounded up, so `-o 12hr` is the same as
# `-o 1day`.
#
# Normall this will only do a dry run, printing out the generations that will be
# removed, nothing will be deleted unless `--run` is passed.
@example "Show all history that would be wiped" {nix profile wipe-all-history}
@example "Delete all history older than 1 day" {nix profile wipe-all-history --run}
@example "Dry-run deleting all history" {nix profile wipe-all-history -o 0day}
def "nix profile wipe-all-history" [
    --older-than (-o): duration = 1day # How many days of history to keep
    --run # Don't do a dry-run
]: nothing -> any {
    if $older_than < 0day {
        error make {msg: "Can't have a negative duration"}
    }
    let days: int = $older_than
    | into int
    | $in / (1day | into int)
    | math ceil
    let paths: list<glob> = [
        /nix/var/nix/profiles/**/profile
        /nix/var/nix/profiles/**/system
        ~/.local/state/nix/profiles/**/profile
        ~/.local/state/nix/profiles/**/system
    ]
    | each {|g| glob -DF $g}
    | flatten

    $paths | each {|p|
        let no_sudo: bool = try {
            $p | path relative-to $env.home
            true
        } catch {
            false
        }
        let args = [
            profile
            wipe-history
            --offline
            --log-format internal-json
            --profile $p
            ...(if $run {[]} else {[--dry-run]})
            ...(if $days > 0 {[--older-than $"($days)d"]} else {[]})
        ]
        if $no_sudo {
            ^nix ...$args | complete | get stderr
        } else {
            sudo nix ...$args | complete | get stderr
        }
        |
        str replace -amr "^@nix " ""
        | from json -o
        | each {|l|
            $l | merge {profile: $p}
        }
    }
    | flatten
}

# Recursively list configured builders
def "nix builders" [
    --at-file: string # Show builders at this location
    --nushell (-n) # Nushell output
]: [
    nothing -> list<string>
    nothing -> table
] {
    let nixConfig = if ($at_file | is-empty) {
        nix config show --json
        | from json
        | get builders
    } else { {
        value: (open ($at_file | str substring 1..))
    } }

    let builders = $nixConfig.value?
    | default $nixConfig.defaultValue?
    | default ""
    | split row -r '\s*(;|\n)\s*'

    $builders
    | each --flatten {|builder|
        if $builder =~ '^@' {
            nix builders --at-file $builder
        } else {
            $builder
        }
    }
    | if $nushell {
        each {from nixbuilder}
    } else {do {||}}
}

# Convert from a builder string to a nushell record
def "from nixbuilder" []: string -> record {
    let builder = $in | split row --regex ' +'
    {
        uri: $builder.0
        systems: ($builder.1? | default "-" | split row ',' | compact -e)
        sshkey: ($builder.2?)
        maxbuilds: ($builder.3? | default "1" | into int)
        speed: ($builder.4? | default "0" | into int)
        features: ($builder.5? | default "-" | split row ',' | compact -e)
        required: ($builder.6? | default "-" | split row ',' | compact -e)
        pubkey: ($builder.7?)
    }
}

# TODO: Fix this to actually work lol
def "to nixbuilder" []: record -> string {
    $in.values
    | each {default '-'}
    | str join ' '
}

def "nu-complete nodes" []: any -> list<string> {
    nix flake show /etc/nixos --json
    | complete
    | get stdout
    | from json
    | get --optional nixosConfigurations
    | default {}
    | columns
}

# Updates multiple nix nodes
@example "Update two nodes" {nix rebuild nodes foo bar}
@example "Update one node and switch" {nix rebuild nodes -a switch foo}
def "nix rebuild nodes" [
    --builders: list<string>@"nix builders" = [] # Which builder to use
    --action (-a): string@[ "switch" "boot" "test" "build" ] = "test" # What `nixos-rebuild` action to run
    --verbose (-v) # Be verbose
    ...nodes: string@"nu-complete nodes"
]: nothing -> table {
    $env.NU_LOG_LEVEL = if $verbose { "debug" } else { null }
    log debug $"nixos-rebuild nodes|running `nixos-rebuild ($action)` on ($nodes | str join ' ')"
    $nodes
    | each {|node|
        log debug $"Running on ($node)..."
        let progfile = mktemp --tmpdir --suffix ".log"
        (
            ^nixos-rebuild
                $action
                --flake $"/etc/nixos#($node | split row '.' | first)"
                --target-host $"($env.user)@($node)"
                --sudo
                ...(optionals $builders [--builders ($builders | str join ',')])
                ...(optionals $verbose [--verbose])
        ) o+e>| save --progress --append $progfile
        let out = open --raw $progfile | lines
        rm $progfile
        let done =  ($out | last 10 | where $it =~ '^Done[.] ')
        {
            node: $node
            out: (if ($done | is-not-empty) {
                $done
            } else {
                $out
            })
        }
    }
}

# Copy by nix drv path
@example "Copy from a derivation" {
    nix copy drv --from ssh://foo /nix/store/somehash-name.drv
} --result "/nix/store/someotherhash-name"
def "nix copy drv" [
    --from: string # Where to copy from
    --to: string # Where to send the files
    drv: path # Path to the remote nix derivation (ending in `.drv`)
] {
    match [$from $to] {
        [null, null] => (error make {msg: "Must set a `--from` or `--to` location."})
        [null, $x] | [$x null] => {
            let p = nix derivation show $drv
            | from json
            | get ($drv | path basename)
            | get outputs.out.path
            | ["/nix" "store" $in]
            | path join

            nix copy -v --from $from $p
            $p
        }
        _ => (error make {msg: "Must set only one of `--from` or `--to`."})
    }
}

# Creates the nix index for _much_ faster command lookups by command_not_found.
#
# If a cache paths.cache file is available, it can be placed into the db
# directory (`~/.cache/nix-index-not-found/paths.cache`) to significantly speed
# up the generation process.
#
# The compression level doesn't really matter and the size benefits are minimal
# but 3 is a 'normal' compression, not 22. The main part is the `--filter-prefix`
# to get rid of the non '/bin/' paths.
# def "nix create-index" [
#     --flake (-f): string = "flake:nixpkgs" # Flake to use
#     --system (-s): string # Choose a specific system
#     --compression (-c): int = 3 # Compression level for zstd
#     --path-cache (-p) # Use the path cache at `~/.cache/nix-index-not-found`
# ] {
#     let db_loc = $env.HOME | path join ".cache" "nix-index-not-found"
#     let real_system = if ($system | is-not-empty) {
#         $system
#     } else {
#         nix config show --json
#         | from json
#         | get system.value
#     }
#     # Annoyingly the `--path-cache` doesn't have a location...just in the local
#     # directory.
#     mkdir $db_loc
#     cd $db_loc
#     (
#         nix-index
#         --db $db_loc
#         -f $flake
#         -s $real_system
#         -c $compression
#         --filter-prefix '/bin/'
#     )
# }

# Restart the nix-daemon
#
# This seems to get stuck sometimes with the current version, just adding this
# to help get things running again.
export def "nix daemon restart" [
    --dry-run (-n) # Don't actually restart, just check what's running
] {
    let nix_daemons = ps | where name =~ nix-daemon
    if $dry_run {
        return $nix_daemons
    }
    (
        sudo systemctl stop
        nix-daemon.socket
        determinate-nixd.socket
    )
    sudo systemctl stop nix-daemon.service
    ps | where name =~ nix-daemon
    | match $in {
        [] => ()
        $p => (sudo kill --signal 9 ...($p.pid))
    }
    sudo systemctl start nix-daemon.socket determinate-nixd.socket
    return {
        before: $nix_daemons
        after: (ps | where name =~ nix-daemon)
    }
}

def nu_complete_nhcommands [] {
    [build boot test switch]
}

export def "nix nh" [
    command: string@nu_complete_nhcommands # What to do in `nh`
    ...nodes: string
] {
    log info "Building and sending derivations"
    let flake: string = $env.NH_OS_FLAKE?
    | default $env.NH_FLAKE?
    | default "/etc/nixos"
    let nh = nix build --no-link --print-out-paths $"($flake)#nh"
    | path join bin nh
    let nom = nix build --no-link --print-out-paths $"($flake)#nix-output-monitor"
    | path join bin nom
    let version = run-external $nh ...[--version]
    | parse "nh {major}.{minor}.{micro}"
    | update cells {detect type}
    | first

    # pre-build everything together
    let output =  (
        run-external $nom ...[
            build
            --print-out-paths
            --no-link
            # --builders 'ssh-ng://kaictl@nixps x86_64-linux - 16 100 kvm,nixos-test,big-parallel,benchmark - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUVPYWc3VjNtVmhDaWVrMEFNaTYyUFZQbnM2TTl0VDNxUkhVTjJmeEJhMHU='
            ...(
                $nodes
                | each {|node|
                    $"($flake)#nixosConfigurations.($node).config.system.build.toplevel"
                }
            )
        ]
    )
    | lines
    | wrap output

    let table = $nodes | wrap node
    | merge $output

    log info $"Finished building."
    log info $"list time: (char newline)($table | table -e)"

    $table
    | par-each {|d|
        if $d.node != (sys host).hostname {
            log info $"Sending built derivation to '($d.node)'..."
            (
                nix copy
                --to $"ssh://($d.node)"
                $d.output
            )
        } else {
            log info $"Just built derivation on ($d.node). Continuing."
        }
        if $command != build {
            log info $"Running `nh os ($command)` for host '($d.node)'..."
            run-external $nh ...[
                os $command
                $"($d.output)"
                ...(if $d.node != (sys host).hostname {
                    [--target-host $d.node]
                })
                ...(if $version.major >= 4 and $version.minor >= 3 {
                    [--elevation-strategy passwordless]
                })
            ]
        }
    }

    # if $command != build {
    #     $table
    #     | each {|d|
    #         (
    #             nix run $"($flake)#nh" --
    #                 os $command
    #                 $"($d.output)"
    #                 ...(if $d.node != (sys host).hostname {
    #                     # Remote
    #                     [--target-host $d.host]
    #                 })
    #                 ...(if $version.major >= 4 and $version.minor >= 3 {
    #                     # passwordless sudo
    #                     [--elevation-strategy passwordless]
    #                 })
    #         )
    #     }
    # }
}
