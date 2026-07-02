# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`claude-cage` is a small project: a `Dockerfile` that builds the sandbox image, a POSIX shell script `bin/claude-cage` that manages the Podman container lifecycle from the host, and a container entrypoint `bin/cage-entrypoint` that prepares GPG before launching Claude Code. There are no build systems, package managers, or test suites.

## Architecture

### `Dockerfile`

Builds the `claude-cage` image on top of `node:26-trixie-slim`. Key layers in order:

1. **System tools** — `git`, `curl`, `ripgrep`, `fd-find`, `jq`, `fish`, etc.
2. **JDK** — `openjdk-25-jdk-headless`, with `JAVA_HOME` pointing to a stable arch-independent symlink `/usr/lib/jvm/default-java`.
3. **Claude Code** — installed globally via pnpm (Corepack-managed). `DISABLE_AUTOUPDATER=1` prevents the auto-updater from failing at runtime against a read-only pnpm store.
4. **Android SDK** — downloaded via `sdkmanager` into `ANDROID_HOME=/opt/android-sdk`. The `cmdline-tools` zip version and SHA-1 are pinned as build args (`CMDLINE_TOOLS_VERSION`, `CMDLINE_TOOLS_SHA1`) and must be updated together when upgrading. Similarly `ANDROID_PLATFORM` and `BUILD_TOOLS` are build args.
5. **Runtime user** — a non-root `dev` user owns `$ANDROID_HOME` so in-container `sdkmanager` calls work.

The `ENTRYPOINT` is `claude`, so all arguments passed to `podman run` are forwarded directly to Claude Code.

### `bin/claude-cage`

A POSIX `sh` script (no bashisms). It:

- Parses `--help`, `--rebuild`, `--no-git`, and `--volume[=SUFFIX]` flags from anywhere in the argument list, forwarding everything else to `claude` inside the container.
- Derives the build context from its own location (`dirname` of the script → parent = repo root), so it works regardless of where it is invoked from.
- Names the home volume `claude-cage-home` or `claude-cage-home-<suffix>`, mounting it at `/home/dev` to persist `~/.claude`, `~/.claude.json`, and shell history.
- Mounts `$PWD` at `/workspace:Z` (the `:Z` label is required for SELinux hosts).
- Exposes the host's `~/.gitconfig` (read-only, at its usual path) and `~/.gnupg` (read-only, at the staging path `/home/dev/.gnupg-host`) when they exist, so commits use the real git identity and GPG keys. `--no-git` skips both. These dotfile mounts deliberately omit the `:Z`/`:z` label to avoid relabeling — and breaking — the host's own files. The mount args are assembled with a space-safe `set --` prepend that keeps the image immediately before the forwarded `claude` args.
- Builds the image automatically on first use; `--rebuild` forces a rebuild.

### `bin/cage-entrypoint`

The image `ENTRYPOINT`. It prepares GPG and then `exec claude "$@"`, so all `podman run` arguments still reach Claude Code. The host `~/.gnupg` almost always arrives over **virtiofs** (Podman runs inside a VM), and virtiofs cannot host the `gpg-agent` Unix socket — so a `GNUPGHOME` placed directly on that mount fails to start the agent. To work around this, when `~/.gnupg-host` is present the entrypoint builds a real `GNUPGHOME` at `~/.gnupg` on the socket-capable home volume: it copies the public keyring and `trustdb.gpg` (small, non-secret, and writable so gpg can update trust) and symlinks `private-keys-v1.d` back to the read-only host mount (secret keys are read live, never persisted into the volume). It also writes a `gpg-agent.conf` pinning `pinentry-program` to `/usr/bin/pinentry-tty` (the host's own config may point at a GUI pinentry that isn't installed here; `pinentry-tty` prompts inline rather than drawing a full-screen curses dialog that would clash with Claude's terminal UI) and exports `GPG_TTY` so pinentry can prompt. A `.cage-managed` marker lets a later run without the keys mounted clean the directory back up.

Because the entrypoint only sets `GPG_TTY` for the `claude` process tree, the image *also* sets it from the shell startup files (`/etc/profile.d/gpg-tty.sh`, `/etc/bash.bashrc`, `/etc/fish/conf.d/gpg-tty.fish`) so that shells opened separately via `podman exec` can sign too. Without a terminal, pinentry fails with `Inappropriate ioctl for device`.

## Common tasks

### Build the image manually

```sh
podman build -t claude-cage .
```

### Force-rebuild via the script

```sh
claude-cage --rebuild
```

### Upgrade the Android command-line tools

1. Find the new version number and zip URL at <https://developer.android.com/studio#command-line-tools-only>.
2. Download the zip and compute its SHA-1: `sha1sum commandlinetools-linux-*.zip`.
3. Update `CMDLINE_TOOLS_VERSION` and `CMDLINE_TOOLS_SHA1` in the `Dockerfile`.
4. Rebuild the image.

### Change the Android platform or build-tools version

Update the `ANDROID_PLATFORM` and `BUILD_TOOLS` build args near the bottom of the `Dockerfile`, then rebuild.
