alias brewuu="brew update && brew outdated --verbose  | tee /dev/tty | read && echo -n \"\\nGoing to run 'brew upgrade'\n\" && read -q \"?Do you want to proceed? (y/n)\" && echo '' && brew upgrade && printf \"\\n\\033[0;34m==>\\033[0m $(tput bold)brew update && brew upgrade$(tput sgr0) executed\\033[0;32m successfully\\033[0m\\n\\n\""

brewuy() {
  brew update
  OUTDATED_FORMULAE=$(brew outdated --formula --verbose)
  OUTDATED_CASKS=$(brew outdated --cask --verbose)

  if [[ -n $OUTDATED_FORMULAE || -n $OUTDATED_CASKS ]]; then
    echo -e "\nGoing to run 'brew upgrade'\n"
    brew upgrade
    printf "\n\033[0;34m==>\033[0m $(tput bold)brew update && brew upgrade$(tput sgr0) executed\033[0;32m successfully\033[0m\n"
    
    if [[ -n $OUTDATED_CASKS ]]; then
      printf "\n\033[0;34m==>\033[0m $(tput bold)Updated casks:\n$(tput sgr0)"
      echo "$OUTDATED_CASKS"
    fi
    if [[ -n $OUTDATED_FORMULAE ]]; then
      printf "\n\033[0;34m==>\033[0m $(tput bold)Updated formulae:\n$(tput sgr0)"
      echo "$OUTDATED_FORMULAE"
    fi
  else
    printf "\n\033[0;33m==>\033[0m $(tput bold)No outdated packages. Skipping upgrade.$(tput sgr0)\n"
  fi
  echo ''
}

brew_autoupdate_check() {
  brew info --cask --json=v2 $(brew ls --cask) \
    | jq -r '
      .casks[]
      | select(.auto_updates == true)
      | (
          if (.installed | type) == "array" and (.installed | length) > 0 then
            .installed[0].version
          elif (.installed | type) == "string" then
            .installed
          else
            empty
          end
        ) as $inst
      | select($inst != .version)
      | "\(.token) (\($inst) -> \(.version))"
    '
}

brew_greedy_cask_upgrade() {
  local cask="$1"
  if [[ -z $cask ]]; then
    echo "Usage: bug <cask_token>" >&2
    return 1
  fi
  brew upgrade --cask --greedy "$cask"
}


alias uu="brewuu"  # Interactive brew update and upgrade with confirmation
alias uy="brewuy"  # Automatic brew update and upgrade with summary
alias bs="brew search"  # Search for Homebrew packages
alias bi="brew info"  # Show information about a Homebrew package
alias bin="brew install"  # Install a Homebrew package

### Autoupdate Cask Management ###
alias bug="brew_greedy_cask_upgrade"  # Upgrade a cask with --greedy flag (ignores auto-updates)
alias bauc="brew_autoupdate_check"  # Check which casks with auto-updates have newer versions available
alias baua="brew_autoupdate_add"  # Add cask(s) to the autoupdate list
alias baur="brew_autoupdate_remove"  # Remove cask(s) from the autoupdate list
alias baul="brew_autoupdate_list"  # List all casks in the autoupdate list
alias bauu="brew_autoupdate_update"  # Update all casks in the autoupdate list with --greedy flag


# Autoupdate cask management functions
BREW_LOCAL_CONFIG_DIR="$HOME/.homebrew"
BREW_AUTOUPDATE_FILE="$BREW_LOCAL_CONFIG_DIR/autoupdate-casks.config"

brew_autoupdate_add() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: brew_autoupdate_add <cask1> [cask2] ..." >&2
    return 1
  fi
  
  # Create directory and file if they don't exist
  [[ ! -d "$BREW_LOCAL_CONFIG_DIR" ]] && mkdir -p "$BREW_LOCAL_CONFIG_DIR"
  [[ ! -f "$BREW_AUTOUPDATE_FILE" ]] && touch "$BREW_AUTOUPDATE_FILE"
  
  local added=0
  for cask in "$@"; do
    # Check if cask is already in the list (use -Fx for whole-line literal matching)
    if grep -Fxq "$cask" "$BREW_AUTOUPDATE_FILE" 2>/dev/null; then
      printf "\033[0;33m==>\033[0m Cask '%s' is already in the autoupdate list\n" "$cask"
    else
      echo "$cask" >> "$BREW_AUTOUPDATE_FILE"
      printf "\033[0;32m==>\033[0m Added '%s' to autoupdate list\n" "$cask"
      ((added++))
    fi
  done
  
  if [[ $added -gt 0 ]]; then
    # Sort the file alphabetically and remove empty lines
    sort -u "$BREW_AUTOUPDATE_FILE" -o "$BREW_AUTOUPDATE_FILE"
    printf "\n\033[0;34m==>\033[0m Autoupdate list saved: %s\n" "$BREW_AUTOUPDATE_FILE"
  fi
}

