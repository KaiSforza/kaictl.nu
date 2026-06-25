# Module for working on and inspecting tailscale and tailscaled

# Run tailscale directly if we don't have things already set up
export def main --wrapped [...r] {
    ^tailscale ...$r
}

export def "status" [
    --active (-a) # Show only active nodes
    --ipv6 (-6) # Only show ipv6 addresses
    ...r
] {
    let state = main status --json | from json
    let users = $state.User
    let peers = $state.Peer
    let columns = [
        TailscaleIPs HostName UserID Active Online ExitNode LastSeen
    ]
    $peers
    | select 
}

export def "from userID" [users]: int -> string {
    let uid: int = $in
    $users
    | get ($uid | into string)
}
