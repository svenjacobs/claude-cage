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
    ca-certificates \
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

# Run as a non-root user; own the SDK so on-the-fly sdkmanager updates work
RUN useradd -m dev && chown -R dev:dev $ANDROID_HOME
USER dev
WORKDIR /workspace

# Claude Code's auto-updater tries to write to the global pnpm store, which is
# read-only inside the image. Disable it so it doesn't error or stall on start.
ENV DISABLE_AUTOUPDATER=1

ENTRYPOINT ["claude"]
