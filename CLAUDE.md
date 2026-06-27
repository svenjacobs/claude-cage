# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`claude-cage` is a two-file project: a `Dockerfile` that builds the sandbox image and a POSIX shell script `bin/claude-cage` that manages the Podman container lifecycle. There are no build systems, package managers, or test suites.

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

- Parses `--help`, `--rebuild`, and `--volume[=SUFFIX]` flags from anywhere in the argument list, forwarding everything else to `claude` inside the container.
- Derives the build context from its own location (`dirname` of the script → parent = repo root), so it works regardless of where it is invoked from.
- Names the home volume `claude-cage-home` or `claude-cage-home-<suffix>`, mounting it at `/home/dev` to persist `~/.claude`, `~/.claude.json`, and shell history.
- Mounts `$PWD` at `/workspace:Z` (the `:Z` label is required for SELinux hosts).
- Builds the image automatically on first use; `--rebuild` forces a rebuild.

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
