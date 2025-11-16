# Show help information for nushell and external commands

# Default indent to use, set to 2 for compactness
const indent = "  "
# Default prompt ($env.PROMPT_INDICATOR_* are not constants)
const prompt = $"(ansi g)> (ansi rst)"

def linewrap [
    length: int
] {
    [$in] | table --index=false
}

# Returns a string that's an 80 char wide table for things like subcommands
#
# Does some easy line-wrapping for the strings
export def noheader [
    --width: int = 90 # Default width for the table
    --something-long (-s): record<foo: string bar: string> # foobar this is a long one okay wow
]: table -> string {
    let intable = $in
    $env.config.color_config.leading_trailing_space_bg = {}

    # let maxwidths = $intable | values | each {
    #     str join (char newline) | lines | str length | math max
    # }

    # print ($intable | values | each {str join (char newline)} | table -e)
    # print $maxwidths

    # $intable
    # | each {|t|
    #     $t
    #     | items {}
    # }
    $intable
    | table --index=false -e --theme none --width=$width
    | lines
    | each {|line| $"($indent)($line | str replace -r '^ ' '')"}
    | skip
    | str join (char newline)
# }
}

def compten [] {compact | flatten}

def "sections join" []: list<oneof<list<any>, nothing, string>> -> string {
    let input: list<list<any>> = $in
    let interspersed: list<list<any>> = $input
    | skip
    | compact
    | each {|l| $l | prepend ""}

    $input
    | take 1
    | $in ++ $interspersed
    | flatten
    | str join (char newline)
}

def error-fmt [] {
    $"(ansi red)($in)(ansi reset)"
}

def throw-error [error: string, msg: string, span: record] {
    error make {
        msg: ($error | error-fmt)
        label: {
            text: $msg
            span: $span
        }
    }
}

def module-not-found-error [span: record] {
    throw-error "std::help::module_not_found" "module not found" $span
}

def alias-not-found-error [span: record] {
    throw-error "std::help::alias_not_found" "alias not found" $span
}

def extern-not-found-error [span: record] {
    throw-error "std::help::extern_not_found" "extern not found" $span
}

def operator-not-found-error [span: record] {
    throw-error "std::help::operator_not_found" "operator not found" $span
}

def command-not-found-error [span: record] {
    throw-error "std::help::command_not_found" "command not found" $span
}

