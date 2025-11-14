# Load environment from `./.envrc.nu` file
#
# `./.envrc.nu` will be loaded automatically if these files are found. If the
# `$env.envrc_config.legacy_envrc` is `true`, then the `.envrc` file will be
# attempted as well.
#
# The `./.envrc.nu` file should output a nuon string that can be loaded as the
# new environment.

use ./lib.nu *
use ./coreutils.nu *

export-env {
  let envrc_config = {
    # Load old .envrc file
    legacy_envrc: false
  }
  $env.envrc = $envrc_config | merge deep ($env.envrc? | default {})
  let envrc_loaded: path = $env.envrc_loaded? | default ''
  $env.envrc.loaded = $envrc_loaded
  let checkfile = {|p|
    let pl = $p
    | path in-parent ".envrc.nu"
    match $pl {
      [$x] => {
        name: $x
        csum: (open --raw $x | hash sha256)
      }
      [] => {{}}
    }
  }

  let check_allowed = {|p: record|
    $env.envrc.allowed?
    | default []
    | where {|i| $i == $p}
    | match $in {
      [] => false
      _ => true
    }
  }

  let unload = {|delta, loaded|
    log debug $"Unloading env from ($loaded)"
    $env.envrc.loaded = ""
    let envrc_delta: table<name: string b: any a: any> = $delta | default []
    $envrc_delta | each {|d| log debug $"($d)"}
    let b = $envrc_delta | reject a
    let old_env: record = $b | where {|x| $x.b | is-not-empty} | transpose -rd | default -e {}
    log debug $"setting env back to: ($old_env)"
    let unsets: record = $b | where {|x| $x.b | is-empty} | transpose -rd | default -e {}
    log debug $"Unsetting the following: ($unsets | columns)"
    hide-env ...($unsets | columns)
    load-env $old_env
  }

  let load = {|path|
    log debug $"Loading env from ($path)"
    $env.envrc.loaded = $path
    let original_env = $env
    let changes = nu -n $path
    | from nuon
    let delta = [
      $original_env
      (
        $original_env
        | merge deep $changes
      )
    ]
    | transpose name b a
    | where {|e| $e.b != $e.a}
    let orig_delta = $delta
    | transpose -rd
    $delta | each {|d| log debug $"($d)"}
    $env.envrc.delta = $delta
    let a = $env.envrc.delta | reject b
    let new_env = $a
    | where {|x| $x.a | is-not-empty}
    | transpose -ard
    | upsert PATH {|x| $x.path? | default [] | flatten}
    | default -e {}
    let unsets = $a
    | where {|x| $x.a | is-empty}
    | transpose -ard
    | default -e {}
    hide-env ...($unsets | columns)
    load-env $new_env
  }

  let check_envs: closure = {|before, after|
    # Check whether the path even exists and whether it's allowed
    let loadpath: record = if ($after != null) {do $checkfile $after} else {{}}
    let prevpath: record = if ($before != null) {do $checkfile $before} else {{}}
    let allowed: bool = do $check_allowed $loadpath
    let prev_allowed: bool = do $check_allowed $prevpath


    if $allowed or ($prevpath | is-not-empty) {
      log debug $"Checking the loadpath: ($loadpath)"
      match $loadpath {
        {name: $x} => {
          log debug $"Loading from ($x) ..."
          if $x != $env.envrc.loaded? {
            if not $allowed {
              log info $"The `.envrc.nu` file is not allowed! use `envrc allow` to enable it."
              return null
            }
            if ($env.envrc.delta? | is-not-empty) {
              do --env $unload $env.envrc.delta ($env.envrc.loaded | default {})
            }
            do --env $load $x
          }
        }
        _ => {
          log debug $"Nothing loaded, no loadpath set"
          # No envrc loaded here
          if $prev_allowed {
            do --env $unload $env.envrc.delta? $env.envrc.loaded
          }
        }
      }
    }
  }
  $env.config.hooks.env_change.PWD = [$check_envs]
}

export def --env "envrc allow" [
  path: path = './.envrc.nu'
] {
  if ($path | path exists) {
    log info $"Allowing the path ($path | path expand)"
    $env.envrc.allowed = $env.envrc.allowed?
    | default []
    | append [
      {
        name: ($path | path expand)
        csum: ($path | path expand | open | hash sha256)
      }
    ]
    | uniq
  } else {
    log info $"No file we can use at ($path | path expand)"
  }
}

export def --env "envrc deny" [
  path: path = './.envrc'
] {
  $env.envrc.allowed = $env.envrc.allowed?
  | default []
  | where {|s| $s | default {} | get name | $in != $path }
  | uniq
}
