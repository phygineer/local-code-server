# Sandboxed AI Development Environment

A Docker-based development environment for running **code-server**, **Claude Code CLI**, and local AI tooling while keeping the AI agent isolated from the host machine.

The main idea is simple:

> Give the AI agent access to the project directory it needs, rather than giving it access to the entire host machine.

The development environment runs inside Docker, while Ollama can run natively on the Mac and provide local models to tools inside the container.

---

## Architecture

```text
                         macOS Host
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│   Browser                                                    │
│      │                                                       │
│      │ localhost:9999                                        │
│      ▼                                                       │
│   ┌──────────────────────────────────────────────┐           │
│   │ Docker: code-server                         │           │
│   │                                              │           │
│   │  VS Code / code-server                      │           │
│   │  Claude Code CLI                            │           │
│   │  Ollama CLI                                 │           │
│   │  Git                                        │           │
│   │  Node.js                                    │           │
│   │  Python                                     │           │
│   │  Go                                         │           │
│   │  Terraform                                  │           │
│   │  kubectl                                    │           │
│   │                                              │           │
│   │  /workspace  ───────────────┐               │           │
│   └─────────────────────────────│────────────────┘           │
│                                 │                            │
│                          bind-mounted                        │
│                                 │                            │
│                                 ▼                            │
│                         ../System                            │
│                                                              │
│                                                              │
│   Ollama                                                     │
│   localhost:11434                                            │
│       ▲                                                      │
│       │                                                      │
│       │ host.docker.internal:11434                           │
│       │                                                      │
│   code-server container                                      │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

# Why This Exists

AI coding agents such as Claude Code can execute shell commands, modify files, install dependencies, run tests, and perform many other development operations.

Running such an agent directly on the host means it potentially operates in an environment containing:

```text
~/Documents
~/Downloads
~/.ssh
~/.aws
~/.kube
~/Desktop
other repositories
local configuration
host applications
```

Instead, Claude Code is executed **inside a Docker container**.

The container receives access only to the directories and services intentionally exposed to it.

---

# Isolation Model

The Docker container itself acts as the development sandbox.

There is no separate "sandbox container."

```text
Host
 │
 │ Docker boundary
 ▼
┌───────────────────────────┐
│ code-server container     │
│                           │
│ Claude Code               │
│ Ollama CLI                │
│ compilers                 │
│ shell                     │
│ development tools         │
│                           │
│ /workspace                │
└────────────┬──────────────┘
             │
             │ explicit bind mount
             ▼
        Host project
