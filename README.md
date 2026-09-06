# Local Code Server

A Docker-based development environment for running **code-server**, **Claude Code CLI**, and local AI tooling while keeping the AI agent isolated from most of the host machine.

The core idea is simple:

> Give the AI agent access only to the project directory you intentionally mount, instead of giving it access to your entire host filesystem.

This setup is designed for local development on macOS with:

* code-server running inside Docker
* Claude Code CLI running inside the code-server container
* Ollama running natively on the Mac
* Ollama CLI inside the container connecting back to the Mac host
* a configurable host project directory mounted as `/workspace`

---

## Architecture

```text
                         macOS Host
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│   Browser                                                    │
│      │                                                       │
│      │ http://localhost:9999                                 │
│      ▼                                                       │
│   ┌──────────────────────────────────────────────┐           │
│   │ Docker: code-server                         │           │
│   │                                              │           │
│   │  code-server / VS Code                      │           │
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
│                           bind mount                         │
│                                 │                            │
│                                 ▼                            │
│                         Host project                         │
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

AI coding agents such as Claude Code can execute shell commands, modify files, install dependencies, run tests, inspect repositories, and perform many other development operations.

Running such an agent directly on the host means it may operate in an environment containing:

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

Instead, Claude Code is executed inside a Docker container.

The container receives access only to the files, directories, and services that are deliberately exposed to it.

---

# Isolation Model

The code-server container itself acts as the development sandbox.

There is no separate sandbox container.

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
│ shell                     │
│ compilers                 │
│ development tools         │
│                           │
│ /workspace                │
└────────────┬──────────────┘
             │
             │ explicit bind mount
             ▼
        Host project
```

Claude Code executes commands inside the Linux container, not directly in macOS.

For example:

```bash
apt install ...
npm install ...
pip install ...
```

run inside the container.

Likewise:

```bash
rm -rf /tmp/*
```

affects the container filesystem.

The host operating system is not directly modified by those commands unless the affected path is a mounted host directory.

---

# Important: Mounted Directories Are Writable

Docker isolation does not protect writable bind mounts from processes inside the container.

The workspace is mounted using:

```yaml
- ${WORKSPACE_PATH}:/workspace
```

That means:

```text
Container /workspace
        │
        ▼
Host WORKSPACE_PATH
```

Claude Code can therefore:

* read project files
* modify project files
* create files
* delete files
* rename files

This is intentional because the coding agent needs access to the source code.

For example:

```bash
rm -rf /workspace/*
```

would delete files from the mounted host project directory.

Git should be used as an additional recovery mechanism.

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
/
```

Avoid broad mounts such as:

```yaml
- ~/:/host-home
```

or:

```yaml
- /:/host
```

because they significantly weaken the intended isolation boundary.

---

# Do Not Mount the Docker Socket

Avoid:

```yaml
- /var/run/docker.sock:/var/run/docker.sock
```

unless it is absolutely necessary.

Giving the container access to the host Docker daemon can effectively allow processes inside the container to control other containers and host-mounted resources.

For this environment, the Docker socket should remain unavailable.

---

# Configuration

Copy the example environment file:

```bash
cp .env.example .env
```

Then edit `.env`.

Example:

```dotenv
WORKSPACE_PATH=/Users/yourname/Projects/my-project
CODE_SERVER_PASSWORD=change-me
CODE_SERVER_PORT=9999
OLLAMA_HOST=http://host.docker.internal:11434
```

Do not commit `.env`.

---

# Workspace Configuration

`WORKSPACE_PATH` defines which host directory is exposed to the AI development environment.

Example:

```dotenv
WORKSPACE_PATH=/Users/yourname/Projects/my-project
```

Inside the container it appears as:

```text
/workspace
```

This is the most important filesystem security setting in the project.

Only mount the directory you actually want Claude Code to access.

Avoid:

```dotenv
WORKSPACE_PATH=/Users/yourname
```

Prefer:

```dotenv
WORKSPACE_PATH=/Users/yourname/Projects/specific-project
```

The Compose file requires this value explicitly.

If `WORKSPACE_PATH` is missing, Docker Compose fails instead of mounting an unexpected directory.

---

# code-server

code-server provides VS Code through a browser.

The default URL is:

```text
http://localhost:9999
```

Authentication is enabled using the password configured in `.env`:

```dotenv
CODE_SERVER_PASSWORD=change-me
```

Change this value before exposing code-server outside your local machine.

---

# Claude Code CLI

Claude Code runs inside the container.

Start it from the project directory:

```bash
cd /workspace
claude
```

Because Claude is running inside Docker, tools and shell commands executed by Claude run inside the container environment.

The primary writable host location exposed to it is `/workspace`.

---

# Ollama

Ollama runs natively on the host Mac.

The code-server container includes the Ollama CLI but does not run its own Ollama server.

Do not run:

```bash
ollama serve
```

inside the code-server container.

Instead, the CLI connects to the Mac host using:

```dotenv
OLLAMA_HOST=http://host.docker.internal:11434
```

Docker Desktop provides:

```text
host.docker.internal
```

as a hostname that containers can use to reach the host machine.

The connection is:

```text
Ollama CLI
inside container
      │
      │ HTTP
      ▼