# Manually set list of operators
def get-all-operators [] {
    [
        [type, operator, name, description, precedence];
        [Assignment, =, Assign, 'Assigns a value to a variable.', 10]
        [Assignment, +=, AddAssign, 'Adds a value to a variable.', 10]
        [Assignment, -=, SubtractAssign, 'Subtracts a value from a variable.', 10]
        [Assignment, *=, MultiplyAssign, 'Multiplies a variable by a value.', 10]
        [Assignment, /=, DivideAssign, 'Divides a variable by a value.', 10]
        [Assignment, ++=, ConcatenateAssign, 'Concatenates a list, a string, or a binary value to a variable of the same type.', 10]
        [Comparison, ==, Equal, 'Checks if two values are equal.', 80]
        [Comparison, !=, NotEqual, 'Checks if two values are not equal.', 80]
        [Comparison, <, LessThan, 'Checks if a value is less than another.', 80]
        [Comparison, >, GreaterThan, 'Checks if a value is greater than another.', 80]
        [Comparison, <=, LessThanOrEqual, 'Checks if a value is less than or equal to another.', 80]
        [Comparison, >=, GreaterThanOrEqual, 'Checks if a value is greater than or equal to another.', 80]
        [Comparison, '=~ or like', RegexMatch, 'Checks if a value matches a regular expression.', 80]
        [Comparison, '!~ or not-like', NotRegexMatch, 'Checks if a value does not match a regular expression.', 80]
        [Comparison, in, In, 'Checks if a value is in a list, is part of a string, or is a key in a record.', 80]
        [Comparison, not-in, NotIn, 'Checks if a value is not in a list, is not part of a string, or is not a key in a record.', 80]
        [Comparison, has, Has, 'Checks if a list contains a value, a string contains another, or if a record has a key.', 80]
        [Comparison, not-has, NotHas, 'Checks if a list does not contains a value, a string does not contains another, or if a record does not have a key.', 80]
        [Comparison, starts-with, StartsWith, 'Checks if a string starts with another.', 80]
        [Comparison, not-starts-with, NotStartsWith, 'Checks if a string does not start with another.', 80]
        [Comparison, ends-with, EndsWith, 'Checks if a string ends with another.', 80]
        [Comparison, not-ends-with, NotEndsWith, 'Checks if a string does not end with another.', 80]
        [Math, +, Add, 'Adds two values.', 90]
        [Math, -, Subtract, 'Subtracts two values.', 90]
        [Math, *, Multiply, 'Multiplies two values.', 95]
        [Math, /, Divide, 'Divides two values.', 95]
        [Math, //, FloorDivide, 'Divides two values and floors the result.', 95]
        [Math, mod, Modulo, 'Divides two values and returns the remainder.', 95]
        [Math, **, Pow, 'Raises one value to the power of another.', 100]
        [Math, ++, Concatenate, 'Concatenates two lists, two strings, or two binary values.', 80]
        [Bitwise, bit-or, BitOr, 'Performs a bitwise OR on two values.', 60]
        [Bitwise, bit-xor, BitXor, 'Performs a bitwise XOR on two values.', 70]
        [Bitwise, bit-and, BitAnd, 'Performs a bitwise AND on two values.', 75]
        [Bitwise, bit-shl, ShiftLeft, 'Bitwise shifts a value left by another.', 85]
        [Bitwise, bit-shr, ShiftRight, 'Bitwise shifts a value right by another.', 85]
        [Boolean, or, Or, 'Checks if either value is true.', 40]
        [Boolean, xor, Xor, 'Checks if one value is true and the other is false.', 45]
        [Boolean, and, And, 'Checks if both values are true.', 50]
        [Boolean, not, Not, 'Negates a value or expression.', 55]
    ]
}

def "nu-complete list-aliases" [] {
    scope aliases | select name description | rename value description
}

def "nu-complete list-modules" [] {
    scope modules | select name description | rename value description
}

def "nu-complete list-operators" [] {
    let completions = (
        get-all-operators
        | select name description
        | rename value description
    )
    $completions
}

def "nu-complete list-commands" [] {
    scope commands | select name description | rename value description
}

def "nu-complete main-help" [] {
    [
        { value: "commands", description: "Show help on Nushell commands." }
        { value: "aliases", description: "Show help on Nushell aliases." }
        { value: "modules", description: "Show help on Nushell modules." }
        { value: "externs", description: "Show help on Nushell externs." }
        { value: "operators", description: "Show help on Nushell operators." }
        { value: "escapes", description: "Show help on Nushell string escapes." }
    ]
    | append (nu-complete list-commands)
}

def "nu-complete list-externs" [] {
    scope commands | where type == "external" | select name description | rename value description
}

def build-help-header [
    text: string
    --newline (-n)
] {
    let header = $"(ansi green)($text)(ansi reset):"

    if not $newline {
        $header
    } else {
        $header ++ (char newline)
    }
}

# Highlight (and italicize) code in backticks, fallback to dimmed for invalid syntax
def nu-highlight-desc [
    --fallback: string = (ansi d)
] {
    if (config use-colors) {
        str replace -ar '(?<!`)`([^`]+)`(?!`)' {||
            let s = $in
            | str trim -c '`'
            $s
            | try {
                nu-highlight --reject-garbage
            } catch {
                $"($fallback)($s)(ansi rst)"
            }
            | $"(ansi i)($in)(ansi rst_i)"
        }
    } else {}
}

def "format type" []: string -> string {
    $in
    | str replace -ra "([^<]+)(<)" $"(ansi bo)$1(ansi rst_bo)$2"
    | $"<(ansi b)($in)(ansi rst)>"
}

def "format cmd" [] {
    let cmd = $in
    $"(ansi default_dimmed)(ansi default_italic)($cmd)(ansi reset)"
}


def build-module-page [module: record] {
    let name = [
        $"(build-help-header "Module") ($module.name)"
    ]

    let description = if ($module.description? | is-not-empty) {[
        ($module.description | nu-highlight-desc)
    ]}

    let extra_description = if ($module.extra_description? | is-not-empty) {[
        ($module.extra_description | nu-highlight-desc)
    ]}

    let submodules = if ($module.submodules? | is-not-empty) {[
        (build-help-header "Submodules")
        $"(
            $module.submodules
            | each {|submodule|
                {
                    m: $"(ansi cb)($submodule.name)(ansi rst)"
                    d: $submodule.description
                }
                # $'($indent)(ansi cb)($submodule.name)(ansi rst) (char lparen)($module.name) ($submodule.name)(char rparen) - ($submodule.description)'
            }
            | noheader
            # | str join (char newline)
        )"
    ]}

    let cmdinfo = scope commands | where name in $module.commands.name

    let commands = if ($module.commands? | is-not-empty) {[
        (build-help-header "Exported commands")
        $"(
            $module.commands | each {|command|
                {
                    n: $'(ansi cb)($command.name)(ansi rst)'
                    d: ($cmdinfo | where name == $command.name).description
                }
                # $'($indent)(ansi cb)($command.name)(ansi rst)' #' (char lparen)($module.name) ($command.name)(char rparen)'
            }
            | noheader
        )"
    ]}

    let aliases = if ($module.aliases? | is-not-empty) {[
        (build-help-header "Exported aliases")
        $"($indent)($module.aliases.name | str join (char newline))"
    ]}

    # Always show the env block
    let env_block = [
        (if not $module.has_env_block {
            $"This module (ansi cyan)does not export(ansi reset) environment."
        } else {
            $"This module (ansi cyan)exports(ansi reset) environment."
        })
    ]

    [$name $description $extra_description $submodules $commands $aliases $env_block] | sections join
}

