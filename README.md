# multigravity-cli

> Multi-account profile, session, and quota manager for the **Google Antigravity CLI (`agy`)**.

`multigravity` allows you to manage multiple isolated Antigravity accounts (e.g., personal, work, friends, or team members) on a single machine. It seamlessly isolates authentication tokens, configurations, conversation summaries, and history without interfering with your shared Git identity or SSH keys.

---

## ✨ Features

- **Profile Isolation**: Each profile maintains its own completely isolated environment under `~/.config/multigravity-profiles/<profile>/`.
- **Parallel Sessions**: Run side-by-side terminal sessions under different accounts simultaneously.
- **Quota Aggregator**: Inspect model quota limits (Gemini, Claude, GPT) across all configured profiles with a single command (`multigravity quotas`).
- **Seamless Auth**: Triggers the Antigravity OAuth browser login flow per profile.
- **Git & SSH Preservation**: Automatically symlinks your host `~/.gitconfig` and `~/.ssh` to ensure git commits and remote operations work out of the box.
- **Zero Heavy Dependencies**: Pure, portable shell script compatible with macOS (`bash`/`zsh`) and Linux.

---

## 🚀 Quick Start

### 1. Installation

You can install `multigravity` directly into `~/.local/bin`:

```bash
# Clone the repository
git clone https://github.com/your-username/multigravity-cli.git
cd multigravity-cli

# Run installer
./install.sh
```

Or copy the script manually:

```bash
mkdir -p ~/.local/bin ~/.config/multigravity-profiles
cp bin/multigravity ~/.local/bin/multigravity
chmod +x ~/.local/bin/multigravity
```

Ensure `~/.local/bin` is in your `$PATH`:
```bash
export PATH="$HOME/.local/bin:$PATH"
```
*(Add this to your `~/.zshrc` or `~/.bashrc` to make it permanent.)*

---

### 2. Creating Profiles

Set up profiles for different Google accounts:

```bash
# Set up your primary profile:
multigravity new perso

# Set up a second account (e.g. friend or work):
multigravity new pote
```

For each command, follow the OAuth prompt displayed in the browser/terminal to complete the authentication.

Verify both profiles are registered:
```bash
multigravity list
```

---

### 3. Running Side-by-Side Sessions

Open multiple terminals or split panes (e.g., in iTerm2, VS Code, or tmux):

* **Terminal 1:**
  ```bash
  multigravity perso
  ```

* **Terminal 2:**
  ```bash
  multigravity pote
  ```

Both instances run independently with separate sessions, token refreshes, and history!

You can also pass any `agy` arguments or flags directly:
```bash
multigravity perso --model gemini-2.5-flash
multigravity pote -p "explain async in Rust"
```

---

### 4. Checking Quotas Across All Accounts

Inspect quota limits for all configured accounts in one shot:

```bash
multigravity quotas
```

Example output:
```text
=== Quota for profile: perso ===
Quota:
Gemini Models          Weekly Limit Remaining     53%   2026-10-06T13:07:58Z
Gemini Models          Five Hour Limit Remaining  18%   2026-10-01T00:48:28Z
Claude and GPT models  Weekly Limit Remaining     66%   2026-10-07T00:32:37Z
Claude and GPT models  Five Hour Limit Remaining  100%  2026-10-01T02:50:32Z

=== Quota for profile: pote ===
Quota:
Gemini Models          Weekly Limit Remaining     100%  2026-10-07T22:00:00Z
Gemini Models          Five Hour Limit Remaining  100%  2026-10-01T03:00:00Z
Claude and GPT models  Weekly Limit Remaining     100%  2026-10-07T22:00:00Z
Claude and GPT models  Five Hour Limit Remaining  100%  2026-10-01T03:00:00Z
```

---

## 📖 Command Reference

| Command | Description |
| :--- | :--- |
| `multigravity new <profile>` | Creates a profile directory and runs the initial OAuth login flow. |
| `multigravity import <profile>` | Copies the current default `~/.gemini/antigravity-cli` into a named profile. |
| `multigravity list` | Lists all created profiles. |
| `multigravity quotas` | Iterates over each profile and prints current model quotas. |
| `multigravity delete <profile>` | Removes a profile and its associated data directory. |
| `multigravity <profile> [args...]` | Launches `agy` with the specified profile and optional arguments. |
| `multigravity help` | Displays usage and help information. |

---

## 📂 Profile Architecture

Each profile is stored under `~/.config/multigravity-profiles/<profile_name>`:

```
~/.config/multigravity-profiles/
├── perso/
│   ├── .gemini/
│   │   └── antigravity-cli/   # Isolated tokens, conversation logs, and SQLite DBs
│   ├── .gitconfig             # Symlink -> host ~/.gitconfig
│   └── .ssh                   # Symlink -> host ~/.ssh
└── pote/
    ├── .gemini/
    │   └── antigravity-cli/   # Isolated tokens, conversation logs, and SQLite DBs
    ├── .gitconfig             # Symlink -> host ~/.gitconfig
    └── .ssh                   # Symlink -> host ~/.ssh
```

---

## 📄 License

MIT
