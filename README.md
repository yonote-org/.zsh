# Zsh Configuration Addons

A collection of modular zsh configuration addons that enhance your shell experience with custom prompts, git integration, history search, Homebrew utilities, and more.

## Installation

### With Homebrew

The addons are published as the `zsh-addons` formula in the
[yonote-org Homebrew tap](https://github.com/yonote-org/homebrew-tap):

```bash
brew install yonote-org/tap/zsh-addons
```

Then add the following line to your `~/.zshrc` file (`brew install` prints it with the exact path
for your Homebrew prefix):

```bash
[[ -f "$(brew --prefix)/share/zsh-addons/configs.zsh" ]] && source "$(brew --prefix)/share/zsh-addons/configs.zsh"
```

The formula also installs the two tools the addons rely on: `expect` (for `uless.zsh`) and `jq`
(for `brew-new`'s online engine).

To uninstall:

```bash
brew uninstall zsh-addons
```

and remove the line from `~/.zshrc` — the `[[ -f ... ]]` guard keeps the shell quiet in the
meantime. `brew untap yonote-org/tap` removes the tap itself if nothing else from it is installed.

### From a clone

Clone the repo in your home directory (~):

```bash
git clone https://github.com/yonote-org/.zsh.git ~/.zsh
```

Then simply add the following line to your `~/.zshrc` file:

```bash
source ~/.zsh/configs.zsh
```

If the file doesn't exist in your home directory, you can add it with:

```bash
echo "source ~/.zsh/configs.zsh" >> ~/.zshrc
```

`configs.zsh` finds the other modules relative to its own location, so the clone can live
anywhere; `~/.zsh` is just the conventional place.

After adding the line, reload your shell configuration:

```bash
source ~/.zshrc
```

## Project Structure

This project consists of a main configuration file (`configs.zsh`) that sources various addon modules:

- **configs.zsh** - Main configuration file that sources all addons
- **aliases.zsh** - Common shell aliases
- **git.zsh** - Git integration and prompt enhancements
- **history.zsh** - Advanced history search widgets
- **confirm.zsh** - Interactive confirmation function
- **members.zsh** - macOS group membership utility
- **uless.zsh** - Color-preserving less integration
- **brew-enhancements.zsh** - Homebrew aliases and core upgrade utilities
- **brew-new.zsh** - Lists formulae and casks newly added to Homebrew
- **brew-autoupdate.zsh** - Homebrew cask autoupdate management (real-version aware)
- **local-user-config.zsh** - Local user configuration overrides (git-ignored, optional)

## Addon Details

### configs.zsh

The main configuration orchestrator that:
- Sets the `LANG` locale to `en_US.UTF-8`
- Sets up a custom prompt showing username and current directory
- Enables `INTERACTIVE_COMMENTS` (allows `#` comments in interactive shell)
- Sources all other addon modules

**Prompt Format:** `username ~/workspaces %`

### aliases.zsh

Provides convenient aliases for common commands:

- `ls` - Colored directory listing
- `ll` - Long format listing with hidden files
- `finder` - Opens macOS Finder, can be used with a directory as parameter: open the specified folder in the finder
- `cdr` - Change directory to the root of the current Git repository or worktree
- `cdw` - Change directory to a subdirectory of `~/workspaces`. Supports tab completion: typing `cdw <prefix><TAB>` lists matching subdirectories of `~/workspaces` (e.g. `cdw pm<TAB>` offers `pmain`, `pmain-worktrees`).

### git.zsh

Enhances the prompt with Git repository information:

- **Features:**
  - Displays current branch name in the prompt
  - Shows Git state indicators (REBASING, MERGING, CHERRY-PICKING, BISECTING, REVERTING, APPLYING, DETACHED HEAD)
  - Color-coded branch and state information

**Prompt Enhancement:** Adds `branch-name (STATE)` to your prompt when in a Git repository

**Functions:**
- `cd_git_root` (alias: `cdr`) - Changes directory to the root of the current Git repository. Works with both regular repositories and Git worktrees — in a worktree, it navigates to the worktree root, not the main repository's location.

**Usage:**
```bash
cdr    # Jump to repo/worktree root from any subdirectory
```

### history.zsh

Advanced history search capabilities with multiple search modes:

- **History Beginning Search:**
  - `Page Up` / `Page Down` - Search from beginning of command (cursor stays in place)
  - `Ctrl+Page Up` / `Ctrl+Page Down` - Search from beginning (cursor moves to end)

- **Pattern Search:**
  - `Ctrl+Page Up` (with Shift) - Search for pattern anywhere in command history (backward)
  - `Ctrl+Page Down` (with Shift) - Search for pattern anywhere in command history (forward)
  - Type a pattern, then use the keybindings to cycle through matches

**Usage:** Type part of a command, then use the keybindings to search through history.

### confirm.zsh

Interactive confirmation function for scripts:

```bash
if confirm; then
    echo "User confirmed"
else
    echo "User declined"
fi
```

**Options:**
- `Y` or `y` - Yes (returns 0)
- `N` or `n` - No (returns 1)
- `C` or `c` - Cancel (exits script)

### members.zsh

macOS utility function to list all members of a group:

```bash
members admin
members staff
```

**Usage:** `members <group-name>`

### uless.zsh

Automatic color preservation when piping to `less`:

- **Features:**
  - Automatically wraps commands with `unbuffer` when piping to `less`
  - Adds `-S -#10 -R` flags to preserve colors and enable scrolling
  - Stores original command in history

**Usage:** Just pipe any command to `less` as usual:
```bash
git log | less
ls -la | less
```

The colors will be automatically preserved!

**Requirements:** `expect` formula (installed via Homebrew automatically if missing)

### brew-enhancements.zsh

Homebrew package manager enhancements:

**Aliases:**
- `uu` / `brewuu` - Interactive brew update and upgrade (with confirmation)
- `uy` / `brewuy` - Automatic brew update and upgrade (shows what was updated)
- `bs` - `brew search`
- `bi` - `brew info`
- `bin` - `brew install`

**Functions:**
- `brewuy()` - Smart upgrade that:
  - Updates Homebrew
  - Checks for outdated formulae and casks separately
  - Only upgrades if there are updates available
  - Shows formatted output of what was updated
  - Displays separate lists for formulae and casks

**Usage Examples:**
```bash
uu    # Interactive upgrade with confirmation
uy    # Automatic upgrade with summary
bs python    # Search for Python packages
bi node      # Show info about Node.js
bin git      # Install Git
```

### brew-new.zsh

Lists formulae and casks **newly added to Homebrew**, in the two-section format of `brew update`'s
own report (`==> New Formulae` / `==> New Casks`), with a one-line description per item.

**Aliases:**
- `bn` - Alias of `brew_new`. Lists newly added formulae and casks.

**Two engines:**

- **local** (default) — what your most recent `brew update` pulled in. No network at all: it
  reproduces Homebrew's own "New Formulae/Casks" report, plus a description per item, by diffing
  the name lists in brew's API cache (`$(brew --cache)/api/*_names{,.before}.txt`), which is what
  `brew update` does internally. Covers only the gap between your last two updates, and has no
  per-item dates because none exist locally.
- **online** — any date window. Homebrew no longer clones the core/cask taps locally (API mode), so
  there is no local history to read; this queries the tap history on GitHub, where every addition
  carries a `name 1.2.3 (new formula)` / `(new cask)` line in its commit message.

Any date argument selects the online engine; with no arguments you get the local report.

**Options:**

| Option | Meaning |
|---|---|
| *(none)* | Local report: additions since your last `brew update` |
| `--on DATE` | Additions on that single day (`yyyy-MM-dd`) |
| `--since DATE` | Additions from that date until now |
| `--from DATE` / `--to DATE` | Explicit window, both ends inclusive |
| `days` | Additions in the last N days (default 7) |
| `--online` | Force the online engine over its 7-day default |
| `-u` | Force the local engine (the default) |
| `-f` / `-c` | Formulae only / casks only |
| `-d` | Also show descriptions (online engine; the local report always includes them) |
| `-h` | Full usage |

**Usage Examples:**
```bash
bn                              # since your last brew update (no network)
bn --on 2026-08-31              # added on that day
bn --since 2026-08-30           # added since that date
bn --from 2026-08-01 --to 2026-08-15
bn 30 -f                        # formulae added in the last 30 days
bn 30 -f -d                     # ...with descriptions
```

**Notes:**

- The local default makes **zero** network calls. The online engine costs one GitHub search request
  per 100 matching commits per tap — 2 requests for a week, 4 for a month, 9 for 90 days; `-f` or
  `-c` halves that. The authenticated limit is 30 searches/minute (10 unauthenticated).
- A failed or throttled query is reported as `(unavailable)` with a non-zero return rather than as
  an empty result, so a failure is never mistaken for "nothing new".
- Dates are the UTC date on which the addition landed on the tap's default branch, so an item keeps
  the same date regardless of which window you query.
- `HOMEBREW_NO_AUTO_UPDATE` is set for the duration of the call only: `brew desc` (which supplies the
  descriptions) can otherwise trigger an auto-update, which rotates the very name lists the local
  engine reads.

### brew-autoupdate.zsh

Homebrew cask autoupdate management (for casks with `auto_updates true` that are not handled by `brew update` / `brew upgrade`):

**Autoupdate Cask Management:**

Some Homebrew casks have auto-update enabled, which means they update themselves automatically. These casks are not included in `brew update` and `brew upgrade` by default. The autoupdate management functions allow you to track and update these casks manually. These functions are particularly useful when you have installed casks using auto-update that you don't use in your day-to-day routine but that are important to you to stay up to date.

**Aliases:**
- `bauc` - Alias of `brew_autoupdate_check`. Scans tracked casks with `auto_updates == true`, compares the **real app version** (from `mdls`) to the latest cask version, and groups casks into up-to-date vs outdated, showing real vs latest versions. Pass `--all` to check all installed auto-update casks instead of just the tracked list.

- `baua` - Alias of `brew_autoupdate_add`. Adds one or more casks to the autoupdate tracking list. The list is stored in `~/.homebrew/autoupdate-casks.config`. Duplicates are automatically prevented. Usage: `baua <cask1> [cask2] ...`

- `baur` - Alias of `brew_autoupdate_remove`. Removes one or more casks from the autoupdate tracking list. Usage: `baur <cask1> [cask2] ...`

- `baul` - Alias of `brew_autoupdate_list`. Displays all casks currently in the autoupdate tracking list.

- `bauu` - Alias of `brew_autoupdate_update`. Updates tracked casks with `auto_updates == true` whose **real app version is lower than the latest**. Pass `--all` to update all installed auto-update casks instead of just the tracked list. It:
  - Updates Homebrew to check for latest versions
  - Uses real app versions from `mdls` when possible (with comma/build number normalization)
  - Skips casks where real version is equal to or newer than latest
  - Falls back to Homebrew-installed version when real version cannot be read
  - Uses the `--greedy` flag to bypass auto-update restrictions
  - Provides a detailed summary including `(from -> to)` versions for updated casks and real/installed/latest versions for skipped ones

- `bug` - Alias of `brew_greedy_cask_upgrade`. Upgrades a specific cask using the `--greedy` flag, which allows upgrading casks even if they have auto-update enabled. Usage: `bug <cask>`

**Usage Examples:**
```bash
# Check tracked auto-update casks for newer versions
bauc

# Check all installed auto-update casks (not just tracked)
bauc --all

# Add casks to the tracking list
baua google-chrome firefox

# List tracked casks
baul

# Update all tracked casks whose real version is behind latest
bauu

# Remove a cask from tracking
baur google-chrome

# Upgrade a specific cask with --greedy flag
bug firefox
```

**Note:** The autoupdate list is stored in `~/.homebrew/autoupdate-casks.config` and is automatically sorted alphabetically.

### local-user-config.zsh

Local configuration file for machine-specific or user-specific settings that should not be committed to the repository.

- **Git-ignored:** This file is excluded from version control via `.gitignore`
- **Optional:** Sourced only if it exists — no warning or error if absent
- **Fixed location:** Always read from `~/.zsh/local-user-config.zsh`, also with a Homebrew install
  (create the directory if needed) — files under Homebrew's `share/` are replaced on upgrade
- **Purpose:** Place any personal aliases, environment variables, or overrides here

**Example content:**
```bash
export LC_MONETARY="he_IL.UTF-8"
alias myalias='some-command --with-options'
```

To create your local configuration:
```bash
touch ~/.zsh/local-user-config.zsh
# Add your personal aliases and settings
```

## Customization

Each addon can be customized by editing the respective file in `~/.zsh/` (with a Homebrew install,
put overrides in `local-user-config.zsh` instead — files under `$(brew --prefix)/share/zsh-addons`
are replaced on upgrade). The modular structure allows you to:

- Enable/disable addons by commenting out lines in `configs.zsh`
- Modify behavior by editing individual addon files
- Add your own addons by creating new files and sourcing them in `configs.zsh`
- Use `local-user-config.zsh` for machine-specific or private settings (git-ignored)

## Requirements

- **zsh** - Z shell (default on macOS)
- **Homebrew** - For `brew-enhancements.zsh` and `uless.zsh`
- **expect** - Provides `unbuffer` for `uless.zsh`; a dependency of the Homebrew formula, and
  installed by `uless.zsh` on first load otherwise
- **Git** - For `git.zsh` functionality
- **jq** - For `brew-new`'s online engine only (its default local engine needs nothing); a dependency
  of the Homebrew formula
- **gh** - Optional, used by `brew-new` when authenticated; falls back to `curl`

## License

Released under the [MIT License](LICENSE) — Copyright (c) 2025-2026 Yosef Yona.