# Show help on nushell modules.
#
# When requesting help for a single module, its commands and aliases will be highlighted if they
# are also available in the current scope. Commands/aliases that were imported under a different name
# (such as with a prefix after `use some-module`) will be highlighted in parentheses.
@example "show all aliases" {help modules}
@example "search for string in module names" {help modules --find ba}
@example "search help for single module" {help modules foo}
export def modules [
    ...module: string@"nu-complete list-modules" # the name of module to get help on
    --find (-f): string # string to find in module names
]: nothing -> any {
    let modules = (scope modules)

    if ($find | is-not-empty) {
        $modules | find $find --columns [name description]
    } else if ($module | is-not-empty) {
        let found_module = ($modules | where name == ($module | str join " "))

        if ($found_module | is-empty) {
            module-not-found-error (metadata $module | get span)
        }

        build-module-page ($found_module | get 0)
    } else {
        $modules
    }
}

def build-alias-page [alias: record]: nothing -> string {
    let ad = $alias.description? | default ""
    let description = if (
        $ad | is-not-empty
    ) or not (
        $ad != $"Alias for `($alias.expansion)`"
    ) {[
        ($alias.description | nu-highlight-desc)
    ]}

    let aname = [
        (build-help-header "Alias")
        $"($indent)($alias.name)"
    ]

    let expansion = [
        (build-help-header "Expansion")
        (
            $alias.expansion
            | lines
            | each {$"($indent)($in)"}
            | str join (char newline)
        )
    ]

    [$aname $description $expansion] | sections join
}

# Show help on nushell aliases.
@example "show all aliases" {help aliases}
@example "search for string in alias names" {help aliases --find ba}
@example "search help for single alias" {help aliases multi}
export def aliases [
    ...alias: string@"nu-complete list-aliases" # the name of alias to get help on
    --find (-f): string # string to find in alias names
]: nothing -> any {
    let aliases = (scope aliases | sort-by name)

    if ($find | is-not-empty) {
        $aliases | find $find --columns [name description]
    } else if ($alias | is-not-empty) {
        let found_alias = ($aliases | where name == ($alias | str join " "))

        if ($found_alias | is-empty) {
            alias-not-found-error (metadata $alias | get span)
        }

        build-alias-page ($found_alias | get 0)
    } else {
        $aliases
    }
}

# Show help on nushell externs.
export def externs [
    ...extern: string@"nu-complete list-externs" # the name of extern to get help on
    --find (-f): string # string to find in extern names
]: nothing -> any {
    let externs = (
        scope commands
        | where type == "external"
        | sort-by name
        | upsert description {|d| $d.description | str trim}
    )

    if ($find | is-not-empty) {
        $externs
        | find $find --columns [name description]
        | select name description
    } else if ($extern | is-not-empty) {
        let found_extern = ($externs | where name == ($extern | str join " "))

        if ($found_extern | is-empty) {
            extern-not-found-error (metadata $extern | get span)
        }

        build-command-page ($found_extern | get 0)
    } else {
        $externs
        | select name description
    }
}

