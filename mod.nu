# Main modules for convenience functions and other uses
#
# See `help <command>` for more info on each submodule.

use ./env *
use std/log
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

export use base *
