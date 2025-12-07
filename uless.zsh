# author: yosef yona
# date: 2025-11-19
#
# Unbuffer + Less auto-rewrite function
# Usage: source this file to test, then add to ~/.zshrc if you like it
#
# Test it: source uless.zsh

# Check if 'expect' formula is installed (provides unbuffer command)
if ! brew list --formula | grep -q expect; then
  echo "Installing 'expect' formula (required for unbuffer)..."
  brew install --formula expect
fi

custom-accept-line() {
  local original="$BUFFER"

  # Match: "command | less" or "command |less" or "command |  less"
  # Pattern: \| *less matches pipe + zero or more spaces + "less"
  local pattern='^(.+)\| *less(.*)$'
  if [[ $BUFFER =~ $pattern ]]; then
    local cmd="${match[1]}"
    local less_args="${match[2]}"

    # Remove trailing spaces from command
    cmd="${cmd%"${cmd##*[![:space:]]}"}"

    # Add -R if not already present
    if [[ ! "$less_args" =~ -R ]]; then
      less_args=" -S -#10 -R${less_args}"
    fi

    local rewritten="unbuffer ${cmd} | less${less_args}"

    # Store original command in history
    print -s "$original"

    # Show visual feedback
    print -n "\r\033[K"  # Clear current line
    print -r "→ Rewritten: $rewritten"

    # Execute the rewritten command
    eval "$rewritten"

    # Reset the prompt instead of accepting the line
    zle reset-prompt
  else
    # No rewriting needed, normal accept
    zle .accept-line
  fi
}

zle -N accept-line custom-accept-line
