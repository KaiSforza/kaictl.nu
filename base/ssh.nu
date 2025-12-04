# SSH wrapper
export def main [
    --sshopts (-o): list<string> # Options to pass to ssh
    host: string # Host to connect to
    cmd?: list<string> = [-t nu] # commands to run on the host
] {
    ^ssh $host ...$sshopts ...$cmd
}
