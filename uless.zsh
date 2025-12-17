# Author: Yosef Yona
# Date: 2025-11-19
#
# Unbuffer + Less Auto-rewrite Function
#
# This widget automatically rewrites commands that pipe to 'less' by:
# 1. Wrapping the command with 'unbuffer' to preserve ANSI colors
# 2. Adding useful less flags: -S (no wrap), -#10 (scroll amount), -R (raw control chars)
#
# Example: "git log | less" becomes "unbuffer git log | less -S -#10 -R"
#
# Widget Chaining: This widget properly chains with any previously defined accept-line
# widget (such as the one from history.zsh), ensuring all behaviors work together.
#
# Usage: This file is sourced automatically in configs.zsh

# Ensure 'expect' formula is installed (provides the unbuffer command)
if ! brew list --formula | grep -q expect; then
  echo "Installing 'expect' formula (required for unbuffer command)..."
  brew install --formula expect
fi

# Save reference to the current accept-line widget before we override it
# This allows us to chain with other custom accept-line widgets (like history.zsh)
functions[_uless_original_accept_line]="${functions[accept-line]:-${functions[.accept-line]}}"

# Custom accept-line widget that intercepts and rewrites commands piping to less
custom-accept-line() {
  local original="$BUFFER"

  # Regex pattern to match: "command | less" with optional whitespace variations
  # Examples matched: "cmd | less", "cmd |less", "cmd |  less -arg"
  # Captures: group 1 = command before pipe, group 2 = any less arguments
  local pattern='^(.+)\| *less(.*)$'

  if [[ $BUFFER =~ $pattern ]]; then
    local cmd="${match[1]}"
    local less_args="${match[2]}"

    # Remove trailing whitespace from the command portion
    cmd="${cmd%"${cmd##*[![:space:]]}"}"

    # Add our recommended less flags if -R (raw control chars) isn't already present
    # -S: Don't wrap long lines (horizontal scroll)
    # -#10: Set horizontal scroll amount to 10 characters
    # -R: Display raw ANSI color codes properly
    if [[ ! "$less_args" =~ -R ]]; then
      less_args=" -S -#10 -R${less_args}"
    fi

    # Build the rewritten command with unbuffer to preserve colors
    local rewritten="unbuffer ${cmd} | less${less_args}"

    # Store the original command in history (not the rewritten version)
    print -s "$original"

    # Provide visual feedback showing the rewritten command
    # Move to a new line (don't clear the current line so the prompt stays visible)
    print ""
    print -r "→ Rewritten: $rewritten"

    # Execute the rewritten command
    eval "$rewritten"

    # Clear the buffer and call the chained accept-line to let it do its cleanup
    # (like resetting history search state). Since BUFFER is empty, it won't
    # execute anything, but it will perform any state cleanup that needs to happen.
    BUFFER=""
    _uless_original_accept_line
  else
    # Command doesn't pipe to less - call the previous accept-line widget in the chain
    # This ensures other custom behaviors (like history search reset) still work
    _uless_original_accept_line
  fi
}

# Register the custom widget, replacing the current accept-line
zle -N accept-line custom-accept-line
