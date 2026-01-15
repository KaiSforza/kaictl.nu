# Not replacements, but improvements for some coreutils functions
#
# Includes better output for `ls`, `w`, `df` and more! I know most of these
# aren't actually part of `coreutils`, but they are core utilities that could
# use better output.

# Order `ls` output more like what the normal `ls` output is.
#
# Re-orders the output to normally be `mode user group size mod name (target)`
export def l [
    --all (-a) # Show hidden files
    --long (-l) # Get all available columns
    --short-names (-s) # Only print the file names, not the path
    --full-paths (-f) # display paths as absolute paths
    --du (-d) # Display apparent directory sizes
    --directory (-D) # List the specified directory itself instead of the contents
    --mime-type (-m) # Show mime-types based on filenames
    --threads (-t) # Use multiple threads
    ...pattern: oneof<glob, string> # The glob pattern to use
] {
    let r: oneof<glob, string> = if ($pattern | is-empty) {
        [.]
    } else {
        $pattern
    }
    (ls
        -l
        --all=$all
        --short-names=$short_names
        --full-paths=$full_paths
        --du=$du
        --directory=$directory
        --mime-type=$mime_type
        --threads=$threads
        ...$r
    )
    | if $long {
        do {||}
    } else {
        do {||
            select --optional ...(
                [
                    mode user group size modified name
                    ...(if ($in | is-not-empty target) {[target]})
                ]
            )
        }
    }
}

# Ordered `ls` output
export alias ll = l

# A `^watch` alternative.
export def retry [
    --interval (-n): duration = 2sec, # time between retries
    --precise (-p) # Be precise with the sleep
    command: closure, # command to run
] {
    let host = (sys host).hostname? | default ""
    let cmdstr = $"Every ($interval): (view source $command | lines | first)"
    let cmdstr_len = $cmdstr | str length
    #let times: list<datetime> = generate {|i|
    #  {out: $i, next: ($i + $dur)}
    #} (date now)
    loop {
        let till = (date now) + $interval
        let out = do $command
        let right = $"(date now)"
        clear
        print $"($cmdstr)($right | fill --alignment r --character ' ' --width ((term size).columns - $cmdstr_len))(char newline)"
        $out | do $env.config.hooks.display_output
        sleep (if $precise {
            $till - (date now)
        } else {
            $interval
        })
    }
}

def nu_complete_mounts [] {
    sys df | get mount
}

# View important information about the system disks that matter.
#
# Fixes the names to be shorter `/dev/sd*` or `/dev/nv*`, adds percent free,
# filters out overlays and useless disks.
@example "View disks" {sys df}
export def "sys df" [
    --precision (-p): int = 2 # Default precision to use for the filesizes
    ...path: string@nu_complete_mounts #Show a specific mount only
]: nothing -> table {
    let pathfilter = if ($path | is-not-empty) {
        {|p| $p.mount in $path}
    } else {
        {|p| true}
    }
    sys disks
    | where {|s| (
        (do $pathfilter $s) and (
            $s.device != 'overlay' and (
                ($s.device =~ '^/.*') or ($s.type == "apfs")
            ) and (
                not ($s.mount =~ '.*/kubelet/.*')
            )
        )
    )}
    | insert used {|s| $s.total - $s.free}
    | insert pUse {|s| (try {$s.used / $s.total} catch {0.0})}
    | upsert device {|s|
        if ($s.device | path split | length) >= 4 and $s.device =~ '^/.*' {
            if ($s.device | str contains "/by-label/") {
                $"label:($s.device | parse "{_}/by-label/{label}" | first | get label)"
            } else {
                let actualdev = $s.device
                let loc = ls -l $actualdev | first
                let target = $loc.target
                ($loc.name | path dirname | path join $target) | path expand
            }
        } else {
            $s.device
        }
    }
    | move --after total used free pUse mount
    | match $in {
        [$x] => $x
        $x => $x
    }
}

# sys net but sorted
export def "sys n" [
    iface: string@nu_complete_ifaces = '' # Get a specific interface only
]: nothing -> table {
    let sn = sys net
    | sort-by name
    | upsert ip {|i|
        $i.ip
        | sort-by --natural address
    }

    if $iface != '' {
        $sn | where name == $iface | first
    } else {
        $sn
    }
}

def nu_complete_ifaces [] {
    sys net | get name
}

