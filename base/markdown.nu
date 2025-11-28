# Convert from markdown to a nice text representation for the terminal

# null string to separate the lines when we're still parsing.
const N = "\u{0}"

export def "from md" [
    --width (-w): int = 100
]: string -> any {
    let md = $in
    let paragraphs = $md | lines | split list --split after ''
    $paragraphs
    | each {str join $N}  # Join with nulls for parsing later
    | each {lists}
    | each {linebreak}
    | each {str join ''}
    # | str join (char newline)
}

def style []: string -> string {
    (
        str replace --regex
        '\*\*(.+)\*\*'
        $"( )"
    )
}

def lists []: string -> string {
    str replace --all --regex '(?m)(\n|\u{0})(\s*)[*-] ([^\u{0}]+)' "\n$2 $3"
}

def linebreak []: string -> string {
    str replace --regex '  \u{0}' "  \n"
}
