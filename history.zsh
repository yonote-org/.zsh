# Custom History Search Widgets with Pattern Matching
#
# This file provides enhanced history search functionality that allows searching
# for patterns anywhere in previous commands (not just at the beginning).

# Helper function to get all history matches for a pattern
_history_get_matches() {
  local pattern="$1"
  local matches=(${(f)"$(fc -ln 0 | grep "$pattern")"})
  echo "${matches[@]}"
}

# Helper function to set buffer and cursor position
_history_set_buffer() {
  local content="$1"
  BUFFER="$content"
  CURSOR=$#BUFFER
}

# Search backward through history for the pattern (toward older commands)
pattern-search-backward() {
  # Initialize pattern on first invocation
  if [[ -z $pattern_search_pattern ]]; then
    pattern_search_pattern=$BUFFER
  fi

  if [[ -n $pattern_search_pattern ]]; then
    # Get all history matches for the pattern
    local matches=(${(f)"$(fc -ln 0 | grep "$pattern_search_pattern")"})

    if [[ ${#matches} -gt 0 ]]; then
      # Initialize position to one past the newest match on first search
      if [[ -z $pattern_search_pos ]]; then
        pattern_search_pos=$((${#matches} + 1))
      fi

      # Move to previous (older) match, stopping at the oldest
      pattern_search_pos=$((pattern_search_pos - 1))
      if [[ $pattern_search_pos -lt 1 ]]; then
        pattern_search_pos=1
      fi

      # Update buffer with the current match
      _history_set_buffer "${matches[$pattern_search_pos]}"
    fi
  fi
}

# Search forward through history for the pattern (toward newer commands)
pattern-search-forward() {
  # Exit if no active search pattern
  if [[ -z $pattern_search_pattern ]]; then
    return
  fi

  # Get all history matches for the pattern
  local matches=(${(f)"$(fc -ln 0 | grep "$pattern_search_pattern")"})

  if [[ ${#matches} -gt 0 ]]; then
    # Initialize position to the oldest match on first search
    if [[ -z $pattern_search_pos ]]; then
      pattern_search_pos=1
    fi

    # Move to next (newer) match
    pattern_search_pos=$((pattern_search_pos + 1))

    # If we've cycled past the newest match, restore original pattern and reset
    if [[ $pattern_search_pos -gt ${#matches} ]]; then
      _history_set_buffer "$pattern_search_pattern"
      unset pattern_search_pos
      unset pattern_search_pattern
      return
    fi

    # Update buffer with the current match
    _history_set_buffer "${matches[$pattern_search_pos]}"
  fi
}

# Reset pattern search state when a command is executed
# This ensures each new search starts fresh
accept-line() {
  pattern_search_pos=""
  pattern_search_pattern=""
  zle .accept-line
}

# Register custom widgets
zle -N accept-line
zle -N pattern-search-backward
zle -N pattern-search-forward

# Key Bindings for History Search
#
# Multiple search modes are available:
# 1. Beginning search (keeps cursor position) - Page Up/Down
# 2. Standard search (moves cursor to end) - Ctrl+Page Up/Down
# 3. Pattern search (matches anywhere) - Ctrl+Shift+Page Up/Down

# Page Up/Down: Search from beginning of command, cursor stays in place
bindkey '^[[5~' history-beginning-search-backward
bindkey '^[[6~' history-beginning-search-forward

# Ctrl+Page Up/Down: Search from beginning, moves cursor to end
bindkey '^[[1;5~' history-search-backward
bindkey '^[[1;6~' history-search-forward

# Ctrl+Shift+Page Up/Down: Pattern search anywhere in command
bindkey '^[[5;5~' pattern-search-backward
bindkey '^[[6;5~' pattern-search-forward

