FROM node:26-trixie-slim

# Base tools Claude Code shells out to, plus a JDK and unzip for the Android SDK
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    unzip \
    ripgrep \
    fd-find \
    jq \
    less \
    file \
    vim \
    nano \
    ca-certificates \
    gnupg \
    pinentry-tty \
    fish \
    openjdk-25-jdk-headless \
 && rm -rf /var/lib/apt/lists/* \
 && ln -s "$(command -v fdfind)" /usr/local/bin/fd  # Debian names it "fdfind"

# Set JAVA_HOME via a stable, arch-independent symlink to avoid hardcoding the
# openjdk-<arch> path.
RUN ln -s /usr/lib/jvm/java-25-openjdk-$(dpkg --print-architecture) \
          /usr/lib/jvm/default-java
ENV JAVA_HOME=/usr/lib/jvm/default-java
ENV PATH="$JAVA_HOME/bin:$PATH"

# Enable Corepack (yarn/pnpm shims), then install Claude Code globally via pnpm.
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME/bin:$PATH"
# Corepack is no longer bundled with Node, so install it before enabling
RUN npm install -g corepack && corepack enable
# The pnpm store must live inside the image (not a BuildKit cache mount): global
# installs symlink node_modules into the store, so a cache-mounted store would be
# absent at runtime ("claude: not found"). Docker layer caching still skips this
# step on unrelated rebuilds. pnpm 10+ also blocks dependency build scripts by
# default, and claude-code's postinstall installs its platform-native binary, so
# it must be allowed explicitly.
RUN pnpm add -g --allow-build=@anthropic-ai/claude-code @anthropic-ai/claude-code

# --- Android SDK ---------------------------------------------------------
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=$ANDROID_HOME
ENV PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools

# Command-line tools. NOTE: the version number and SHA-1 must match the current
# release from https://developer.android.com/studio#command-line-tools-only —
# a stale number will 404 (there is no "latest" alias), and a mismatched SHA-1
# fails the integrity check below.
ARG CMDLINE_TOOLS_VERSION=14742923
ARG CMDLINE_TOOLS_SHA1=48833c34b761c10cb20bcd16582129395d121b27
RUN mkdir -p $ANDROID_HOME/cmdline-tools \
 && curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip" -o /tmp/cmd.zip \
 && echo "${CMDLINE_TOOLS_SHA1}  /tmp/cmd.zip" | sha1sum -c - \
 && unzip -q /tmp/cmd.zip -d $ANDROID_HOME/cmdline-tools \
 && mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest \
 && rm /tmp/cmd.zip

# SDK packages
ARG ANDROID_PLATFORM=android-37.0
ARG BUILD_TOOLS=37.0.0
RUN yes | sdkmanager --licenses >/dev/null \
 && sdkmanager --install "platform-tools" "platforms;${ANDROID_PLATFORM}" "build-tools;${BUILD_TOOLS}"
# ------------------------------------------------------------------------

# --- GitHub CLI ----------------------------------------------------------
RUN mkdir -p /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*
# -------------------------------------------------------------------------

# --- Google Cloud CLI ----------------------------------------------------
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
      | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
      > /etc/apt/sources.list.d/google-cloud-sdk.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends google-cloud-cli \
 && rm -rf /var/lib/apt/lists/*
# -------------------------------------------------------------------------

# GPG's pinentry needs to know which terminal to prompt on (via $GPG_TTY).
# Interactive shells opened separately (e.g. `podman exec ... bash`) don't run the
# entrypoint, so set it in the shell startup files: login/POSIX shells via
# profile.d, interactive Bash via bash.bashrc, and fish via conf.d. Without this,
# signing fails with "Inappropriate ioctl for device".
RUN printf '%s\n' '[ -t 0 ] && GPG_TTY=$(tty) && export GPG_TTY' \
      > /etc/profile.d/gpg-tty.sh \
 && printf '\n%s\n' '[ -t 0 ] && GPG_TTY=$(tty) && export GPG_TTY' \
      >> /etc/bash.bashrc \
 && mkdir -p /etc/fish/conf.d \
 && printf '%s\n' 'if isatty stdin' '    set -gx GPG_TTY (tty)' 'end' \
      > /etc/fish/conf.d/gpg-tty.fish

# Run as a non-root user; own the SDK so on-the-fly sdkmanager updates work
RUN useradd -m dev && chown -R dev:dev $ANDROID_HOME
USER dev
WORKDIR /workspace

# Claude Code's auto-updater tries to write to the global pnpm store, which is
# read-only inside the image. Disable it so it doesn't error or stall on start.
ENV DISABLE_AUTOUPDATER=1

# Entrypoint prepares GPG (see the script) then execs claude, forwarding all args.
# gpg-unlock lets the user cache the signing passphrase once per session.
COPY --chmod=755 bin/cage-entrypoint /usr/local/bin/cage-entrypoint
COPY --chmod=755 bin/gpg-unlock /usr/local/bin/gpg-unlock
ENTRYPOINT ["/usr/local/bin/cage-entrypoint"]
