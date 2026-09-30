# mgy (multigravity-cli)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-brightgreen.svg)]()
[![Shell](https://img.shields.io/badge/Shell-bash%20%7C%20zsh-orange.svg)]()

> Lightweight multi-account profile, session, and quota manager for the **Google Antigravity CLI (`agy`)**.

`mgy` (short for `multigravity`) enables developers to maintain multiple isolated Antigravity accounts (e.g., personal, work, client, or shared team accounts) on a single machine. Just as `agy` is the CLI for Antigravity, `mgy` is your tool for managing multi-gravity profiles.

It seamlessly segregates OAuth credentials, session state, conversation memories, and token caches while preserving global Git configuration and SSH keys.

---

## 🎯 Why mgy?

By default, the Antigravity CLI (`agy`) stores all credentials, project metadata, SQLite databases, and conversation transcripts in a single directory: `~/.gemini/antigravity-cli`.

This creates several challenges for power users:
- **Account Switching Overhead**: Switching between Google accounts requires re-authenticating and overwriting existing tokens.
- **Quota Limitations**: When your five-hour or weekly quota on one account runs low, you cannot easily switch to another without disrupting your environment.
- **Session Bleed**: History, presence, and project cache are shared across all sessions.
- **Side-by-Side Incompatibility**: You cannot run two `agy` instances logged into different accounts simultaneously.

`mgy` solves this by introducing **environment-isolated profile spaces** without any heavy runtime dependencies or modifying the `agy` binary.

---

## 🏗️ How It Works

Each profile lives in its own sandbox directory under `~/.config/multigravity-profiles/<profile_name>/`. 

When launching a session, `mgy` redirects the user's home context for `agy`, ensuring complete token and conversation separation:

```
~/.config/multigravity-profiles/
├── perso/
│   ├── .gemini/antigravity-cli/     # Perso OAuth tokens, history, and DBs
│   ├── .gitconfig                   # Symlink -> host ~/.gitconfig
│   └── .ssh                         # Symlink -> host ~/.ssh
└── work/
    ├── .gemini/antigravity-cli/     # Work OAuth tokens, history, and DBs
    ├── .gitconfig                   # Symlink -> host ~/.gitconfig
    └── .ssh                         # Symlink -> host ~/.ssh
```

> [!NOTE]
> **Preserved Identity**: Symlinking your global `.gitconfig` and `.ssh` ensures all Git commits made by agents retain your correct Git name, email, and signing credentials.

---

## 🚀 Quick Start

### 1. Installation

#### Option A: Clone & Install (Recommended)
```bash
git clone https://github.com/your-username/multigravity-cli.git
cd multigravity-cli
./install.sh
```

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

Both `mgy` and `multigravity` commands will be available in your shell!

---

### 2. Setting Up Profiles

#### Create a New Account Profile
Run `mgy new <profile>` to launch the isolated browser OAuth flow:
```bash
# Personal profile
mgy new perso

# Work or secondary profile
mgy new work
```
Follow the OAuth prompt in your browser. Once authorized, the profile is configured and verified.

#### (Optional) Import Current Machine Session
If you are already logged in to `agy` on your machine and want to migrate that existing session directly into a profile without re-authenticating:
```bash
mgy import perso
```

#### Verify Registered Profiles
```bash
mgy list
```

---

### 3. Running Side-by-Side Sessions

Launch interactive sessions under separate profiles in separate terminal tabs, windows, or tmux panes:

* **Pane 1 (Personal Account):**
  ```bash
  mgy perso
  ```

* **Pane 2 (Work / Secondary Account):**
  ```bash
  mgy work
  ```

Both instances execute simultaneously with full token, cache, and history isolation.

#### Passing Flags and Arguments
Any additional CLI arguments are forwarded directly to `agy`:
```bash
mgy perso --model gemini-2.5-flash
mgy work -p "Explain distributed locks in Go"
mgy work --continue
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
Gemini Models          Weekly Limit Remaining     53%   2026-10-06T13:07:58Z
Gemini Models          Five Hour Limit Remaining  18%   2026-10-01T00:48:28Z
Claude and GPT models  Weekly Limit Remaining     66%   2026-10-07T00:32:37Z
Claude and GPT models  Five Hour Limit Remaining  100%  2026-10-01T02:50:32Z

=== Quota for profile: work ===
Quota:
Gemini Models          Weekly Limit Remaining     94%   2026-10-07T18:12:00Z
Gemini Models          Five Hour Limit Remaining  82%   2026-10-01T04:10:15Z
Claude and GPT models  Weekly Limit Remaining     100%  2026-10-07T18:12:00Z
Claude and GPT models  Five Hour Limit Remaining  100%  2026-10-01T04:10:15Z
```

---

## 📖 Command Reference

Both `mgy` and `multigravity` can be used interchangeably:

| Command | Description |
| :--- | :--- |
| `mgy new <profile>` | Creates a profile directory and executes the initial OAuth authentication flow. |
| `mgy import <profile>` | Clones the host's existing `~/.gemini/antigravity-cli` credentials into the named profile. |
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
