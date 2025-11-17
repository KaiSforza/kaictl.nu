# Convnenience functions for Nushell

export use std/log
export use ./cache.nu *
export use ./sshkey.nu *
export use ./consts.nu *


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

# Wrap a string using `table`'s wrapping width
#
# `table` keeps spaces if the break between the two lines has a single space.
# Using a double space will keep the space there. Note, this means that the
# following will work:
# 
#   `let s = "12345678 1234567"`
#   `$s | str wrap 10 | lines | str join ' ' | $in == $s`
#   ==> `true`
#
# but it will probably not work with multiple spaces.
export def "str wrap" [
    --unindent (-u) # Unindent the string 
    width: int
]: string -> string {
    let in_text: string = $in
    $env.config.table = {
        trim: {methodology: "wrapping" wrapping_try_keep_words: true}
        padding: {left: 0 right: 0}
        mode: "none"
    }

    [$in_text]
    | table -e --width $width --index=false
    | ansi strip
}