brew_autoupdate_remove() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: brew_autoupdate_remove <cask1> [cask2] ..." >&2
    return 1
  fi
  
  # If file doesn't exist, no casks to remove
  if [[ ! -f "$BREW_AUTOUPDATE_FILE" ]] || [[ ! -s "$BREW_AUTOUPDATE_FILE" ]]; then
    printf "\033[0;33m==>\033[0m No casks in autoupdate list\n"
    return 0
  fi
  
  local removed=0
  for cask in "$@"; do
    if grep -Fxq "$cask" "$BREW_AUTOUPDATE_FILE" 2>/dev/null; then
      # Remove the line using grep -vFx for exact literal matching (works on both macOS and Linux)
      grep -vFx "$cask" "$BREW_AUTOUPDATE_FILE" > "${BREW_AUTOUPDATE_FILE}.tmp" && \
        mv "${BREW_AUTOUPDATE_FILE}.tmp" "$BREW_AUTOUPDATE_FILE"
      printf "\033[0;32m==>\033[0m Removed '%s' from autoupdate list\n" "$cask"
      ((removed++))
    else
      printf "\033[0;33m==>\033[0m Cask '%s' not found in autoupdate list\n" "$cask"
    fi
  done
  
  if [[ $removed -gt 0 ]]; then
    printf "\n\033[0;34m==>\033[0m Autoupdate list updated: %s\n" "$BREW_AUTOUPDATE_FILE"
  fi
}

brew_autoupdate_list() {
  if [[ ! -f "$BREW_AUTOUPDATE_FILE" ]] || [[ ! -s "$BREW_AUTOUPDATE_FILE" ]]; then
    printf "\033[0;33m==>\033[0m No casks in autoupdate list\n"
    printf "Use 'brew_autoupdate_add <cask>' to add casks\n"
    return 0
  fi
  
  printf "\033[0;34m==>\033[0m $(tput bold)Casks in autoupdate list:$(tput sgr0)\n"
  cat "$BREW_AUTOUPDATE_FILE" | while read -r cask; do
    [[ -n "$cask" ]] && echo "  - $cask"
  done
  echo ""
}

brew_autoupdate_update() {
  # If file doesn't exist, no casks to update
  if [[ ! -f "$BREW_AUTOUPDATE_FILE" ]] || [[ ! -s "$BREW_AUTOUPDATE_FILE" ]]; then
    printf "\033[0;33m==>\033[0m No casks in autoupdate list\n"
    return 0
  fi
  
  local casks=()
  while IFS= read -r cask; do
    [[ -n "$cask" ]] && casks+=("$cask")
  done < "$BREW_AUTOUPDATE_FILE"
  
  if [[ ${#casks[@]} -eq 0 ]]; then
    printf "\033[0;33m==>\033[0m No casks to update\n"
    return 0
  fi
  
  printf "\033[0;34m==>\033[0m $(tput bold)Updating Homebrew to check for latest versions...$(tput sgr0)\n"
  brew update >/dev/null 2>&1
  echo ""
  
  printf "\033[0;34m==>\033[0m $(tput bold)Checking %d cask(s) for updates:$(tput sgr0)\n" "${#casks[@]}"
  printf "  %s\n\n" "${casks[*]}"
  
  # Get list of outdated casks by comparing installed vs latest versions
  local outdated_casks
  outdated_casks=$(brew info --cask --json=v2 "${casks[@]}" 2>/dev/null \
    | jq -r '
      .casks[]
      | (
          if (.installed | type) == "array" and (.installed | length) > 0 then
            .installed[0].version
          elif (.installed | type) == "string" then
            .installed
          else
            empty
          end
        ) as $inst
      | select($inst != null and $inst != .version)
      | .token
    ' 2>/dev/null)
  
  local updated=0
  local failed=0
  local skipped=0
  local updated_casks=()
  local skipped_casks=()
  local total=${#casks[@]}
  
  for cask in "${casks[@]}"; do
    # Check if cask is outdated (use -Fx for whole-line literal matching)
    if echo "$outdated_casks" | grep -Fxq "$cask"; then
      printf "\033[0;34m==>\033[0m Updating %s...\n" "$cask"
      if brew_greedy_cask_upgrade "$cask"; then
        printf "\033[0;32m==>\033[0m Successfully updated %s\n" "$cask"
        updated_casks+=("$cask")
        ((updated++))
      else
        printf "\033[0;31m==>\033[0m Failed to update %s\n" "$cask"
        ((failed++))
      fi
    else
      printf "\033[0;36m==>\033[0m %s is already up-to-date, skipping\n" "$cask"
      skipped_casks+=("$cask")
      ((skipped++))
    fi
  done
  
  echo ""
  printf "\033[0;34m==>\033[0m $(tput bold)Update summary:$(tput sgr0)\n"
  if [[ $updated -gt 0 ]]; then
    printf "  \033[0;32mSuccessfully updated (%d out of %d):\033[0m\n" "$updated" "$total"
    for cask in "${updated_casks[@]}"; do
      printf "    - %s\n" "$cask"
    done
  fi
  if [[ $skipped -gt 0 ]]; then
    printf "  \033[0;36mAlready up-to-date (%d):\033[0m\n" "$skipped"
    for cask in "${skipped_casks[@]}"; do
      printf "    - %s\n" "$cask"
    done
  fi
  [[ $failed -gt 0 ]] && printf "  \033[0;31mFailed: %d\033[0m\n" "$failed"
  echo ""
}