```

Claude Code executes commands **inside the container**, not directly on macOS.

For example:

```bash
rm -rf /tmp/*
```

affects the container.

Similarly:

```bash
apt install ...
npm install ...
pip install ...
```

runs inside the Linux container.

The host operating system is not directly modified by these commands.

---

# Important: Mounted Directories Are NOT Isolated

Docker isolation does **not** protect writable bind mounts from processes inside the container.

For example:

```yaml
volumes:
  - ../System:/workspace
```

means:

```text
Container /workspace
        │
        ▼
Host ../System
```

Claude can therefore:

* read files in the project
* create files
* modify files
* delete files
* rename files

This is intentional because Claude needs access to the source code.

For example:

```bash
rm -rf /workspace/*
```

would delete files from the **host project directory**.

The sandbox protects the rest of the host, not the mounted project itself.

Git should therefore be used as an additional recovery mechanism.

---

# What Claude Cannot Normally Access

Unless explicitly mounted or otherwise exposed, the container cannot directly access host paths such as:

```text
~/Documents
~/Downloads
~/Desktop
~/.ssh
~/.aws
~/.kube
/etc
/
```

Do **not** mount these directories unless they are genuinely required.

In particular, avoid mounts such as:

```yaml
- ~/:/host-home
```

or:

```yaml
- /:/host
```

Doing so would significantly weaken the isolation boundary.

---

# Do Not Mount the Docker Socket

Avoid:

```yaml
- /var/run/docker.sock:/var/run/docker.sock
```

unless it is absolutely necessary.

Giving a container access to the host Docker daemon can effectively give processes inside that container control over the host's Docker environment and can undermine the intended sandbox.

For this environment, the Docker socket should remain unavailable.

---

# Components

## code-server

code-server provides VS Code through a browser.

The UI is exposed on:

```text
http://localhost:9999
```

Authentication is enabled using:

```yaml
command:
  - --bind-addr
  - 0.0.0.0:8080
  - --auth
  - password
```

with:

```yaml
environment:
  PASSWORD: changeme
```

Change this password before exposing code-server beyond localhost.

---

# Claude Code CLI

Claude Code is installed inside the container.

Example:

```bash
claude
```

Because Claude executes inside Docker, commands initiated by Claude execute in the container's Linux environment.

Start Claude from the project directory:

```bash
cd /workspace
claude
```

This naturally scopes the coding session to the mounted repository.

Claude authentication/configuration can be stored under `/home/coder`.

---

# Ollama

Ollama itself runs **natively on the Mac**, rather than inside this Docker container.

The container contains the Ollama CLI, but it does not run:

```bash
ollama serve
```

Instead, the CLI connects to Ollama running on macOS.

Docker Desktop exposes the host through:

```text
host.docker.internal
```

Therefore Compose configures:

```yaml
environment:
  OLLAMA_HOST: http://host.docker.internal:11434
```

The resulting connection is:

```text
Ollama CLI
inside container
      │
      │ HTTP
      ▼
host.docker.internal:11434
      │
      ▼
Ollama
running on macOS
```

---

# Testing Ollama Connectivity

Inside the code-server terminal:

```bash
echo $OLLAMA_HOST
```

Expected:

```text
http://host.docker.internal:11434
```

Test the API directly:

```bash
curl http://host.docker.internal:11434/api/tags
```

Or use the Ollama CLI:

```bash
ollama list
```

The models displayed are the models installed by Ollama on the Mac.

Running:

```bash
ollama run <model>
```

uses the model running through the host Ollama server.

The model itself does not need to be copied into the code-server container.

---

# Local Model Isolation

There are two separate pieces involved:

```text
AI client / agent
        │
        │ HTTP
        ▼
Ollama inference server
```

The model running through Ollama does not automatically receive access to the host filesystem.

It receives the information sent to it by the client.

For example:

```text
Claude/local agent
      │
      │ reads /workspace/file.py
      │
      │ sends relevant content
      ▼
Ollama
      │
      ▼
Local model
```

The important security boundary is therefore the **agent/tooling layer**, not merely the model.

A plain LLM cannot independently browse the filesystem.

An agent can, because tools may give it capabilities such as:

```text
read_file
write_file
shell
git
grep
python
npm
```

Running those tools inside Docker limits their filesystem and operating-system access to the container and its explicitly mounted resources.

---

# Why Ollama Can Run Outside the Sandbox

Ollama is primarily being used as an inference server.

The container sends requests such as:

```text
POST /api/chat
POST /api/generate
```

to:

```text
host.docker.internal:11434
```

Ollama returns model output.

The dangerous capabilities are generally the **tools around the model**:

```text
LLM
 ↓
Agent
 ↓
Shell / Files / Git / Tools
```

Those tools remain inside the Docker container.

Therefore it is reasonable to run Ollama natively while keeping the AI coding agent itself containerized.

---

# Persistent Home Directory

code-server stores configuration, extensions, caches, authentication information, and user-installed tooling under:

```text
/home/coder
```

A named Docker volume can preserve this data:

```yaml
volumes:
  - system_codeserver_data:/home/coder
```

This means rebuilding the image does not necessarily remove the developer environment's persistent user state.

---

# Workspace

The host repository is mounted as:

```yaml
volumes:
  - ../System:/workspace
```

and the container uses:

```yaml
working_dir: /workspace
```

Therefore terminals normally start inside the repository.

Example:

```bash
pwd
```

should return:

```text
/workspace
```

---

# Development Tools

The image includes:

```text
code-server
Claude Code CLI
Ollama CLI
Git
OpenSSH client
Node.js 20
npm
Python 3
pip
venv
Go
Terraform
kubectl
curl
wget
jq
ripgrep
vim
nano
tree
htop
build-essential
```

This allows Claude Code to build, test, inspect, and modify most projects without requiring access to host development tools.

---

# Passwordless sudo

The `coder` user is configured with:

```text
coder ALL=(ALL) NOPASSWD:ALL
```

This means Claude or the developer can execute:

```bash
sudo apt-get install ...
```

inside the container.

This gives processes effectively root-level control **inside the container**.

It does not normally provide root access to macOS.

However, root inside a container should still be treated as powerful, especially if additional host resources are mounted later.

---

# Security Boundary

The intended security boundary is:

```text
                 TRUSTED / HOST
┌──────────────────────────────────────────┐
│ macOS                                    │
│                                          │
│ Personal files                           │
│ SSH credentials                          │
│ Other repositories                       │
│ Docker Desktop                           │
│                                          │
│             ┌────────────────────┐       │
│             │ AI sandbox         │       │
│             │                    │       │
│             │ code-server        │       │
│             │ Claude Code        │       │
│             │ shell              │       │
│             │ dev tools          │       │
│             │                    │       │
│             │ /workspace ────────┼───────┼── allowed project
│             └────────────────────┘       │
│                                          │
│ Ollama :11434 ◄──── HTTP ────────────────┤
│                                          │
└──────────────────────────────────────────┘
```

Only explicitly exposed resources should cross this boundary.

---

# What This Protects Against

This setup reduces the impact of accidental or undesirable agent commands.

For example, if Claude runs:

```bash
sudo apt remove ...
```

the container is affected rather than macOS.

If Claude installs hundreds of packages:

```bash
npm install ...
pip install ...
apt install ...
```

they remain inside the container environment unless they write into a mounted directory.

If the environment becomes corrupted, it can simply be rebuilt:

```bash
docker compose down

docker compose build --no-cache

docker compose up -d
```

The host development environment remains largely untouched.

---

# What This Does NOT Protect Against

This setup is isolation, but it is **not a perfect security boundary**.

Claude can still:

1. Modify or delete files in writable mounted directories.
2. Access network services reachable from the container.
3. Send data to external APIs if outbound Internet access is allowed.
4. Access credentials deliberately placed inside the container.
5. Modify persistent `/home/coder` data.
6. Execute arbitrary commands as `coder`, and effectively as root because passwordless sudo is enabled.

For stronger isolation, additional controls can be introduced later, including:

```text
read-only root filesystem
dropped Linux capabilities
no-new-privileges
resource limits
network restrictions
separate secrets
non-root execution without sudo
temporary filesystems
dedicated per-project containers
```

The current design prioritizes a practical development environment while still providing a meaningful boundary between AI coding tools and the Mac host.

---

# Recommended Docker Compose

```yaml
services:

  codeserver:
    build: .
    pull_policy: never
    container_name: codeserver

    restart: unless-stopped

    command:
      - --bind-addr
      - 0.0.0.0:8080
      - --auth
      - password

    environment:
      PASSWORD: changeme
      OLLAMA_HOST: http://host.docker.internal:11434

    ports:
      - "9999:8080"

    volumes:
      - system_codeserver_data:/home/coder
      - ../System:/workspace

    working_dir: /workspace

    networks:
      - system

volumes:
  system_codeserver_data:

networks:
  system:
```

---

# Starting the Environment

Build:

```bash
docker compose build codeserver
```

Start:

```bash
docker compose up -d codeserver
```

Open:

```text
http://localhost:9999
```

Log in using the configured code-server password.

---

# Verify the Environment

Open a terminal inside code-server.

Check Claude:

```bash
claude --version
```

Check Ollama:

```bash
ollama --version
```

Check the configured Ollama server:

```bash
echo $OLLAMA_HOST
```

Check connectivity:

```bash
ollama list
```

Check the workspace:

```bash
pwd
git status
```

Expected working directory:

```text
/workspace
```

---

# Running Claude Code

From the code-server terminal:

```bash
cd /workspace
claude
```

Claude can now inspect and modify the repository and execute development commands inside the Docker environment.

The intended model is:

```text
                 Claude / AI Agent
                        │
                        ▼
               code-server container
                        │
            ┌───────────┴───────────┐
            ▼                       ▼
       /workspace                 Network
            │                       │
            ▼                       ▼
    explicitly mounted       Ollama / APIs
        repository

                 ✕
                 │
          rest of macOS
```

The core principle is:

> **Give the AI access to the workspace and tools it needs, while keeping everything else outside its execution environment.**

---

# Security Checklist

Before allowing an AI coding agent to execute commands automatically:

* Keep host mounts limited to the required repository.
* Do not mount `/`.
* Do not mount the entire macOS home directory.
* Do not mount `~/.ssh` unless absolutely necessary.
* Do not mount cloud credentials unnecessarily.
* Do not expose the Docker socket.
* Keep important project changes committed to Git.
* Do not place unnecessary secrets inside `/workspace`.
* Keep code-server bound to trusted interfaces or protect it with proper authentication.
* Treat `/workspace` as writable and therefore accessible to the agent.
* Remember that network access is a separate capability from filesystem isolation.

This gives a practical **AI development sandbox** without requiring a separate VM or a dedicated sandbox container.
