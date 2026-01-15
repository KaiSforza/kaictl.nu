# Kaictl Nu Modules

Just a few modules that I want to have available for improvements to Nushell and
other commands.

Also includes a bunch of environment stuff that could be put into an autoload,
but is separate and can be used with `overlay use ./kaictl.nu/env`.

If there are any commands or improvements that can be added here, please open an issue!

## Why?

Originally this was just a repo for me to consume as a non-flake input for my
nix configuration, but it has grown quite a bit. Nu is a very nice shell, but it
gets so much nicer when the commands are able to output native nu types. This
was the main factor for `ww`, since I wanted to see load avg as ints, lists of
sessions and not just a simple string output from `w`. `ww` focuses almost
entirely on Linux and systemd, using the `cgroupfs` to get proper information
about the processes of each session.

`l` was created because the order of the columns in nushell's `ls` doesn't
really map onto the output of coreutils `ls`.

My other goal was speed. Some of the commands in nix take quite a while,
especially when they have to go and load a whole flake (and its dependencies)
before giving a proper answer. The default `command_not_found` was really slow,
and even the one recommended by `nix-index` took about 2 seconds on my terrible
hardware. With some tweaks I was able to get that down to a reasonable time
(smaller db, only executables), but even then I was parsing the strings every
time and I wanted to avoid that. `nix create-index` creates a 'native' sqlite
database that can be queried almost instantly by the `nix locate` command,
allowing for easy and fast lookups, with that command, as well as the ability to
use the sqlite file outside these specific nushell commands. I did the same for
`pacman`, and intend to add more package managers in the future.

## `base`

Contains the commands and other things that users will probably want, without
modifying the environment.

After importing, check `help modules` for more details and a more complete list
of commands.

### Commands

- `help` - replacement help command with _much_ better output for modules.

Some of the coreutils commands have been "replaced" without overwriting the
original commands:

- `l` - replacement for `ls` that more closely mimics the coreutils output.
- `retry` - `^watch` for nushell data.
- `sys df` - a better `sys disks` output
- `sys n` - A better `sys net` output
- `witch` - `^which`, returns a list of paths to more closely mimic other
  shell's `which` commands.
- `ww` - `uptime`/`w` but with nushell data (and better, more informative
  output)

There are also some nix-specific commands:

- `nix nh` - a light wrapper for [`nom`][nom] and [`nh`][nh]
- `nix s` - quick local search in flakes. Uses the `n` flake, which can be a
  user-set alias to `nixpkgs` or any other flake reference.
- `nix s regen` - regenerate the index for `nix s`

1Password CLI improvements:

- `op` - A replacement for the `^op` command that properly caches authentication
  without the desktop application.

Cgroup and proc parsing commands, these are mostly used internally for the `ww`
command:

- `proc cgroup` - Get the cgroup of a process or list of processes.
- `cgroup cpu`, `cgroup io`, `cgroup mem` - Show info from the `($name).stat`
  file for that cgroup, with some conversions for better nushell usage
- `cgroup parse` - parses files in a cgroup into a table.

## `env`

Adds a few environment variables and some helpful commands for those environment
variables. Most of the commands are there for the `command_not_found` work, with
support for both `nix` and `pacman` for now.

### Commands

- `cmd locate` - internal function to look up packages that provide a command in
  a specific database.
- `nix create-index` - creates the local nix package sqlite database for near
  instant searches, requires [`nix-index`][nix-index].
- `nix locate` - find a specific package in the `nix` database created.
- `pacman create-index` - creates the local pacman sqlite database for near
  instant searches.
- `pacman locate` - find a specific package in the `pacman` database created.
- `provided-by` - used by `command_not_found` to return a list of commands that
  can be run to install the packages that provide a binary.

[nom]: https://code.maralorn.de/maralorn/nix-output-monitor
[nh]: https://github.com/nix-community/nh
[nix-index]: https://github.com/nix-community/nix-index

## WIP

### Docker replacement `pd`

Outputs docker/podman output as nushell objects for easy searching and much,
much better completion. Attempts to not use the Docker or Podman CLI at all,
instead fully relying on the new `http ... --unix-socket ...` nushell command
argument, removing the need for any other commands to be installed. Currently
only does `pd ps` and `pd image ls`, other commands are just wrapped from
`docker ...` or `podman ...`.