def build-operator-page [operator: record] {
    [
        (build-help-header "Description")
        $"($indent)($operator.description)"
        (build-help-header "Operator")
        $"($indent)($operator.name) (char lparen)(ansi cyan_bold)($operator.operator)(ansi reset)(char rparen)"
        (build-help-header "Type")
        $"($indent)($operator.type)"
        (build-help-header "Precedence")
        $"($indent)($operator.precedence)"
    ] | str join (char newline)
}

alias "help operators" = operators # Command args are different

# Show help on nushell operators.
@example "search for string in operators names" { help operators --find Bit }
@example "search help for single operator" { help operators NotRegexMatch }
export def operators [
    ...operator: string@"nu-complete list-operators" # the name of operator to get help on
    --find (-f): string # string to find in operator names
]: nothing -> any {
    let operators = (get-all-operators)

    if ($find | is-not-empty) {
        $operators | find $find --columns [type name]
    } else if ($operator | is-not-empty) {
        let found_operator = ($operators | where name == ($operator | str join " "))

        if ($found_operator | is-empty) {
            operator-not-found-error (metadata $operator | get span)
        }

        build-operator-page ($found_operator | get 0)
    } else {
        $operators
    }
}

def get-extension-by-prefix [prefix: string] {
    scope commands
    | where name starts-with $prefix
    | insert extension { get name | parse $"($prefix){ext}" | get ext.0 | $"*.($in)" }
    | select extension name
    | rename --column { name: command }
}

def get-command-extensions [command: string] {
    let extensions = {
        "open": {||
            [
                "The following extensions are recognized and will be piped into `command`:"
                (get-extension-by-prefix "from " | table --theme="none" --index false)
            ]
        }

        "save": {||
            [
                "The following extensions are recognized and will be piped into `command`:"
                (get-extension-by-prefix "to " | table --theme="none" --index false)
            ]
        }
    }

    if $command in $extensions {
        $extensions
        | get $command
        | do $in
        | each { lines | each { $"($indent)($in)" } | str join (char newline) }
        | nu-highlight-desc
    } else {
        []
    }
}

