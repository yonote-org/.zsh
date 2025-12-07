# Zsh Configuration Addons

A collection of modular zsh configuration addons that enhance your shell experience with custom prompts, git integration, history search, Homebrew utilities, and more.

## Installation

To install these configurations, simply add the following line to your `~/.zshrc` file:

```bash
source ~/.zsh/configs.zsh
```

If the file doesn't exist in your home directory, you can add it with:

```bash
echo "source ~/.zsh/configs.zsh" >> ~/.zshrc
```

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
- **claude-run.zsh** - Claude Code setup with AWS Bedrock integration
- **uless.zsh** - Color-preserving less integration
- **brew-enhancements.zsh** - Homebrew aliases and upgrade utilities

## Addon Details

### configs.zsh

The main configuration orchestrator that:
- Sets up a custom prompt showing username and current directory
- Sources all other addon modules

**Prompt Format:** `username ~/workspaces %`

### aliases.zsh

Provides convenient aliases for common commands:

- `ls` - Colored directory listing
- `ll` - Long format listing with hidden files
- `finder` - Opens macOS Finder

### git.zsh

Enhances the prompt with Git repository information:

- **Features:**
  - Displays current branch name in the prompt
  - Shows Git state indicators (REBASING, MERGING, CHERRY-PICKING, BISECTING, REVERTING, APPLYING, DETACHED HEAD)
  - Color-coded branch and state information

**Prompt Enhancement:** Adds `branch-name (STATE)` to your prompt when in a Git repository

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

### claude-run.zsh

Claude Code integration with AWS Bedrock:

- **Function:** `claude-run`
- **Features:**
  - Automatically checks for active AWS session
  - Runs AWS SSO login if session expired
  - Launches Claude Code with proper environment variables
  - Configures AWS Bedrock with profile `claude-code` in region `eu-west-1`
  - Uses Claude Sonnet 4.5 model

**Usage:** Simply run `claude-run` to start Claude Code with AWS Bedrock backend.

**Requirements:**
- AWS CLI configured with `claude-code` profile
- AWS SSO access configured
- Claude Code installed

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

## Customization

Each addon can be customized by editing the respective file in `~/.zsh/`. The modular structure allows you to:

- Enable/disable addons by commenting out lines in `configs.zsh`
- Modify behavior by editing individual addon files
- Add your own addons by creating new files and sourcing them in `configs.zsh`

## Requirements

- **zsh** - Z shell (default on macOS)
- **Homebrew** - For `brew-enhancements.zsh` and `uless.zsh`
- **expect** - Automatically installed by `uless.zsh` if missing
- **Git** - For `git.zsh` functionality
- **AWS CLI** - For `claude-run.zsh` (optional)
- **Claude Code** - For `claude-run.zsh` (optional)

## License

This is a personal configuration collection. Feel free to use and modify as needed.

