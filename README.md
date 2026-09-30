# mgy (multigravity-cli)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-brightgreen.svg)]()
[![Shell](https://img.shields.io/badge/Shell-bash%20%7C%20zsh-orange.svg)]()

> Lightweight multi-account profile, session, and quota manager for the **Google Antigravity CLI (`agy`)**.

`mgy` (short for `multigravity`) enables developers to maintain multiple isolated Antigravity accounts (e.g., personal, work, client, or shared team accounts) on a single machine. Just as `agy` is the CLI for Antigravity, `mgy` is your tool for managing multi-gravity profiles.

It isolates Google OAuth credentials and quotas per profile, while keeping your conversation history, agent memories, MCP servers, and global configurations unified across all profiles.

---

## 🎯 Why mgy?

By default, the Antigravity CLI (`agy`) binds your credentials and your conversation history together in a single global directory: `~/.gemini/antigravity-cli`.

This creates several challenges for power users:
- **Quota Exhaustion**: When your five-hour or weekly quota on one account runs low, you cannot switch accounts without losing active session context or overwriting tokens.
- **Account Switching Overhead**: Switching between personal and work Google accounts requires constantly re-authenticating.
- **Unified History Requirement**: When you switch accounts, you still want full access to your previous conversations (`agy -c`), chat history, prompt history, and MCP tools.
- **Side-by-Side Sessions**: You cannot run two `agy` instances logged into different accounts simultaneously.

`mgy` solves this by **sharing the global configuration and conversation history** across all profiles while **strictly isolating the authentication tokens and quotas**.

---

## 🏗️ How It Works

`mgy` solves the multi-account challenge with a unified-history, isolated-token architecture:

**All profiles share your global conversations, history, settings, and MCP tools**, while each profile maintains its **own independent Google OAuth token and quota**.

When launching a session with `mgy <profile>`, the environment redirects `HOME` to `~/.config/multigravity-profiles/<profile>/`:

```
~/.config/multigravity-profiles/
├── perso/
│   ├── .gemini/
│   │   └── antigravity-cli/         # Symlink -> host ~/.gemini/antigravity-cli (SHARED)
│   ├── .gitconfig                   # Symlink -> host ~/.gitconfig
│   ├── .ssh                         # Symlink -> host ~/.ssh
│   └── Library/Keychains/           # Symlink -> host Keychain (Personal OAuth token)
└── work/
    ├── .gemini/
    │   └── antigravity-cli/         # Symlink -> host ~/.gemini/antigravity-cli (SHARED)
    ├── .gitconfig                   # Symlink -> host ~/.gitconfig
    ├── .ssh                         # Symlink -> host ~/.ssh
    └── Library/Keychains/           # Isolated Keychain (Work OAuth token)
```

> [!NOTE]
> - **Unified History & Memory**: Because `.gemini/antigravity-cli` is shared across all profiles, all your conversations, chat summaries, CLI settings, prompt history (`history.jsonl`), and MCP servers are always preserved. You can resume any conversation across different accounts seamlessly (`mgy work -c`).
> - **Isolated Credentials & Quota**: Each non-default profile maintains its own isolated OAuth token. When you switch to `work`, you draw from your work account's quota limits without affecting your personal account or losing any context.
> - **Preserved Identity**: Host `.gitconfig` and `.ssh` are symlinked across all profiles, ensuring git commits always retain your author name and email.

---

## 🚀 Quick Start

### 1. Installation

#### Option A: Clone & Install (Recommended)
```bash
git clone https://github.com/your-username/multigravity-cli.git
cd multigravity-cli
./install.sh
```
*The installer automatically links your global config to `perso` and prepares the `work` workspace!*

#### Option B: Standalone One-Liner
```bash
mkdir -p ~/.local/bin ~/.config/multigravity-profiles
curl -fsSL https://raw.githubusercontent.com/your-username/multigravity-cli/master/bin/mgy -o ~/.local/bin/mgy
chmod +x ~/.local/bin/mgy
ln -sf mgy ~/.local/bin/multigravity
```

#### Option C: Via NPM
```bash
cd multigravity-cli
npm link
```

Ensure `~/.local/bin` is in your `$PATH`:
```bash
export PATH="$HOME/.local/bin:$PATH"
```
*(Add the above line to your `~/.zshrc` or `~/.bashrc` to make it permanent).*

Both `mgy` and `multigravity` commands are available in your shell!

---

### 2. Available Profiles & Setup

#### Check Registered Profiles
```bash
mgy list
```
Output:
```text
Available profiles:
perso
work
```

- **`perso` is already ready**: It links directly to your global host configuration (`~/.gemini/antigravity-cli`).
- **`work` (or new profile)**: To authenticate your work or secondary account, run:
  ```bash
  mgy new work
  ```
  Follow the OAuth prompt in your browser. Once completed, `work` is ready with its own isolated token!

---

### 3. Running Side-by-Side Sessions

Launch interactive sessions under separate profiles in separate terminal tabs, windows, or tmux panes:

* **Pane 1 (Personal Account - Global Config):**
  ```bash
  mgy perso
  ```

* **Pane 2 (Work Account - Isolated):**
  ```bash
  mgy work
  ```

Both instances execute simultaneously with full token, cache, and history isolation.

#### Resuming Conversations Across Profiles
Because conversations and history are shared globally, you can resume any conversation under any account:

```bash
# View recent conversation IDs:
mgy conversations

# Resume a specific conversation by ID in perso:
mgy perso --conversation=c4e2acbb-a968-4591-aa3c-a09cf0bf9e22

# Resume that SAME conversation under work to use your work quota:
mgy work --conversation=c4e2acbb-a968-4591-aa3c-a09cf0bf9e22

# Continue the most recent conversation:
mgy perso -c
mgy work --continue
```

#### Passing Other Flags and Arguments
Any additional CLI arguments are forwarded directly to `agy`:
```bash
mgy perso --model gemini-2.5-flash
mgy work -p "Explain distributed locks in Go"
```

---

### 4. Checking Quotas Across All Accounts

Inspect model quota limits (Gemini, Claude, GPT) across all configured profiles with a single command:

```bash
mgy quotas
```

**Example output:**
```text
=== Quota for profile: perso ===
Quota:
Gemini Models          Weekly Limit Remaining     50%   2026-10-06T13:07:58Z
Gemini Models          Five Hour Limit Remaining  1%    2026-10-01T00:48:28Z
Claude and GPT models  Weekly Limit Remaining     66%   2026-10-07T00:32:37Z
Claude and GPT models  Five Hour Limit Remaining  100%  2026-10-01T03:08:15Z

=== Quota for profile: work ===
Profile 'work' is not authenticated yet. Run: mgy new work
```

---

## 📖 Command Reference

Both `mgy` and `multigravity` can be used interchangeably:

| Command | Description |
| :--- | :--- |
| `mgy <profile> --conversation=<id>` | Resumes a specific conversation by ID (same as `agy --conversation=<id>`). |
| `mgy <profile> -c`, `--continue` | Continues the most recent conversation. |
| `mgy conversations` | Lists recent conversation IDs, titles, and activity timestamps. |
| `mgy new <profile>` | Creates a profile directory and executes the initial OAuth authentication flow. |
| `mgy import [profile]` | Links or imports the host's existing `~/.gemini/antigravity-cli` global configuration into the named profile (default: `perso`). |
| `mgy list` | Lists all available configured profiles. |
| `mgy quotas` | Iterates across all profiles and outputs active model quotas. |
| `mgy delete <profile>` | Prompts for confirmation and deletes the profile directory. |
| `mgy <profile> [args...]` | Starts `agy` with the chosen profile, forwarding any arguments. |
| `mgy help`, `--help`, `-h` | Displays the help and usage menu. |

---

## ⚙️ Configuration & Environment Variables

| Variable | Default | Purpose |
| :--- | :--- | :--- |
| `MULTIGRAVITY_PROFILES_DIR` | `~/.config/multigravity-profiles` | Base directory where all isolated profile workspaces are stored. |
| `REAL_HOME` | `$HOME` | Host home directory used for resolving global `.gitconfig` and `.ssh` links. |

You can override the profiles storage directory by exporting `MULTIGRAVITY_PROFILES_DIR`:
```bash
export MULTIGRAVITY_PROFILES_DIR="$HOME/my-profiles"
```

---

## 🧹 Uninstallation

To remove `mgy` and `multigravity` from your system:

```bash
./uninstall.sh
```

To also clean up all stored profile data and credentials:
```bash
rm -rf ~/.config/multigravity-profiles
```

---

## 📄 License

[MIT](LICENSE)
