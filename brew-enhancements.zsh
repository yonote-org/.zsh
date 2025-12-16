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

alias uu="brewuu"  # Interactive brew update and upgrade with confirmation
alias uy="brewuy"  # Automatic brew update and upgrade with summary
alias bs="brew search"  # Search for Homebrew packages
alias bi="brew info"  # Show information about a Homebrew package
alias bin="brew install"  # Install a Homebrew package