def build-command-page [command: record]: nothing -> any {
    let description = if ($command.description? | is-not-empty) {[
        ($command.description | nu-highlight-desc)
    ]}
    let extra_description = if ($command.extra_description? | is-not-empty) {[
        ($command.extra_description | nu-highlight-desc)
    ]}

    let search_terms = if ($command.search_terms? | is-not-empty) {[
        $"(build-help-header 'Search terms') ($command.search_terms)"
    ]}

    let category = if ($command.category? | is-not-empty) {[
        $"(build-help-header 'Category') ($command.category)"
    ]}

    let signatures = ($command.signatures | transpose | get column1)

    let parameters = $signatures | get --optional 0 | default [] | where parameter_type != input and parameter_type != output
    let is_rest = $parameters | where parameter_type == rest | is-not-empty
    let positionals = $parameters | where parameter_type == positional and parameter_type != rest
    let required = $positionals | where is_optional == false
    let optionals = $positionals | where is_optional == true
    let flags = $parameters | where parameter_type != positional and parameter_type != rest

    let cli_usage = if ($signatures | is-not-empty) {
        [
            (build-help-header "Usage")
            ([
                $"($indent)($prompt)`($command.name)` "
                (if ($flags | is-not-empty) { "`[flags]` " })
                ($required | each {|param|
                    $"<`($param.parameter_name)`> "
                })
                ($optionals | each {|param|
                    $"[`($param.parameter_name)`] "
                })
                (if $is_rest { "`(...$rest)`"})
            ]
            | compact
            | flatten
            | str join ""
            | nu-highlight-desc --fallback (ansi c))
        ]
    }

    let subcommands = (scope commands | where name =~ $"^($command.name) " | select name description)
    let subcommands = if ($subcommands | is-not-empty) {[
        (build-help-header "Subcommands")
        ($subcommands
            | select name description
            | upsert name {|sc| $"(ansi teal)($sc.name)(ansi rst)"}
            | noheader
        )
        # ($subcommands | each {|subcommand |
        #     $"($indent)(ansi teal)($subcommand.name)(ansi reset) - ($subcommand.description)"
        # } | str join (char newline))
    ]}

    let rest = (if ($signatures | is-not-empty) {
        let flags =  $parameters
        | where parameter_type != positional and parameter_type != rest
        | if "help" not-in $in.parameter_name or "h" not-in $in.short_flag {
            $in ++ [{
                parameter_name: "help"
                short_flag: (if "h" not-in $in.short_flag {"h"})
                syntax_shape: null
                description: "Display the help message for this command"
                parameter_default: null
            }]
        }

        let cmd_flags = if ($flags | is-not-empty) {[
            (build-help-header "Flags")
            ($flags | each {|flag|
                {
                    f: ([
                        (if ($flag.parameter_name | is-not-empty) {
                            $"--(ansi teal)($flag.parameter_name)(ansi reset)"
                        }),
                        ...(
                            if ($flag.short_flag | is-not-empty) {
                            [
                                ","
                                (if (($flag.parameter_name | str length) > 5) {
                                    $"(char newline)($indent)"
                                } else {" "})
                                $"-(ansi teal)($flag.short_flag)(ansi reset)"
                            ]
                            }
                        )
                        ...(if ($flag.syntax_shape | is-not-empty) {
                            [
                                
                                (if (($flag.syntax_shape | str length) > 12) {
                                    $"(char newline)($indent)"
                                } else {" "})
                                $"($flag.syntax_shape | format type)"
                            ]
                        }),
                    ] | compact | flatten | str join '')
                    d: ([(if ($flag.description | is-not-empty) {
                            $"($flag.description)"
                        }),
                        (if ($flag.parameter_default | is-not-empty) {
                            $"\n\(default: ($flag.parameter_default
                                | if ($in | describe -d).type == string { debug -v } else {})\)"
                        })
                    ] | str join "")
                }
            } | noheader)
        ]}


        let type_signatures = if ($signatures | is-not-empty) {[
            (build-help-header "Signatures")
            ...($signatures | each {|signature|
                let input = ($signature | where parameter_type == input | get 0)
                let output = ($signature | where parameter_type == output | get 0)
                [
                    $indent
                    ...[(if $input.syntax_shape != nothing {
                        $"($input.syntax_shape | format type) | "
                    })]
                    $"($'`($command.name)`' | nu-highlight-desc --fallback (ansi cb))"
                    $" -> ($output.syntax_shape | format type)"
                ] | str join ""
            })
        ]}

        let parameters = if ($positionals | is-not-empty) or $is_rest {
            [
                (build-help-header "Parameters")
                ...($positionals | each {|positional|
                    [
                        $indent
                        $"(ansi teal)($positional.parameter_name)(ansi reset)",
                        (if ($positional.syntax_shape | is-empty) { "" } else {
                            $": ($positional.syntax_shape | format type)"
                        }),
                        (if ($positional.description | is-empty) { "" } else {
                            $" ($positional.description)"
                        }),
                        (if ($positional.parameter_default | is-empty) { "" } else {
                            $" \(optional, default: ($positional.parameter_default)\)"
                        })
                    ] | str join ""
                })
                (if $is_rest {
                    let rest = ($parameters | where parameter_type == rest | get 0)
                    [
                        $indent
                        $"...(ansi teal)rest(ansi reset): ($rest.syntax_shape | format type)"
                        (if ($rest.description |is-not-empty) {$rest.description})
                    ] | str join ""
                })
            ]
            | compact
        }
        [
            $cmd_flags
            $type_signatures
            $parameters
        ]
        | sections join
    })

    # This section documents how the command can be extended
    # E.g. `open` can be extended by adding more `from ...` commands
    let extensions = (
        get-command-extensions $command.name
        | if ($in | is-not-empty) {
            prepend [
              (build-help-header "Extensions")
            ]
        }
    )

    let examples = if ($command.examples | is-not-empty) {[
        (build-help-header "Examples")
        ($command.examples | each {|example| [
            $"($indent)(ansi d)# ($example.description)(ansi rst)"
            $"($indent)($prompt)($example.example | if (config use-colors) { nu-highlight } else {})"
            ...[(if ($example.result | is-not-empty) {
                $example.result
                | table -e
                | to text
                | str trim --right
                | lines
                | skip until { is-not-empty }
                | each {|line|
                    $"($indent)($line)"
                }
                | str join (char newline)
            })]
        ] | compact | str join (char newline)})
    ] | flatten}

    [
        $description
        $extra_description
        $search_terms
        $category
        $cli_usage
        $subcommands
        $rest
        $extensions
        $examples
    ]
    | sections join
}

