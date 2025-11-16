use ../lib *
use ../env *

# Run docker/podman wrapped, or directly via the API if implemented below
export def --wrapped main [
    --url: string
    ...r
] {
    let url = if ($url | is-not-empty) {
        {}
    } else if ($env.CONTAINER_HOST? | is-not-empty) {
        {}
    } else {
        let clientver = ^docker --version
        | parse "{_name} version {maj}.{min}.{_}"
        | get maj.0
        | into int
        if ($clientver > 20) {
            {CONTAINER_HOST: "unix:///run/docker.sock"}
        } else {
            # For non-linux stuff
            {CONTAINER_HOST: $"unix://($env.XDG_RUNTIME_DIR? | default "/run")/podman/podman.sock"}
        }
    }
    with-env $url {
        log info "Falling back to podman since there is no custom command written (yet)."
        ^podman ...$r
    }
}

# Update cells recursively
def update_cells_deep [
    # closure: closure
]: [
    table -> table
    record -> record
] {
    let d = $in
    let recurs = {||
        items {|k, v|
            let t = $v | describe
            {
                $k: (if $t =~ "^(table|record)" {
                    $v | update_cells_deep
                } else {
                    $v | detect type
                })
            }
        }
    }
    if ($d | describe) =~ "^(list|table)" {
        $d | each {do $recurs | into record}
    } else {
        $d | do $recurs | into record
    }
}

def "pu info" [
    --force (-f)
]: nothing -> record {
    let path = $env.XDG_RUNTIME_DIR? | default $D_CACHE | path join "podmaninfo.db"
    let host = ($path | path dirname) | path join podman podman.sock
    let hash = random uuid -v 5 -n url -s $host
    if (not $force) and ($path | path exists) and ($hash in (open $path | columns)) {
        open $path
        | get $hash
        | sort-by SystemTime
        | last
    } else {
        let pudata = http get --unix-socket $host http://localhost/info
        $pudata
        | reject ID
        | into datetime SystemTime
        | tee {into sqlite --table-name $hash $path}
    }
}

def pu_version [] {
    pu info | get ServerVersion
}

def "pu get" [
    path: string
    params: record = {}
] {
    let url = {
        scheme: http
        host: localhost
        path: /v(pu_version)/libpod/($path)
        params: $params
    } | url join
    http get --unix-socket $env.CONTAINER_HOST $url
}

def "pu post" [
    path: string
    params: record = {}
    data: any = null
] {
    let url = {
        scheme: http
        host: localhost
        path: /v(pu_version)/libpod/($path)
        params: $params
    } | url join
    http post --unix-socket $env.CONTAINER_HOST $url
}

# Get a list of podman/docker containers
#
# Similar to docker ps
export def "pd ps" [
    --full (-f) # Show the full table
    --url: oneof<string, path> # Override the `podman`/`docker` url
    --all (-a) # Display all containers
    --external (-e) # Return containers in storage not controlled by podman
    --limit: int # Return this number of containers by creation date
    --size # Return size of containers as `SizeRw` and `SizeRootFs`
]: nothing -> table {
    let params = {
        all: $all
        external: $external
        limit: $limit
        size: $size
    } | compact
    $env.CONTAINER_HOST = $url | default "/run/docker.sock"
    let now = date now
    let dout = pu get containers/json $params

    let insp = $dout
    | get id!
    | par-each --keep-order {|cid|
        pu get $"containers/($cid)/json"
    }

    let inspect = $insp
    | update_cells_deep

    $inspect
    | par-each --keep-order {|container|
        $container
        | upsert Id {|s|
            if not $full {
                $s.Id! | str substring 0..11
            } else {
                $s.Id!
            }
        }
        | upsert Image {|s|
            let iname: string = $s.Config.Image
            let iid: string = $s.Image

            if ((not $full) and (($iname | str length) > 48)) {
                $"digest:($iid | str replace --regex '^sha256:' '' | str substring 0..12)"
            } else {
                $iname
            }
        }
        | upsert Command {|s|
            let cmd = $s.Config.Cmd? | default -e []
            let ep = $s.Config.Entrypoint? | default -e []

            let fullcmd = $ep ++ $cmd
             if ($ep | length) == 1 {
                $ep | first
            } else {
                $ep
            }
        }
        | upsert Ports {|s|
            if ($s.NetworkSettings.Ports? | is-not-empty) {
                $s.NetworkSettings.Ports
                | items {|k, _v|
                    let v = $_v.0? | default {}
                    let p = $k | parse "{ContainerPort}/{Protocol}" | first
                    {
                        HostIp: (if not ($v.HostIp? in ["0.0.0.0" "::"]) {$v.HostIp?})
                        HostPort: (if $v.HostPort? != $p.ContainerPort {$v.HostPort?})
                        ContainerPort: ($p.ContainerPort? | default 0 | into int)
                        Protocol: (if $p.Protocol? != "tcp" {$v.Protocol?})
                    }
                    | compact -e
                }
            }
        }
        | upsert Status {|s|
            #  "created" "running" "paused" "restarting" "removing" "exited" "dead" 
            [
                (match $s.State.Status {
                    running => "Up"
                    _ => {$"($s.State.Status | str capitalize) \(($s.State.ExitCode)\)"}
                })
                ((
                    [
                        $s.State.StartedAt?
                        $s.State.FinishedAt?
                        $s.State.CheckpointedAt?
                        $s.State.RestoredAt?
                    ]
                    | compact -e
                    | math max
                    | date humanize
                    | do (if $s.State.Running {{|| str replace ' ago' ''}} else {{||}})))
            ] ++ [(if ($s.State.Running) and ($s.State.Health? | is-not-empty) {
                    (
                        $s.State.Health? | default {}
                        | $in.Status? | default "ok"
                        | $"\(($in)\)"
                    )
                }
            )]
            | compact -e
            | str join ' '
        }
    }
    | if $full {
        $in
    } else {
        $in
        | select -o Name Image Command Id Created Status Ports
    }
    | each {compact --empty}
}

export def "pd image ls" [
    --url: oneof<string, path> # Override the `podman`/`docker` url
    --all (-a)
    --full (-f)
] {
    $env.CONTAINER_HOST = $url | default "/run/docker.sock"
    let all_images = pu get images/json

    $all_images
    | upsert Id {|s|
        $s.id! | if $full {do {||}} else {str substring  0..12}
    }
    | select History Id Created VirtualSize
}
