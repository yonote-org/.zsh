# Custom widgets for pattern search
function pattern-search-backward() {
    # Store the current buffer content as the pattern if we're starting a new search
    if [[ -z $pattern_search_pattern ]]; then
        pattern_search_pattern=$BUFFER
    fi

    if [[ -n $pattern_search_pattern ]]; then
        # Get all matches and store them in an array
        local matches=(${(f)"$(fc -ln 0 | grep "$pattern_search_pattern")"})
        if [[ ${#matches} -gt 0 ]]; then
            # If this is the first search, initialize the position to one past the most recent match
            if [[ -z $pattern_search_pos ]]; then
                pattern_search_pos=$((${#matches} + 1))
            fi
            # Move to previous match and stop at the oldest match
            pattern_search_pos=$((pattern_search_pos - 1))
            if [[ $pattern_search_pos -lt 1 ]]; then
                pattern_search_pos=1
            fi
            # Set the buffer to the current match
            BUFFER=${matches[$pattern_search_pos]}
            CURSOR=$#BUFFER
        fi
    fi
}

function pattern-search-forward() {
    # If we've already restored the pattern, don't cycle
    if [[ -z $pattern_search_pattern ]]; then
        return
    fi

    # Store the current buffer content as the pattern if we're starting a new search
    if [[ -z $pattern_search_pattern ]]; then
        pattern_search_pattern=$BUFFER
    fi

    if [[ -n $pattern_search_pattern ]]; then
        # Get all matches and store them in an array
        local matches=(${(f)"$(fc -ln 0 | grep "$pattern_search_pattern")"})
        if [[ ${#matches} -gt 0 ]]; then
            # If this is the first search, initialize the position to the oldest match
            if [[ -z $pattern_search_pos ]]; then
                pattern_search_pos=1
            fi
            # Move to next match
            pattern_search_pos=$((pattern_search_pos + 1))
            if [[ $pattern_search_pos -gt ${#matches} ]]; then
                # Restore the original pattern when reaching the newest match
                BUFFER=$pattern_search_pattern
                CURSOR=$#BUFFER
                # Reset all search variables
                unset pattern_search_pos
                unset pattern_search_pattern
                return
            fi
            # Set the buffer to the current match
            BUFFER=${matches[$pattern_search_pos]}
            CURSOR=$#BUFFER
        fi
    fi
}

# Reset pattern search position and pattern when starting a new command
function accept-line() {
    pattern_search_pos=""
    pattern_search_pattern=""
    zle .accept-line
}
zle -N accept-line

zle -N pattern-search-backward
zle -N pattern-search-forward

# Key bindings for history search that keeps cursor position
bindkey '^[[5~' history-beginning-search-backward
bindkey '^[[6~' history-beginning-search-forward

# Key bindings for history search that moves cursor to end
bindkey '^[[1;5~' history-search-backward
bindkey '^[[1;6~' history-search-forward

# Key bindings for pattern search in history (search anywhere in command)
bindkey '^[[5;5~' pattern-search-backward
bindkey '^[[6;5~' pattern-search-forward