# Create a tree-like ps output in a nushell table
def pstree [
    procs: table # ps -l output here
    newprocs # new output here for recursion?
] {
    if ($newprocs | describe -n) !~ '^table' {
        $newprocs
    } else {
        let with_childs = $newprocs
        | upsert children {|proc|
            let children = $procs | where ppid == $proc.pid
            pstree $procs $children
        }
        $with_childs
        # | where ppid not-in $with_childs.pid
    }
}

def "from fk_tab" [name: string = "default"]: string -> table {
    # from ssv --minimum-spaces 1 --noheaders
    lines
    | split column ' '
    | flatten
    | rename key value
    | par-each {|kv|
        match $kv {
            {key: $x value: $y} => $kv
            {key: $x} => {key: $name value: $x}
            $x => $x
        }
    }
    # parse "{key} {value}"
    # | rename key value
}

# from a flat keyed file to a nushell record
def "from fk" [name: string = "default"]: string -> record {
    from fk_tab $name
    | transpose -rd
}

# Get the group of the process or list of processes
#
# The only possible format for these in v2 is `0::/foo/bar`, which makes this a
# bit simpler. Defaults to the `/sys/fs/cgroup` path as the root.
#
# These can be passed into `cgroup parse` directly.
export def "proc cgroup" [
    cgroupfs: path = "/sys/fs/cgroup"
    --session (-s) # Use a session instead of a PID
]: [
    oneof<int, string> -> record<id: int, ss: list, cg: path>
    list<oneof<int, string>> -> table<id: int, ss: list, cg: path>
] {
    let pids = $in
    let pcg = {|pid|
        [/proc $"($pid)" cgroup] | path join
            | open
            | parse '{id}:{ss}:{cg}'
            | first
            | into int id
            | upsert ss {|p| $p.ss | split row ',' | compact -e}
            | upsert cg {|p|
                [$cgroupfs] ++ ($p.cg | split row (char psep)) | path join
            }
    }
    match ($pids | describe) {
        list<int> | list<string> => ($pids | par-each --keep-order $pcg)
        _ => (do $pcg $pids)
    }
}

# Parse the cgroup info for `$subsys`
export def "cgroup parse" [subsys: string]: oneof<string, record> -> table {
    match $in {
        {cg: $x} => $x
        $x => $x
    } | path join $subsys
        | open
        | from fk_tab
}

# Get info about the CPU usage
export def "cgroup cpu" []: oneof<string, record> -> record {
    cgroup parse cpu.stat
    | par-each --keep-order {|r|
        {
            key: $r.key
            val: (
                if $r.key =~ '_usec' {
                    $r.value | into duration --unit us
                } else {
                    $r.value | detect type
                }
            )
        }
    }
    | transpose -rd
}

# Get memory usage info (all values in filesize)
export def "cgroup mem" []: oneof<string, record> -> record {
    let sr = $in
    $sr
    | cgroup parse memory.stat
    | into filesize value
    | transpose -rd
    | merge {
        current: (try {
            ($sr | cgroup parse memory.current | into filesize value).0.value
        } catch {0})
    }
}

# Parse stats for each disk
export def "cgroup io" []: oneof<string, record> -> table {
    cgroup parse io.stat
    | par-each {|disk|
        {disk: $disk.key}
        | merge (
            $disk.value
            | split row ' '
            | parse '{key}={val}'
            | transpose -rd
            | into filesize rbytes wbytes dbytes
        )
    }
}

# Parses the /proc/*/stat files
def "proc stat" [
    ticksize: int = 100 # CPU Tick Size (usually 100, but could be different)
]: oneof<int, string> -> record {
    let stat = open $"/proc/($in)/stat" | str trim
    let comm = $stat | parse '{_} ({comm}) {_}' | get 0.comm
    # Taken from `man 5 proc_pid_stat`
    let columns = [
        pid comm state ppid pgrp # 5
        session tty_nr tpgid flags minflt # 10
        cminflt majflt cmajflt utime stime # 15
        cutime cstime priority nice num_threads # 20
        itrealvalue starttime vsize rss rsslim # 25
        startcode encode startstack kstkesp kstkeip # 30
        signal blocked sigignore sigcatch wchan # 35
        nswap cnswap exit_signal processor rt_priority # 40
        policy delayacct_blkio_ticks guest_time cguest_time start_data # 45
        end_data start_brk arg_start arg_end env_start # 50
        env_end exit_code
    ]
    $stat
    | str replace --regex '\(.+\)' 'PROC'
    | split column ' '
    | rename ...$columns
    | first
    | merge {comm: $comm}
    | upsert starttime {|p|
        | into int
        | $in / $ticksize
        | into duration --unit sec
        | $in + (sys host).boot_time
    }
}

