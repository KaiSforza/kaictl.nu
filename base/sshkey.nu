use ../env *

# Declaring this here so it can be used more quickly in the `sort`
const DSF = {
    "id_ed25519": 0
    "id_ed25519_sk": 1
    "id_ecdsa": 2
    "id_ecdsa_sk": 3
    "id_rsa": 4
}

def main [] {}

# Sorts a list of files into ssh keys the way they should be sorted.
#
# Will prioritize items in `$DSF` over other keys, and order them as they are
# in `$DSF`.
export def "sshkey sort" [f, j] {
    let fn = $f.name | path basename
    let jn = $j.name | path basename
    match [($fn in $DSF), ($jn in $DSF)] {
        [true true] => {($DSF | get $fn) < ($DSF | get $jn)}
        [true, false] => true
        [false, true] => false
        _ => {$fn < $jn }
    }
}

export def "sshkey priv" [
    keypaths: list<oneof<glob, path>> = []
]: nothing -> record<priv: path, pub: oneof<path, string>> {
    let keylocs = if ($keypaths | is-not-empty) {
            $keypaths
        } else {
            [
                $env.OP_SIGNIN_ENCRYPT?
                ($env.CBS_DEVSHELL_HOME? | default $env.home | path join ".config" "ssh" "*")
                "~/.ssh/*"
            ]
            | compact
        }
        | into glob

    match (sshkey find $keylocs) {
        null => {error make -u {msg: ([
            "No keys found! Please create a key or specify it with"
            "`--encrypt` on the command line."
            "Tried searching the following paths/globs:"
            ...($keylocs | each {|s| $" * ($s)"})
        ] | str join (char newline))}}
        $x => $x
    }
}
# Finds the ssh private keys in the given directory or file
#
# If given a path, it will search in that path
export def "sshkey find" [
    search: list<glob>
]: nothing -> oneof<record<priv: path, pub: oneof<path, string>>, nothing> {
    const lp = $"findkey($LP_SEP)"
    log debug $"($lp)Checking for files in ($search)..."
    let files = $search | each {|s|
        glob --no-dir $s
        | if ($in | is-not-empty) {ls ...$in} else {[]}
        | where {|f| $f.size <= 4kb }
        | sort-by --custom {|f j| sshkey sort $f $j}
    }
    | flatten

    log debug $"($lp)Files found:(char newline)($files | get name | to json)"

    for f in $files {
        let ssh_pubkey = (ssh-keygen -y -f $f.name | complete)
        if $ssh_pubkey.exit_code == 0 {
            let pp = if ($"($f.name).pub" | path exists) {
                {priv: $f.name, pub: $"($f.name).pub"}
            } else {
                {priv: $f.name, pub: ($ssh_pubkey.stdout | str trim)}
            }
            log debug $"($lp)Good private/public key found: ($pp)"

            return $pp
        }
    }
    return null
}

def "sshkey verify" [
    opis: list<record>,
    rec: record<path: string, fprint: string>
]: nothing -> string {
    if ($opis | where op_url == $rec.path | get additional_information | first) != $rec.fprint {
        $rec.path
    }
}

