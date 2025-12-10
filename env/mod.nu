# Set environment variables and other options

# Set up the environment
export-env {
    overlay use ./command_not_found.nu
    overlay use ./logs.nu
}

# Also set up the commands for cnf
export use ./command_not_found.nu *
