# Custom prompt configuration
autoload -Uz vcs_info

precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats '%b'
zstyle ':vcs_info:git:*' actionformats '%b'

# Function to check git state
function git_state_formated() {
    local is_git_repo=$(git rev-parse --is-inside-work-tree 2>/dev/null)
    if [[ $is_git_repo == "true" ]]; then
        local state=""
        local formated_state=""
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
        if [[ -n $state ]]; then
            formated_state=" ($state)"
        fi
        if [[ -n $is_git_repo ]]; then
            echo " %F{green}${vcs_info_msg_0_}%f%F{yellow}$formated_state%f"
        fi
    fi
}

# Set the prompt
setopt PROMPT_SUBST

# if [[ -n $PROMPT_END ]]; then
#     PROMPT='%n %F{cyan}%~%f %%%f '
# fi

# STOP=\'
# echo $STOP$PROMPT$STOP

# Split PROMPT at the space before the last space
# First remove last space and everything after, then remove the next space and everything after
PROMPT_NO_END="${${PROMPT% *}% *}"
# Get everything from the end of PROMPT_NO_END onward
PROMPT_END="${PROMPT:${#PROMPT_NO_END}}"


PROMPT='$PROMPT_NO_END%F{yellow}$(git_state_formated)%f$PROMPT_END'
#echo $STOP$PROMPT_END$STOP