# Session info 
export def session_info [
    session
]: nothing -> record {
    # Get cgroup directory
    let cgroup = glob -SF $"/sys/fs/cgroup/**/session-($session.session).scope"
    | default -e [
        ($session.leader | proc cgroup).cg
    ]
    let total_cpu = "/sys/fs/cgroup" | cgroup cpu
    {
        user: $session.user
        uid: $session.uid
        # tty: $session.tty?
        # leader: $session.leader
        session: $session.session
        login: (0 | into datetime)
    }
    | merge (
            if $session.idle {
                {idle: ((sys host).boot_time + ($session.since | into duration --unit us))}
            } else { { } }
        )
    | merge (
        match $cgroup {
            [$x] => {
                # Get most recently added PID
                let pids = (open ($x | path join "cgroup.procs") | lines)
                let cpu = ($x | cgroup cpu | get usage_usec)
                {
                    login: (
                        (open ($cgroup | path join "cgroup.procs")
                            | lines
                            | first
                            | into int
                        ) | default 1
                        | proc stat
                    ).starttime
                    cpu: (($x | cgroup cpu | get usage_usec) / $total_cpu.usage_usec)
                    mem: ($x | cgroup mem | get current)
                    what: (
                        $pids
                        | par-each {|pid|
                            {
                                pid: $pid
                                cmdline: (
                                    open $"/proc/($pid)/cmdline"
                                    | str trim
                                    | str replace --all (char nul) ' '
                                )
                            }
                        }
                    )
                    # what: $what.command?
                }
            }
            _ => { { } }
        }
    )
}

# A better output for `w`
@example "Get load average and other info" {ww}
@example "Get uptime" {ww | get uptime} --result 29sec
export def ww [
    --long (-l) # long version
]: nothing -> record<boot: string, uptime: duration, load: table, sessions: table> {
    let cpus = sys cpu | get load_average | uniq
    let tfs: record = sys host
    # Need to do this because nu has no native session info support
    let session_l: list = if (which loginctl | is-not-empty) {
        if $long {
            let ticksize: int = getconf CLK_TCK | default -e 100 | into int
            let now = (date now)
            loginctl list-sessions --json=short | from json
            | par-each {|session|
                session_info $session
            }
            | sort-by login
        } else {
            loginctl list-sessions --json=short | from json
        }

    } else {
        w | detect columns --skip 1
    }

    {
        boot: $tfs.boot_time
        uptime: $tfs.uptime
        load: ($cpus | parse "{1m}, {5m}, {15m}" | update cells {detect type})
        sessions: $session_l
    }
}

# Get just the path to the which file
#
# Works similar to the normal bash/zsh `type`. Only outputs applications, so
# this will always be a list of paths. Aliases, builtins and custom commands
# will need to use `which`.
#
# Will return a single path if you only give it a single application and do not
# use `-a`, so it can be used as an argument to external commands. With `-a` or
# multiple arguments a list will be returned. This list can be expanded with
# `...(witch -a nu)`. The arguments determine the output type.
@example "Which nu" {witch nu} --result "/path/to/nu"
@example "Which which" {witch -a which} --result ["which" "/path/to/which"]
@example "Get info on a file" {ls (witch nu) | first} --result {
    name: "/path/to/nu",
    type: symlink,
    size: 68b,
    modified: 1970-01-01T00:00:01-00:00
}
export def witch [
    --all (-a)
    ...apps
]: [
    nothing -> list<path>
    nothing -> path
] {
    match (
        which --all=$all ...$apps
        | each {|w| match $w.type {
            external => $w.path
            _ => null
        }}
        | compact --empty
    ) {
        [$x] => $x
        $x => $x
    }
}

# Find the first path matching $in/$p, or an empty list if it doesn't exist.
#
# Useful instead of using `jj root` or `git rev-parse --show-toplevel`
# 
# Returns either an empty list if not found, or a singleton list with the path
# of the directory being searched for
@example "Find a git path" {"/foo/bar/repo/subdir/subdir2" | path in-parent ".git"} --result ["/foo/bar/repo/.git"]
@example "Not finding a path" {"/foo/bar/repo/subdir/subdir2" | path in-parent "thisdoesntexist"} --result []
export def "path in-parent" [
    p: string # Path to find in the parent directories
]: path -> list<path> {
    let inpath = $in
    let pathlen = $inpath | path split | length
    for ep in 0..$pathlen {
        let check_path: path = ($inpath | path dirname -n $ep | path join $p)
        if ($check_path | path exists -n) {
            return [$check_path]
        }
    }
    return []
}
