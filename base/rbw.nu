# External settings for `rbw`, the Rust Bitwarden CLI

const rbw_fields = ["id" "name" "user" "folder"]

# Unofficial Bitwarden CLI
export extern "rbw main" [
    --version (-v) # Print version
]

# Check if the local Bitwarden database is unlocked (nu version)
def "rbw is-unlocked" []: nothing -> bool {
    ^rbw unlocked | complete | $in.exit_code == 0
}

# Get a list of item names for completion
def nu_complete_rbw_items []: nothing -> list<string> {
    if (rbw is-unlocked) {
        ^rbw list --raw
        | from json
        | get name
    } else {
        []
    }
}

# Get a list of folders for completion
def nu_complete_rbw_folders []: nothing -> list<string> {
    if (rbw is-unlocked) {
        ^rbw list --raw
        | from json
        | get folders
        | uniq
        | compact
    } else {
        []
    }
}

# Display the authenticator code for a given entry
export extern "rbw code" [
    NEEDLE: string@nu_complete_rbw_items # Name, URI or UUID of the entry to display
    USER: oneof<string, nothing> = null # Username for the entry
    --folder: string@nu_complete_rbw_folders
    --ignorecase (-i)
    --clipboard
]

# Display the password for a given entry
export extern "rbw get" [
    NEEDLE: string@nu_complete_rbw_items # Name, URI or UUID of the entry to display
    USER: oneof<string, nothing> = null # Username for the entry
    --folder: string@nu_complete_rbw_folders # Folder name to search in
    --field: string # Fields to get
    --full # Show notes as well as password
    --raw # Display output as JSON
    --ignorecase (-i) # Ignore case
    --clipboard # Copy result to clipboard
]

# List all entries in the local Bitwarden database
export extern "rbw list" [
    --fields: string@$rbw_fields = "name" # Fields to display
    --raw # Display output as JSON
]

# Search for entries
export extern "rbw search" [
    TERM: string
    --fields: string@$rbw_fields = "name" # Fields to display
    --folder: string@nu_complete_rbw_folders # Folder name to search in
    --raw # Display output as JSON
]

# Add a new password to the database
export extern "rbw add" [
    NAME: string # Name for the entry
    USER: oneof<string, nothing> = null # Username for the entry
    --uri: string # URI for the entry
    --folder: string@nu_complete_rbw_folders # Folder name to search in
]

# Generate a new password
export extern "rbw generate" [
    LEN: int # Length of the password to generate
    NAME: oneof<string, nothing> = null # Name for the entry
    USER: oneof<string, nothing> = null # Username for the entry
    --uri: string # URI for the entry
    --folder: string@nu_complete_rbw_folders # Folder name to search in
    --no-symbols # Generate a password with no special characters
    --only-numbers # Generate a password with only numbers
    --nonconfusables # Generate a password without visually similar characters
    --diceware # Generate a password of multiple dictionary words
]

# Modify an existing password
export extern "rbw edit" [
    NEEDLE: string@nu_complete_rbw_items # Name, URI or UUID of the entry to display
    USER: oneof<string, nothing> = null # Username for the entry
    --folder: string@nu_complete_rbw_folders # Folder name to search in
    --ignorecase (-i) # Ignore case
]

# Remove a given entry
export extern "rbw remove" [
    NEEDLE: string@nu_complete_rbw_items # Name, URI or UUID of the entry to display
    USER: oneof<string, nothing> = null # Username for the entry
    --folder: string@nu_complete_rbw_folders # Folder name to search in
    --ignorecase (-i) # Ignore case
]

# View the password history for a given entry
export extern "rbw history" [
    NEEDLE: string@nu_complete_rbw_items # Name, URI or UUID of the entry to display
    USER: oneof<string, nothing> = null # Username for the entry
    --folder: string@nu_complete_rbw_folders # Folder name to search in
    --ignorecase (-i) # Ignore case
]

const SHELLS: list<string> = [bash zsh fish powershell elvish nushell fig]
# Generate the completion script for the given shell
export extern "rbw gen-completions" [
    SHELL: string@$SHELLS
]

# Get or set configuration options
export extern "rbw config" []

# Show the values of all configuration settings
export extern "rbw config show" []
# Set a configuration setting
export extern "rbw config set" [
    KEY: string
    VALUE: string
]
# Reset a configuration option to its default
export extern "rbw config unset" [
    KEY: string
]

# Register this device with the Bitwarden server
export extern "rbw register" []
# Log in to the Bitwarden server
export extern "rbw login" []
# Unlock the local Bitwarden database
export extern "rbw unlock" []
# Check if the local Bitwarden database is unlocked
export extern "rbw unlocked" []
# Update the local copy of the Bitwarden database
export extern "rbw sync" []
# Lock the password database
export extern "rbw lock" []
# Remove the local copy of the password database
export extern "rbw purge" []
# Terminate the background agent
export extern "rbw stop-agent" []
