# Git Integration for ZSH Prompt
#
# This file enhances the prompt to display Git repository information including:
# - Current branch name
# - Repository state (REBASING, MERGING, CHERRY-PICKING, etc.)

# Load and configure the version control info system
autoload -Uz vcs_info

# Update vcs_info before each prompt
precmd() { vcs_info }

# Configure vcs_info to show branch name for git repositories
zstyle ':vcs_info:git:*' formats '%b'
zstyle ':vcs_info:git:*' actionformats '%b'

# Function to check and format git repository state
# Returns a formatted string with branch name and current state (if any)
git_state_formated() {
  local is_git_repo=$(git rev-parse --is-inside-work-tree 2>/dev/null)

  if [[ $is_git_repo == "true" ]]; then
    local state=""
    local formated_state=""

    # Detect various git states by checking for specific files/directories
    if [[ -d .git/rebase-merge ]]; then
      state="REBASING"
    elif [[ -f .git/MERGE_HEAD ]]; then
      state="MERGING"
    elif [[ -f .git/CHERRY_PICK_HEAD ]]; then
      state="CHERRY-PICKING"
    elif [[ -f .git/BISECT_LOG ]]; then
      state="BISECTING"
    elif [[ -f .git/REVERT_HEAD ]]; then
      state="REVERTING"
    elif [[ -f .git/sequencer/todo ]]; then
      state="APPLYING"
    elif [[ $(git rev-parse --abbrev-ref HEAD) == "HEAD" ]]; then
      state="DETACHED HEAD"
    fi

    # Format the state for display if one was detected
    if [[ -n $state ]]; then
      formated_state=" ($state)"
    fi

    # Return formatted git info: branch name in green, state in yellow
    echo " %F{green}${vcs_info_msg_0_}%f%F{yellow}$formated_state%f"
  fi
}

# Enable prompt substitution to allow dynamic command evaluation
setopt PROMPT_SUBST

# Modify the existing PROMPT to inject git information before the final prompt character
# Strategy: Split the prompt into everything except the last part, then inject git info
#
# Example transformation:
#   Original: '%n %F{cyan}%~%f %%%f '
#   Split into: PROMPT_NO_END='%n' and PROMPT_END=' %F{cyan}%~%f %%%f '
#   Result: '%n%F{yellow}$(git_state_formated)%f %F{cyan}%~%f %%%f '

# Extract everything except the last two "words" (space-separated parts)
PROMPT_NO_END="${${PROMPT% *}% *}"

# Extract the remaining part (last two "words")
PROMPT_END="${PROMPT:${#PROMPT_NO_END}}"

# Reconstruct PROMPT with git info injected in the middle
PROMPT='$PROMPT_NO_END%F{yellow}$(git_state_formated)%f$PROMPT_END'



