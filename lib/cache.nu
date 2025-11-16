# Cache reading and writing using age and SSH keys for encryption

use ./sshkey.nu *
use ./consts.nu *

# Read from a cache if it exists, or default to an empty record.
#
# You probably want to use `cache cuse` or `cuse`, depending on how it is
# imported.
export def "cache read" [
    --encrypt (-e): path # Path to the private key
    --default (-d): string = "{}" # Default output as a string
    save: path # Path to read the nuon string from
]: nothing -> record {
    const lp = $"cache read($LP_SEP)"
    let outpath: path = $save | path expand
    if ($outpath | path exists) {
        open $outpath --raw
        | do (
            if ($encrypt | is-empty) {
                {||}
            } else {
                let epath: path = $encrypt | path expand
                log debug $"($lp)epath: ($epath)"
                {||
                    rage --decrypt --identity $epath
                    | complete
                    | get -o stdout
                    | default $default
                    | from nuon
                }
            }
        )
    } else {
        mkdir ($outpath | path dirname)
        return null
    }
}

# Encrypt and write to a cache, creating the file if it doesn't exist.
#
# You probably want to use `cache cuse` or `cuse`, depending on how it is
# imported, it is much safer than using this alone.
export def "cache write" [
    --encrypt (-e): string # Path to or string of the public key
    save: path # Path to store the nuon string in
]: any -> nothing {
    let outpath = $save | path expand
    mkdir ($outpath | path dirname)
    $in
    | to nuon --raw
    | do (if ($encrypt | is-empty) {
        {||}
    } else {
        let epath = $encrypt | path expand
        if ($epath | path exists) {
            {|| rage --encrypt --armor --recipients-file $epath}
        } else {
            {|| rage --encrypt --armor --recipient $epath}
        }
    })
    | save -f $outpath
}

# Try the cache, otherwise run the `miss` closure
#
# This simplifies a lot of the caching that needs to be done. Data is stored in
# a record, with a specific key being used for each cache entry. Cache entries
# are themselves a record, and an expiration key (default: `Expiration`) must be
# present in the record. This determines if the cache is hit or not based on
# time.
#
# Use `delta` to require the cache to be valid for more than just that instant.
# For example, if this is part of something that will run for about 10 minutes
# use `--delta 10min` to make sure the cache is valid for that long.
#
# There is no option for this to not encrypt the file, it _will_ be encrypted
# using the users' ssh key, or using the `--encrpyt` option to choose a specific
# pub/priv keypair.
@example "cache an ssh public key" {
    (
        cache try
        ($env.HOME | path join "key")
        "keyname" {|| {
            Expiration: (date now | $in + 12hr)
            key: (open ~/.ssh/id_ed25519.pub)
        }}
    )
} --result {key: "...", Expiration: ...}
export def "cache try" [
    --encrypt (-e): path # A specific key used for encryption, will find a sane default otherwise
    --expiration-key (-k): string = "Expiration" # Where the expiration data is stored
    --delta (-d): duration = 1min # How long to require the key to be available for after this command
    cachepath: path # Location of the cache file
    key: string # Which key to grab in the cache
    miss: closure # Closure to run in case of a miss
]: nothing -> any {
    const lp = $"cache cuse($LP_SEP)"
    let enc = match $encrypt {
        null => {sshkey key}
        $x => {sshkey key $encrypt}
    }

    let all_cache = read -e $enc.priv $cachepath
    | default {}

    let retried = {||
        log debug $"($lp)Not cached, Reauthenticating"
        let missed = do $miss
        $all_cache
        | merge {$"($key)": $missed}
        | write -e $enc.pub $cachepath
        $missed
    }

    match ($all_cache | get -o $key) {
        null => {return (do $retried)}
        $x if ($x | get --optional $expiration_key | default $C_DEF) < ((date now) - $delta)    => {
            return (do $retried)
        }
        $x => $x
    }
}
