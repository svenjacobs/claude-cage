# claude-cage

Run [Claude Code](https://claude.ai/code) in an isolated [Podman](https://podman.io/) sandbox.

`claude-cage` builds a container image tailored for **Node.js and Android development** and launches it with your current working directory mounted at `/workspace`. The image comes with Claude Code and the Android SDK pre-installed. Claude Code's configuration and history are stored in a named Podman volume so they persist across runs without touching your host home directory.

## Features

- **Isolation** — Claude Code runs inside a container; it cannot reach your host filesystem beyond the directory you explicitly mount.
- **Named volumes** — Use `--volume <suffix>` to maintain multiple independent Claude Code instances, each with their own configuration and history.
- **Git identity & signing** — Your host `~/.gitconfig` and `~/.gnupg` are mounted automatically (when present) so commits made inside the container use your real identity and can be GPG-signed. Use `--no-git` to keep the container fully isolated.
- **Auto-build** — The container image is built automatically on first use and can be rebuilt at any time with `--rebuild`.
- **Node.js & Android ready** — The image is purpose-built for Node.js and Android development, with the Android SDK (platform tools, build tools, and an emulator-ready platform) pre-installed alongside a JDK.
- **Full Claude Code CLI** — All arguments are forwarded verbatim to the `claude` command inside the container.

## Requirements

- [Podman](https://podman.io/) (rootless mode recommended)

## Installation

Clone the repository and add the `bin` directory to your shell's `PATH`:

```sh
git clone https://github.com/svenjacobs/claude-cage
```

Then add the following line to your shell's configuration file (e.g. `~/.bashrc`, `~/.zshrc`, or `~/.config/fish/config.fish`):

```sh
# bash / zsh
export PATH="/path/to/claude-cage/bin:$PATH"
```

```fish
# fish
fish_add_path /path/to/claude-cage/bin
```

Replace `/path/to/claude-cage` with the actual path where you cloned the repository.

After reloading your shell (or opening a new terminal), the `claude-cage` command will be available.

## Usage

```
claude-cage [OPTIONS] [CLAUDE_ARGS...]
```

Run from any project directory — it is mounted at `/workspace` inside the container.

### Options

| Option | Description |
|---|---|
| `--volume[=SUFFIX]` | Use a named home volume with the given suffix. The volume is named `claude-cage-home[-SUFFIX]` and holds `~/.claude`, `~/.claude.json`, and shell history. A new volume is created automatically on first use. |
| `--no-git` | Do not mount the host's `~/.gitconfig` and `~/.gnupg`, even when they exist. Keeps the container fully isolated. |
| `--rebuild` | Force a rebuild of the container image before running. |
| `-h`, `--help` | Show help and exit. |

### Examples

```sh
# Run Claude Code in the current directory (default volume)
claude-cage

# Use a separate volume named "claude-cage-home-work"
claude-cage --volume work

# Force a rebuild of the image, then run
claude-cage --rebuild

# Pass arguments to the claude command
claude-cage --volume personal "explain this codebase"
```

## Committing and signing

When the host has a `~/.gitconfig` and/or `~/.gnupg` directory, `claude-cage`
exposes them to the container automatically, so commits made inside the container
carry your real name and email and can be GPG-signed. `~/.gitconfig` is mounted
read-only. `~/.gnupg` is mounted read-only at a staging path, and on startup the
container copies it into a working GPG home on the persistent volume. Pass
`--no-git` to disable both and keep the container isolated.

The copy step exists because Podman typically runs inside a VM, where your home
directory is shared over **virtiofs** — a filesystem that cannot host the
`gpg-agent` Unix socket. Running GPG directly against the mounted `~/.gnupg`
therefore fails with `gpg-agent ... Operation not supported` / `No agent
running`. The container sidesteps this by keeping the agent socket on the volume
while reading your keys from the mount; your secret keys are read live and are
**not** persisted into the volume.

A few things to be aware of:

- **Passphrase prompts.** A key with a passphrase triggers a `pinentry-tty`
  prompt (inline in your terminal) on the first signed commit of a session; the
  passphrase is then cached for the remainder of that container run. Keys without
  a passphrase sign with no prompt. `pinentry-tty` is used rather than a
  full-screen curses dialog so it doesn't clash with Claude's terminal UI.
- **Public keyring format.** The copy handles the classic `pubring.kbx` keyring.
  If you use the newer `keyboxd` database exclusively, additional keys may not be
  visible — open an issue if you hit this.
- **SELinux.** These dotfiles are intentionally mounted without an SELinux label
  (relabeling would break your host's own GPG). On enforcing hosts you may need
  to relax the relevant SELinux boolean if access is denied.

## Advanced usage

### Entering the container shell

While `claude-cage` is running, you can open an interactive Bash shell inside the container:

```sh
podman exec -it CONTAINER_NAME /bin/bash
```

Replace `CONTAINER_NAME` with the actual container name or ID (find it with `podman ps`).

### Installing skills

Install skills from inside the container shell, for example:

```sh
pnpx skills add -g JuliusBrussee/caveman
```

Because the home volume persists across runs, an installed skill is available in all future sessions that use the same volume.
