# Convnenience functions for Nushell

# Default duration for op cli to cache credentials without the desktop app
export const C_DUR: duration = 30min
# Old enough to invalidate the cache
export const C_DEF: datetime = 2000-01-01
# Where to store the cached files in `cache read`
export const D_CACHE: path = $nu.cache-dir
export const LP_SEP: string = "|"
export const AWS_ACCOUNT_OP_URL: string = "op://Personal/aws" # Must be 'op://...'

export use std/log

export-env {
    # Use a better log format
    $env.NU_LOG_FORMAT = (
        $env.NU_LOG_FORMAT?
        | default $"%ANSI_START%=> %DATE%($LP_SEP)(ansi u)%LEVEL%(ansi rst_u)($LP_SEP)%MSG%%ANSI_STOP%"
    )
    $env.NU_LOG_DATE_FORMAT = (
        $env.NU_LOG_DATE_FORMAT?
        | default "%H:%M:%S%.3f"
    )
    use std/log []
}

# Optionally return `elems` or an empty array
#
# similar to nix's `lib.optionals`
export def optionals [
    cond: any # Condition (bool, array, etc.)
    elems: list # The output if the condition is true
]: [
    nothing -> list
] {
    if not (($cond == false) or ($cond | is-empty)) {
        $elems
    } else {
        []
    }
}

export def try-open [p]: nothing -> string {
    try {open --raw $p} catch {""}
}

# Just an easier way to write errors using a list of strings.
#
# Strings are joined on a newline.
export def "error arr" [
    msg: list<string>
    more: record = {}
    --unspanned (-u) # Use `error make -u`
    --space # Use space instead of newline
] {
    error make --unspanned=$unspanned (
        {
            msg: ($msg | str join (if $space {char space} else {char newline}))
        }
        | merge $more
    )
}

# Default or an env var or a default
export def "default or" [
    e: string
    d: any
]: any -> any {
    let _e = $in
    if $_e == null or $_e == false {
        let ee = $env | get --optional $e
        if $ee == null or $ee == false {
            return $d
        }
        return $ee
    }
    return $_e
}
