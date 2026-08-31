# Homebrew Enhancement Functions
#
# This file provides convenient aliases and functions for Homebrew package management,
# including interactive and automatic update/upgrade workflows.

# Interactive brew update and upgrade with user confirmation
brewuu() {
  brew update
  brew outdated --verbose | tee /dev/tty | read

  echo ""
  echo "Going to run 'brew upgrade'"

  if read -q "?Do you want to proceed? (y/n)"; then
    echo ''
    brew upgrade -y
    printf "\n\033[0;34m==>\033[0m $(tput bold)brew update && brew upgrade$(tput sgr0) executed\033[0;32m successfully\033[0m\n\n"
  fi
}

# Automatic brew update and upgrade with detailed summary
# Shows separate lists of updated formulae and casks after completion
brewuy() {
  brew update
  OUTDATED_FORMULAE=$(brew outdated --formula --verbose)
  OUTDATED_CASKS=$(brew outdated --cask --verbose)

  if [[ -n $OUTDATED_FORMULAE || -n $OUTDATED_CASKS ]]; then
    echo -e "\nGoing to run 'brew upgrade'\n"
    brew upgrade -y
    printf "\n\033[0;34m==>\033[0m $(tput bold)brew update && brew upgrade$(tput sgr0) executed\033[0;32m successfully\033[0m\n"
    
    if [[ -n $OUTDATED_CASKS ]]; then
      printf "\n\033[0;34m==>\033[0m $(tput bold)Updated casks:\n$(tput sgr0)"
      echo "$OUTDATED_CASKS" | while IFS= read -r line; do
        if [[ "$line" =~ '^(.+) \((.+)\) != (.+)$' ]]; then
          echo "${match[1]} ($(_brew_normalize_version "${match[2]}")) != $(_brew_normalize_version "${match[3]}")"
        else
          echo "$line"
        fi
      done
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

# Convenient aliases for Homebrew operations
alias uu="brewuu"   # Interactive brew update and upgrade with confirmation
alias uy="brewuy"   # Automatic brew update and upgrade with summary
alias bs="brew search"   # Search for Homebrew packages
alias bi="brew info"     # Show information about a Homebrew package
alias bin="brew install" # Install a Homebrew package

# brew-new — list formulae and casks newly added to Homebrew.
#
# Invoked by path rather than sourced: brew-new is a standalone executable
# script that ends in `exit`, so `source`-ing it here would print its report at
# every shell start and then close the shell.
#
#   bn                     what your last `brew update` pulled in (no network)
#   bn --on 2026-08-31     additions on one day          (GitHub API)
#   bn --since 2026-08-30  additions since a date        (GitHub API)
#   bn 7                   additions in the last 7 days  (GitHub API)
#   bn -h                  full usage
alias bn="$HOME/.zsh/brew-new"   # New formulae and casks since the last update

