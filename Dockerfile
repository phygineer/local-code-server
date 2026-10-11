# Custom code-server image — browser-based VS Code + dev tooling + AI coding CLIs.
# Ollama server runs on the Mac host; this image only installs the Ollama CLI.

FROM codercom/code-server:latest

ENV DEBIAN_FRONTEND=noninteractive

USER root

# ── Baseline tools ───────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    ca-certificates \
    gnupg \
    git \
    openssh-client \
    build-essential \
    pkg-config \
    python3 \
    python3-pip \
    python3-venv \
    jq \
    unzip \
    zip \
    tar \
    vim \
    nano \
    less \
    tree \
    htop \
    ripgrep \
    sudo \
    zstd \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 20 ──────────────────────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── User environment ────────────────────────────────────────────────────────────
ENV PATH="/usr/local/go/bin:/home/coder/go/bin:/home/coder/.local/bin:$PATH"

# Global npm installs go into /home/coder/.local
ENV NPM_CONFIG_PREFIX=/home/coder/.local

# code-server terminals may launch login shells, so make sure PATH is restored there too.
RUN printf '%s\n' \
    'export PATH="/usr/local/go/bin:$HOME/go/bin:$HOME/.local/bin:$PATH"' \
    'export NPM_CONFIG_PREFIX="$HOME/.local"' \
    > /etc/profile.d/devtools.sh \
    && chmod 0644 /etc/profile.d/devtools.sh

# ── Passwordless sudo ───────────────────────────────────────────────────────────
RUN echo "coder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/coder \
    && chmod 0440 /etc/sudoers.d/coder

# ── Claude Code CLI ─────────────────────────────────────────────────────────────
RUN npm install -g @anthropic-ai/claude-code

# ── Codex CLI ────────────────────────────────────────────────────────────────────
RUN npm install -g @openai/codex@latest

# ── Runtime user ────────────────────────────────────────────────────────────────
USER coder

WORKDIR /workspace
