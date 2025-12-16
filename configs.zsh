# Custom prompt configuration
# this configure the prompt to only show the current directory and the user name
#something like this: 'username ~/workspaces % '
PROMPT='%n %F{cyan}%~%f %%%f '

source ~/.zsh/aliases.zsh
source ~/.zsh/git.zsh

# Custom widgets for pattern search
source ~/.zsh/history.zsh

# Function to display the confirmation prompt
source ~/.zsh/confirm.zsh

# Function to list members of a group
source ~/.zsh/members.zsh

# Claude Code setup function
source ~/.zsh/claude-run.zsh

# override the accept-line function to add unbuffer + less auto-rewrite
# to preserve colors when piping to less
source ~/.zsh/uless.zsh

# Brew enhancements (aliases and functions)
source ~/.zsh/brew-enhancements.zsh

# Homebrew autoupdate cask management
source ~/.zsh/brew-autoupdate.zsh

