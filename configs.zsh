# Locale: English language with Israel region settings
export LANG="en_US.UTF-8"

# Custom prompt configuration
# this configure the prompt to only show the current directory and the user name
#something like this: 'username ~/workspaces % '
PROMPT='%n %F{cyan}%~%f %%%f '

setopt INTERACTIVE_COMMENTS

# Directory this file lives in, so the modules are found wherever the repo is
# installed: a ~/.zsh clone or Homebrew's share/zsh-addons.
_zsh_addons_dir="${${(%):-%x}:A:h}"

source "$_zsh_addons_dir/aliases.zsh"
source "$_zsh_addons_dir/git.zsh"

# Custom widgets for pattern search
source "$_zsh_addons_dir/history.zsh"

# Function to display the confirmation prompt
source "$_zsh_addons_dir/confirm.zsh"

# Function to list members of a group
source "$_zsh_addons_dir/members.zsh"

# override the accept-line function to add unbuffer + less auto-rewrite
# to preserve colors when piping to less
source "$_zsh_addons_dir/uless.zsh"

# Brew enhancements (aliases and functions)
source "$_zsh_addons_dir/brew-enhancements.zsh"

# Homebrew autoupdate cask management
source "$_zsh_addons_dir/brew-autoupdate.zsh"

# New formulae and casks added to Homebrew
source "$_zsh_addons_dir/brew-new.zsh"

unset _zsh_addons_dir

# Local configuration (git-ignored, optional). Always read from ~/.zsh, so it
# survives Homebrew upgrades, which replace everything under share/.
if [[ -f ~/.zsh/local-user-config.zsh ]]; then
  source ~/.zsh/local-user-config.zsh
fi

