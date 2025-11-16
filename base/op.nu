# Modules to use for 1Password
#
# Overrides the `op` command to use credential caching even when the desktop
# application is not running or available. Favors using the `OP_FORMAT=json`
# mode for easier parsing by nu, so using `op ... | from json` will probably
# result in better output.

use ../lib *
use ../env *

const D_CACHE_OP: path = $nu.cache-dir | path join "op" "cached_creds.age"
const LPP = "op"

def nu_complete_op_accounts [] {
    run-external (oppath) "account" "list" "--format" "json"
    | from json
    | get shorthand
}

# Sign in to `op` and run the command, caching the credentials in `$D_CACHE_OP`
#
# The encryption SSH key will use the following in order:
# * the path set on the `--encrypt` command line as a private key path
# * `$OP_SIGNIN_ENCRYPT` env var as a private key path
# * default ssh key files in `~/.ssh` (`id_*` files)
# * `~/.ssh/` directory searching for pub/priv pairs
#
# Directories will get searched for normal ssh keys (id_*) first, and then
# for other non-standard names alphabetically.
#
# To use this with stdin, either `use` this module or use `nu --stdin ...`
# when running this file as a command.
#
# When using `--encrypt` with a `glob` be sure to use `--encrypt=path/*` and
# not `--encrypt path/*`.
export def main --wrapped [
    --account: string@nu_complete_op_accounts # Account to use for op
    --encrypt: oneof<path, glob> # Encrypt with ssh key at location
    --force-cached (-F) # Force using the cache without trying to `op signin`
    --signin-only # Skip the commands, just do the signin.
    --no-signin # Completely skip the signin part.
    ...r
]: any -> any {
    with-env {OP_FORMAT: "json"} {
        const lp = $"($LPP)($LP_SEP)"
        let _in = $in
        let _account = $account | default or "OP_ACCOUNT" "my"
        if ($in | is-not-empty) {
            log debug $"($lp)Running with input from stdin"
            if not ($signin_only or $no_signin) {
                log debug $"($lp)Piping input while signing in may not work!"
            }
        }
        if $signin_only and $no_signin {error make {msg: "These cannot be used together."}}
        let signed_in = if ($no_signin or "--help" in $r) {
            log debug $"($lp)Not signing in, using current env"
            {}
        } else {
            log debug $"($lp)Trying op signin..."
            signin --force-cached=$force_cached --account $_account --encrypt=$encrypt
        }
        log debug $"($lp)Signin expires at: ($signed_in.OP_EXPIRES? | default (0 | into datetime))"
        if $signin_only {
            log debug $"($lp)Trying to just sign in, no command will be run even if specified"
            $signed_in
        } else {
            with-env $signed_in {
                log debug $"($lp)PERFORMANCE: running `op`"
                $_in | run-external (oppath) "--account" $_account ...$r
            }
        }
    }
}

# Get the most useful path to `op`, ignoring custom commands and aliases
def oppath [ ]: nothing -> path {
    const lp = $"($LPP)path($LP_SEP)"
    let ops = which -a op op.exe
    | where type == "external"
    | get path
    log debug $"($lp)Checking op at ($ops)"
    try {
        let op = $ops
        | first
        log debug $"($lp)op bin: ($op)"
        return $op
    } catch {
        error make -u {msg: "No 1Password installation found!"}
    }
}

alias "op signin" = signin

# Signs into 1Password
#
# Will either output the temporary credentials (30m timeout) for use in
# `with-env` or will use the biometric unlock through the 1Password app.
# By default `op signin` will output a bash environment string that can be
# `eval`uated to get the credentials. This file is, however, not saved anywhere,
# and it relies solely on the user to either load it every time they want to
# start their shell or sign in every time they want to run an `op ...` command.
# This command saves the output into an age encrypted file along with an
# expiration date so it can be re-read without having to enter a password on
# every single command, even on different terminals.
#
# Note: This _is_ not the most secure design for this, but it balances security
# and convenience to a point that is satisfactory. If the user's private SSH key
# is not properly stored or secure, then this will allow other users on the
# machine to access their credentials temporarily.
export def "signin" [
    --verbose # Print stages to the screen
    --account: string # Override the account
    --save: path = $D_CACHE_OP # Where to save the cached credentials
    --encrypt: oneof<glob, path> # will encrypt/decrypt with the key at the given path
    --force-cached # Don't try to signin, just read the cache
]: nothing -> record {
    const lp = $"($LPP)signin($LP_SEP)"
    let _account = $account | default or "OP_ACCOUNT" "my"
    # Skip if we aren't overriding the biometric lock and aren't using the
    # raw command line
    log debug $"($lp)Biometric lock check"
    let be = $env.OP_BIOMETRIC_UNLOCK_ENABLED?
    | default "true"
    if ($be in [true "True" "true" 1 "1"]) {
        log debug $"($lp)Biometric lock enabled"
        return {}
    } else {
        log debug $"($lp)No Biometric lock available, using op-cli only"
    }

    # Will error out if there is no usable key available.
    let enc = sshkey priv ([$encrypt] | compact | flatten)
    log debug $"($lp)Reading cache from ($save)"
    let all_cache = cache read -e $enc.priv $save
    | default {}

    let cache = $all_cache | get --optional $_account
    | default {}

    let expires: datetime = $cache.OP_EXPIRES?
    | default $C_DEF
    log debug $"($lp)cached accounts: ($all_cache | columns)"
    log debug $"($lp)Old expiration: ($expires)"

    let new_vars = if (($expires <= (date now)) or ($cache | is-empty)) {
        if $force_cached {
            error arr ["Cache is no longer valid, use `op --signin-only` before running again."]
        }
        log debug $"($lp)PERFORMANCE: running `op`"
        log debug $"($lp)running `op signin --force`"
        let op_data = (run-external (oppath) "signin" "--force" "--account" $_account)
        let sv = $op_data
        | lines
        | first
        | parse 'export {key}="{val}"'
        | each {|i| {$i.key: $i.val} }
        | first

        $cache
        | merge {OP_EXPIRES: ((date now) + $C_DUR)}
        | merge $sv
    } else {
        $cache
        | merge (
            if $force_cached {
                log debug $"($lp)Note: Cache not refreshed, no `op` command run."
                {}
            } else {
                let new_exp = ((date now) + $C_DUR - 10sec)
                log debug $"($lp)New expiration: ($new_exp)"
                {OP_EXPIRES: $new_exp}
            }
        )
    }

    log debug $"($lp)Saving cache to ($save)"
    $all_cache
    | merge {$_account: $new_vars}
    | cache write -e $enc.pub $save

    return $new_vars
}
