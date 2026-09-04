# Custom code-server image — browser-based VS Code + dev tooling + Claude Code CLI.
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

# ── Go ──────────────────────────────────────────────────────────────────────────
ARG GO_VERSION=1.23.4

RUN ARCH="$(dpkg --print-architecture)" \
    && case "$ARCH" in \
        amd64) GOARCH=amd64 ;; \
        arm64) GOARCH=arm64 ;; \
        *) GOARCH="$ARCH" ;; \
    esac \
    && curl -fsSL \
        "https://go.dev/dl/go${GO_VERSION}.linux-${GOARCH}.tar.gz" \
        -o /tmp/go.tgz \
    && tar -C /usr/local -xzf /tmp/go.tgz \
    && rm /tmp/go.tgz

# ── Terraform ───────────────────────────────────────────────────────────────────
ARG TF_VERSION=1.12.2

RUN ARCH="$(dpkg --print-architecture)" \
    && case "$ARCH" in \
        amd64) TFARCH=amd64 ;; \
        arm64) TFARCH=arm64 ;; \
        *) TFARCH="$ARCH" ;; \
    esac \
    && curl -fsSL \
        "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${TFARCH}.zip" \
        -o /tmp/tf.zip \
    && unzip -o /tmp/tf.zip -d /usr/local/bin terraform \
    && rm /tmp/tf.zip

# ── kubectl ─────────────────────────────────────────────────────────────────────
ARG KUBECTL_VERSION=v1.35.5

RUN ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" \
        -o /usr/local/bin/kubectl \
    && chmod 0755 /usr/local/bin/kubectl

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

# ── Ollama CLI ──────────────────────────────────────────────────────────────────
# Installs the Ollama binary.
# Do NOT run `ollama serve` in this container.
# The CLI will connect to Ollama running on the Mac host via OLLAMA_HOST.
RUN curl -fsSL https://ollama.com/install.sh | sh

# ── Runtime user ────────────────────────────────────────────────────────────────
USER coder

WORKDIR /workspace