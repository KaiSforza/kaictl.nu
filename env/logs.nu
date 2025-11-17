use ../lib/consts.nu *
export-env {
    # Use a better log format
    $env.NU_LOG_FORMAT = $"%ANSI_START%=> %DATE%($LP_SEP)(ansi u)%LEVEL%(ansi rst_u)($LP_SEP)%MSG%%ANSI_STOP%"
    $env.NU_LOG_DATE_FORMAT = "%H:%M:%S%.3f"
    use std/log []
}