def scope-commands [
    ...command: string@"nu-complete list-commands" # the name of command to get help on
    --find (-f): string # string to find in command names and description
] {
    let commands = (scope commands | sort-by name)

    if ($find | is-not-empty) {
        # TODO: impl find for external commands
        $commands | find $find --columns [name description search_terms] | select name category description signatures search_terms
    } else if ($command | is-not-empty) {
        let target_command = ($command | str join " ")
        let found_command = ($commands | where name == $target_command)

        if ($found_command | is-empty) {
            command-not-found-error (metadata $command | get span)
        } else {
            build-command-page ($found_command | get 0)
        }
    } else {
        $commands | select name category description signatures search_terms
    }
}

def external-commands [
    ...command: string@"nu-complete list-commands",
] {
    let target_command = $command | str join " " | str replace "^" ""
    print -e $"(ansi default_italic)Help pages from external command ($target_command | format cmd):(ansi reset)"
    if $env.NU_HELPER? == "--help" {
        run-external ($target_command | split row " ") "--help"
        | if $nu.os-info.name == "windows" { collect } else {}
    } else {
        ^($env.NU_HELPER? | default "man") $target_command
    }
}

# Show help on commands.
export def commands [
    ...command: string@"nu-complete list-commands" # the name of command to get help on
    --find (-f): string # string to find in command names and description
]: nothing -> any {
    try {
        scope-commands ...$command --find=$find
    } catch {
        external-commands ...$command
    }
}

# Display help information about different parts of Nushell.
#
# Welcome to Nushell!
#
# `help word` searches for "word" in commands, aliases and modules, in that order.
# If not found as internal to nushell, you can set `$env.NU_HELPER` to a program
# (default: man) and "word" will be passed as the first argument.
# Alternatively, you can set `$env.NU_HELPER` to `--help` and it will run "word" as
# an external and pass `--help` as the last argument (this could cause unintended
# behaviour if it doesn't support the flag, use it carefully).
#
# Here are some tips to help you get started.
#   * `help -h` or `help help` - show available `help` subcommands and examples
#   * `help commands` - list all available commands
#   * `help <name>` - display help about a particular command, alias, or module
#   * `help --find <text to search>` - search through all help commands table
#
# Nushell works on the idea of a `pipeline`. Pipelines are commands connected
# with the `|` character. Each stage in the pipeline works together to load,
# parse, and display information to you.
#
# You can also learn more at https://www.nushell.sh/book/
@example "show help for single command, alias, or module" {help match}
@example "show help for single sub-command, alias, or module" {help str join}
@example "search for string in command names, description and search terms" {help --find char}
export def main [
    ...item: string@"nu-complete main-help" # the name of the help item to get help on
    --find (-f): string # string to find in help items names and description
]: nothing -> string {
    if ($item | is-empty) and ($find | is-empty) {
        print (main help)
        return
    }

    let target_item = ($item | str join " ")

    let commands = try { scope-commands $target_item --find $find }
    if ($commands | is-not-empty) { return $commands }

    let aliases = try { aliases $target_item --find $find }
    if ($aliases | is-not-empty) { return $aliases }

    let modules = try { modules $target_item --find $find }
    if ($modules | is-not-empty) { return $modules }

    let pipe_redir = try { pipe-and-redirect $target_item --find $find }
    if ($pipe_redir | is-not-empty) { return $pipe_redir}

    if ($find | is-not-empty) {
        print -e $"No help results found mentioning: ($find)"
        return []
    }
    # use external tool (e.g: `man`) to search help for $target_item
    # the stdout and stderr of external tool will follow `main` call.
    external-commands $target_item
}

