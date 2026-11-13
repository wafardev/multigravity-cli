<div align="center">

<img src="assets/multigravity-cli-logo.jpeg" alt="multigravity-cli logo" width="320" style="border-radius: 16px; margin-bottom: 16px;">

# mgy (multigravity-cli)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux%20%7C%20Windows-brightgreen.svg)]()
[![Shell](https://img.shields.io/badge/Shell-bash%20%7C%20zsh%20%7C%20powershell-orange.svg)]()

> Lightweight multi-account profile, session, and quota manager for the **Google Antigravity CLI (`agy`)**.

</div>

`mgy` (short for `multigravity`) enables developers to maintain multiple isolated Antigravity accounts (e.g., personal, work, client, or shared team accounts) on a single machine. Just as `agy` is the CLI for Antigravity, `mgy` is your tool for managing multi-gravity profiles.

It isolates Google OAuth credentials and quotas per profile, while keeping your conversation history, agent memories, MCP servers, and global configurations unified across all profiles.

---

## 🎯 Why mgy?

By default, the Antigravity CLI (`agy`) binds your credentials and your conversation history together in a single global directory: `~/.gemini/antigravity-cli` (`%USERPROFILE%\.gemini\antigravity-cli` on Windows).

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

When launching a session with `mgy <profile>`, the environment redirects `HOME` (and `%USERPROFILE%` on Windows) to `~/.config/multigravity-profiles/<profile>/`:

```
~/.config/multigravity-profiles/  (or %USERPROFILE%\.config\multigravity-profiles\)
├── <profile-1>/
│   ├── .gemini/
│   │   └── antigravity-cli/         # Symlink / Junction -> host antigravity-cli (SHARED)
│   ├── .gitconfig                   # Symlink / HardLink -> host .gitconfig
│   ├── .ssh                         # Symlink / Junction -> host .ssh
│   └── .tokens/ (or Keychains)      # Isolated credentials (Profile 1 OAuth token)
└── <profile-2>/
    ├── .gemini/
    │   └── antigravity-cli/         # Symlink / Junction -> host antigravity-cli (SHARED)
    ├── .gitconfig                   # Symlink / HardLink -> host .gitconfig
    ├── .ssh                         # Symlink / Junction -> host .ssh
    └── .tokens/ (or Keychains)      # Isolated credentials (Profile 2 OAuth token)
```

> [!NOTE]
> - **Unified History & Memory**: Because `.gemini/antigravity-cli` is shared across all profiles, all your conversations, chat summaries, CLI settings, prompt history (`history.jsonl`), and MCP servers are always preserved. You can resume any conversation across different accounts seamlessly (`mgy <profile> -c <id>` or `mgy <profile> --continue`).
> - **Isolated Credentials & Quota**: Each profile maintains its own isolated OAuth token. When you switch profiles, you draw from that specific account's quota limits without affecting others or losing any context.
> - **Preserved Identity**: Host `.gitconfig` and `.ssh` are linked across all profiles, ensuring git commits always retain your author name and email.
> - **Windows Native**: On Windows, NTFS Directory Junctions are utilized instead of symlinks, requiring **no Administrator privileges** or Developer Mode. Both `%USERPROFILE%` and `$HOME` are dynamically isolated.

---

## 🚀 Quick Start

### 1. Installation

#### macOS / Linux
```bash
git clone https://github.com/your-username/multigravity-cli.git
cd multigravity-cli
./install.sh
```

#### Windows (PowerShell / Windows Terminal)
```powershell
git clone https://github.com/your-username/multigravity-cli.git
cd multigravity-cli
.\install.ps1
```
*(Or run `npm run install-windows`). This installs `mgy.cmd`, `mgy.ps1`, `multigravity.cmd`, and `mgy-quota.cmd` into your `%USERPROFILE%\.local\bin` and ensures it is in your User `PATH`.*

#### Via NPM
```bash
cd multigravity-cli
npm link
```

Both `mgy` and `multigravity` commands are immediately available in your terminal!

---

### 2. Creating Profiles

Create as many profiles as you need for different Google accounts:

```bash
# Set up a new profile with Google login
mgy new <profile_name>

# (Optional) Import your current host machine session into a named profile
mgy import <profile_name>

# List all configured profiles
mgy list
```

---

### 3. Running Side-by-Side Sessions

Launch interactive sessions under separate profiles in separate terminal tabs, windows, or tmux panes:

* **Pane 1:**
  ```bash
  mgy <profile_1>
  ```

* **Pane 2:**
  ```bash
  mgy <profile_2>
  ```

Both instances execute simultaneously with full token and quota isolation while sharing all history and settings.

#### Dynamic Quota Switching & Autonomous Resume (`mgy auto`) [Experimental / Unstable]

> [!WARNING]
> **Stability Notice**: `mgy auto` is experimental and may not always work reliably depending on terminal environments, active process streams, or unexpected backend error responses. If you prefer rock-solid reliability without dynamic process termination and automated switching, use **`mgy best`** (which selects and starts the highest quota account without auto-switching) or select profiles manually (`mgy <profile>`).

`mgy auto` attempts to dynamically manage your accounts and quotas with zero manual intervention:

1. **Smart Profile Selection**: Evaluates Gemini quotas across all your accounts and starts `agy` using the profile with the highest remaining quota.
2. **Real-time Watchdog**: Runs an ultralight background monitor tracking child process output and API limits.
3. **Instant Auto-Kill & Failover**: The instant Google returns `RESOURCE_EXHAUSTED` (HTTP 429) mid-stream, `mgy auto` terminates the exhausted process.
4. **Autonomous Resumption**: Automatically rebinds SQLite `trajectory_meta`, switches to the next best account, and attempts to resume your active conversation with:
   ```text
   "/goal resume what you were doing before the quota depleted"
   ```
5. **Depleted Alert**: If every configured profile runs out of quota, `mgy auto` displays a prominent notification banner with countdown reset timers.

```bash
# Start or continue with dynamic quota switching (experimental):
mgy auto

# Continue the latest conversation with auto-switching:
mgy auto --continue

# Resume a specific conversation with auto-switching (-c is alias for --conversation):
mgy auto -c <conversation_id>
mgy auto --conversation <conversation_id>

# Run non-interactively or with custom flags:
mgy auto -p "Implement the user auth module" --dangerously-skip-permissions

# For stable runs without automatic switching, use 'mgy best':
mgy best
```

#### Starting the Best Account Without Auto-Switching (`mgy best`)
If you want to automatically start `agy` using the profile that currently has the most quota available without any background monitoring, process-killing, or automated account switching, use:
```bash
mgy best
mgy best --continue
mgy best -c <conversation_id>
```

#### Resuming Conversations Across Profiles & Automatic Failover
Because conversations and history are shared globally, you can resume any conversation under any account. `mgy` automatically rebinds `trajectory_meta` in SQLite when resuming (`-c <id>`, `--conversation=<id>`, or `--continue`) so switching accounts never causes trajectory ownership collisions, and automatically fails over to the next profile with available quota if your active profile hits `0%` quota:

```bash
# View recent conversation IDs:
mgy conversations

# Resume a specific conversation by ID (-c is an alias for --conversation):
mgy <profile_1> -c <conversation_id>
mgy <profile_1> --conversation=<conversation_id>

# Resume that SAME conversation under another profile to use a different quota:
mgy <profile_2> -c <conversation_id>

# Continue the most recent conversation on the best available profile:
mgy --continue
mgy <profile_1> --continue
mgy <profile_2> --continue
```

#### Passing Other Flags and Arguments
Any additional CLI arguments are forwarded directly to `agy`:
```bash
mgy <profile> --model gemini-2.5-flash
mgy <profile> -p "Explain distributed locks in Go"
```

---

### 4. Checking Quotas Across All Accounts

`mgy` features a built-in, multi-column **Quota Dashboard TUI** that queries the Antigravity API in parallel and displays quotas across all your profiles with live countdowns, progress bars, and critical alerts.

By default, `mgy quotas` displays **Gemini 3.8 and above** quotas (filtering out Claude, OpenAI, and older Gemini models for maximum speed and focus):

```bash
# View dashboard for all profiles (defaults to Gemini 3.8+):
mgy quotas

# Inspect quota for a single profile:
mgy quotas <profile_name>

# View ALL models (including Anthropic Claude, OpenAI, and older Gemini models):
mgy quotas -a
mgy quotas --all

# Live watch mode with auto-refresh (e.g. every 30s):
mgy quotas -w 30
```

**Dashboard Preview:**
```text
  QUOTA DASHBOARD (Gemini 3.8+)                                   │   QUOTA DASHBOARD (Gemini 3.8+)
  <profile_1> [PRO]                                               │   <profile_2> [ULTRA]
                                                                  │ 
  1 model                                                         │   1 model
  ──────────────────────────────────────────────────────────────│   ──────────────────────────────────────────────────────────────
                                                                  │ 
  ◆ Google Gemini                                                 │   ◆ Google Gemini
    3.8 Flash (High)       ━━━━━━━━━━ 100.0%   4h 59m             │     3.8 Flash (High)       ━━━━━━━━━━ 100.0%   4h 59m
```

---

### 5. Exporting & Importing Conversations Across Machines

`mgy` includes native support for exporting and migrating full conversation states, trajectories, agent memories, and audit artifacts between computers:

```bash
# Export a conversation by ID to a portable .tar.gz archive:
mgy export <conv_id> [path/to/archive.tar.gz]

# Example:
mgy export 71475e79-6329-4adb-a3e1-a71f84fe44b9 my_session.tar.gz

# On another machine, import the conversation:
mgy import my_session.tar.gz

# Resume it immediately:
mgy <profile> --conversation 71475e79-6329-4adb-a3e1-a71f84fe44b9
# Or with standard agy:
agy --conversation 71475e79-6329-4adb-a3e1-a71f84fe44b9
```

---

## 📖 Command Reference

Both `mgy` and `multigravity` can be used interchangeably:

| Command                             | Description                                                                                                                      |
| :---------------------------------- | :------------------------------------------------------------------------------------------------------------------------------- |
| `mgy auto [args...]`                | *(Experimental / Unstable)* Starts `agy` on highest quota profile; on quota exhaustion, kills process, switches accounts, and attempts to resume automatically. |
| `mgy best [args...]`                | Selects the profile with highest available quota and starts `agy` normally without auto-switching.                              |
| `mgy resume [conv_id] [args...]`    | Rebinds `trajectory_meta` in SQLite and resumes the conversation on the profile with the highest remaining quota.                |
| `mgy <profile> -c <id>`, `--conversation=<id>` | Rebinds `trajectory_meta` and resumes a specific conversation by ID (`-c` is alias for `--conversation`). |
| `mgy <profile> --continue`          | Continues the most recent conversation (auto-rebinding `trajectory_meta`).                                                       |
| `mgy conversations`                 | Lists recent conversation IDs, titles, and activity timestamps.                                                                  |
| `mgy export <id> [tar_path]`        | Exports a conversation, session SQLite DB, trajectory, and artifacts to a portable `.tar.gz` archive.                             |
| `mgy import <profile|tar_path>`     | Imports a conversation archive (`.tar.gz` / `.zip`) into `~/.gemini/antigravity-cli` OR imports the host session into a profile.   |
| `mgy import-conversation <tar_path>`| Alias for importing an exported conversation archive.                                                                            |
| `mgy fork --conversation=<id>`      | Forks an active conversation across all other profiles with fresh IDs.                                                           |
| `mgy new <profile>`                 | Creates a profile directory and executes the initial OAuth authentication flow.                                                  |
| `mgy list`                          | Lists all available configured profiles.                                                                                         |
| `mgy quotas [-a]`                   | Iterates across all profiles and outputs active Gemini 3.8+ quotas (`-a` / `--all` for all models).                              |
| `mgy delete <profile>`              | Prompts for confirmation and deletes the profile directory.                                                                      |
| `mgy <profile> [args...]`           | Starts `agy` with the chosen profile, forwarding any arguments (with automatic quota-exhaustion failover on exit).               |
| `mgy help`, `--help`, `-h`          | Displays the help and usage menu.                                                                                                |

---

## ⚙️ Configuration & Environment Variables

| Variable                     | Default                           | Purpose                                                                           |
| :--------------------------- | :-------------------------------- | :-------------------------------------------------------------------------------- |
| `MULTIGRAVITY_PROFILES_DIR`  | `~/.config/multigravity-profiles` | Base directory where all isolated profile workspaces are stored.                  |
| `MULTIGRAVITY_AUTO_FAILOVER` | `1` (enabled)                     | Set to `0` or `false` to disable automatic cross-profile failover on quota limit. |
| `MGY_QUOTA_ALL`              | `0` (Gemini 3.8+ only)            | Set to `1` or `true` to display all models (including Claude and OpenAI) by default.|
| `REAL_HOME`                  | `$HOME`                           | Host home directory used for resolving global `.gitconfig` and `.ssh` links.      |

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