host.docker.internal:11434
      │
      ▼
Ollama running on macOS
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

Test the API:

```bash
curl http://host.docker.internal:11434/api/tags
```

Or use the Ollama CLI:

```bash
ollama list
```

The models shown are the models installed on the host Mac.

You can also run:

```bash
ollama run <model>
```

The request goes to the host Ollama server.

The models are not copied into the code-server container.

---

# Local Model Isolation

There are two different layers involved:

```text
AI agent / client
       │
       ▼
Ollama inference server
```

A plain local model does not automatically gain filesystem access.

It only receives the data sent to it by the client.

The tool-capable agent is what can access:

```text
read_file
write_file
shell
git
grep
python
npm
```

Running those tools inside Docker limits their operating-system access to the container and explicitly mounted directories.

The important boundary is therefore the agent/tooling layer, not just the LLM itself.

---

# Why Ollama Can Run Outside the Container

Ollama is primarily acting as an inference server.

The code-server container sends HTTP requests to:

```text
host.docker.internal:11434
```

and receives model responses.

The potentially powerful capabilities remain inside the code-server container:

```text
LLM
 ↓
Agent
 ↓
Shell / Files / Git / Tools
```

This allows Ollama to run efficiently on the Mac while Claude Code and other AI tooling remain containerized.

---

# Persistent Home Directory

code-server stores configuration, extensions, caches, CLI state, and user-installed tools under:

```text
/home/coder
```

A named Docker volume preserves this directory:

```yaml
system_codeserver_data:/home/coder
```

This helps preserve:

* code-server settings
* extensions
* Claude CLI state
* npm-installed user tools
* shell configuration

across image rebuilds.

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

This allows most development work to happen inside the container rather than on the host.

---

# Passwordless sudo

The `coder` user has passwordless sudo inside the container.

That means this works:

```bash
sudo apt-get install ...
```

This gives processes effectively root-level control inside the container.

It does not normally provide root access to macOS.

However, root inside a container is still powerful if broad host mounts or sensitive sockets are exposed.

---

# Security Boundary

The intended boundary is:

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
│             │ /workspace ────────┼───────┼── explicitly mounted project
│             └────────────────────┘       │
│                                          │
│ Ollama :11434 ◄──── HTTP ────────────────┤
│                                          │
└──────────────────────────────────────────┘
```

Only explicitly exposed resources should cross this boundary.

---

# What This Protects Against

This setup reduces the impact of accidental or undesirable AI-agent commands.

For example, if Claude runs:

```bash
sudo apt remove ...
```

the container is affected rather than macOS.

If Claude installs packages:

```bash
npm install ...
pip install ...
apt install ...
```

they remain inside the container unless they write to mounted directories.

If the container becomes corrupted, rebuild it:

```bash
docker compose down
docker compose build --no-cache
docker compose up -d
```

The host development environment remains largely untouched.

---

# What This Does Not Protect Against

This setup is useful isolation, but it is not a perfect security boundary.

Claude can still:

1. modify or delete files under `/workspace`
2. access network services reachable from the container
3. send data to external APIs if outbound Internet access is available
4. access credentials deliberately placed inside the container
5. modify persistent `/home/coder` data
6. execute commands with sudo inside the container

For stronger isolation, additional controls can be introduced later, including:

```text
cap_drop
no-new-privileges
read-only root filesystem
resource limits
network restrictions
non-root execution without sudo
temporary filesystems
dedicated per-project containers
```

---

# Setup

Clone the repository:

```bash
git clone https://github.com/phygineer/local-code-server.git
cd local-code-server
```

Create the local configuration:

```bash
cp .env.example .env
```

Edit `.env`:

```bash
vim .env
```

Set at minimum:

```dotenv
WORKSPACE_PATH=/absolute/path/to/your/project
CODE_SERVER_PASSWORD=your-password
```

Start the environment:

```bash
docker compose up -d --build
```

Open:

```text
http://localhost:9999
```

---

# Verify the Environment

Inside the code-server terminal:

```bash
pwd
```

Expected:

```text
/workspace
```

Check Claude:

```bash
claude --version
```

Check Ollama:

```bash
ollama --version
```

Check the host Ollama connection:

```bash
ollama list
```

Check Git:

```bash
git status
```

---

# Running Claude Code

From the code-server terminal:

```bash
cd /workspace
claude
```

Claude can now inspect and modify the mounted repository and execute development commands inside the Docker environment.

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

> Give the AI access to the workspace and tools it needs, while keeping everything else outside its execution environment.

---

# Recommended Security Checklist

* Keep `WORKSPACE_PATH` limited to the required repository.
* Do not mount `/`.
* Do not mount your whole home directory.
* Do not mount `~/.ssh` unless necessary.
* Do not mount cloud credentials unnecessarily.
* Do not mount `/var/run/docker.sock`.
* Keep important changes committed to Git.
* Do not store unnecessary secrets under `/workspace`.
* Change the default code-server password.
* Remember that `/workspace` is writable by the agent.
* Treat network access as a separate capability from filesystem isolation.
