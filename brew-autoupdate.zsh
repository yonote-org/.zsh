brew_autoupdate_check() {
  # Use the real application version from the installed app bundle (via mdls)
  # instead of only relying on the Homebrew "installed" version metadata.
  # This is important for auto-updating casks where the app may have updated
  # itself independently of Homebrew.
  printf "%s\n" "Checking for autoupdate casks..."

  # Ensure local/typed variables don't spam output when xtrace is enabled.
  # In zsh, TYPESET_SILENT suppresses the extra trace output for typeset/local.
  local _bauc_typeset_silent_was_on=0
  if setopt 2>/dev/null | grep -qx 'typeset_silent'; then
    _bauc_typeset_silent_was_on=1
  else
    setopt TYPESET_SILENT
  fi

  local caskroom
  caskroom="$(brew --prefix)/Caskroom"

  # Arrays to collect results for grouped output
  local -a tracked_outdated=()
  local -a untracked_outdated=()
  local -a up_to_date=()

  # Build a list of all auto-update casks with their installed/latest/app info.
  brew info --cask --json=v2 $(brew ls --cask) 2>/dev/null \
    | jq -r '
      .casks[]
      | select(.auto_updates == true)
      | .token as $token
      | .version as $latest
      | (
          if (.installed | type) == "array" and (.installed | length) > 0 then
            .installed[0].version
          elif (.installed | type) == "string" then
            .installed
          else
            empty
          end
        ) as $inst
      | .artifacts[]?
      | select(has("app"))
      | .app[0] as $app
      | "\($token)\t\($inst)\t\($latest)\t\($app)"
    ' 2>/dev/null \
    | while IFS=$'\t' read -r token inst latest app_name; do
        # Skip incomplete lines
        [[ -z "$token" || -z "$inst" || -z "$latest" || -z "$app_name" ]] && continue

        local app_path real_version
        app_path="$caskroom/$token/$inst/$app_name"

        if [[ -e "$app_path" ]]; then
          real_version=$(mdls -name kMDItemVersion -raw "$app_path" 2>/dev/null | tr -d '\r')
        else
          real_version=""
        fi

        # If we can't determine the real version, skip this cask for now.
        [[ -z "$real_version" ]] && continue

        # Normalize versions by stripping any ",build" suffix so that
        # "0.3.35,1" and "0.3.35" can be compared consistently.
        local clean_inst clean_latest clean_real
        clean_inst="${inst%%,*}"
        clean_latest="${latest%%,*}"
        clean_real="${real_version%%,*}"

        # If real version equals latest, this cask is up-to-date.
        if [[ "$clean_real" == "$clean_latest" ]]; then
          up_to_date+=("$token|$clean_inst|$clean_real|$clean_latest")
          continue
        fi

        # Otherwise, the real version differs from the latest: categorize as tracked/untracked.
        if [[ -f "$BREW_AUTOUPDATE_FILE" ]] && grep -Fxq "$token" "$BREW_AUTOUPDATE_FILE" 2>/dev/null; then
          tracked_outdated+=("$token|$clean_inst|$clean_real|$clean_latest")
        else
          untracked_outdated+=("$token|$clean_inst|$clean_real|$clean_latest")
        fi
      done

  echo ""

  # 1) Tracked casks whose real version differs from latest
  if (( ${#tracked_outdated[@]} > 0 )); then
    printf "\033[0;34m==>\033[0m $(tput bold)Tracked autoupdate casks needing updates (real vs latest):$(tput sgr0)\n"
    for entry in "${tracked_outdated[@]}"; do
      local token clean_inst clean_real clean_latest
      IFS='|' read -r token clean_inst clean_real clean_latest <<< "$entry"
      printf "  \033[0;31m- %s (real: %s -> latest: %s)\033[0m\n" "$token" "$clean_real" "$clean_latest"
    done
    echo ""
  fi

  # 2) Auto-update casks not in the tracked list whose real version differs from latest
  if (( ${#untracked_outdated[@]} > 0 )); then
    printf "\033[0;34m==>\033[0m $(tput bold)Untracked autoupdate casks needing updates (real vs latest):$(tput sgr0)\n"
    for entry in "${untracked_outdated[@]}"; do
      local token clean_inst clean_real clean_latest
      IFS='|' read -r token clean_inst clean_real clean_latest <<< "$entry"
      printf "  \033[0;31m- %s (real: %s -> latest: %s)\033[0m\n" "$token" "$clean_real" "$clean_latest"
    done
    echo ""
  fi

  # 3) Auto-update casks that are up-to-date (real == latest)
  if (( ${#up_to_date[@]} > 0 )); then
    printf "\033[0;34m==>\033[0m $(tput bold)Autoupdate casks that are up-to-date (real == latest):$(tput sgr0)\n"
    
    # Separate into warnings and checkmarks, then sort each by cask name
    local -a warnings=()
    local -a checkmarks=()
    
    for entry in "${up_to_date[@]}"; do
      local token clean_inst clean_real clean_latest
      IFS='|' read -r token clean_inst clean_real clean_latest <<< "$entry"
      
      if [[ "$clean_inst" == "$clean_real" ]]; then
        checkmarks+=("$entry")
      else
        warnings+=("$entry")
      fi
    done
    
    # Sort each array by token (cask name) using sort command
    if (( ${#warnings[@]} > 0 )); then
      local sorted_warnings_str
      sorted_warnings_str=$(printf '%s\n' "${warnings[@]}" | sort -t'|' -k1)
      warnings=("${(f)sorted_warnings_str}")
    fi
    if (( ${#checkmarks[@]} > 0 )); then
      local sorted_checkmarks_str
      sorted_checkmarks_str=$(printf '%s\n' "${checkmarks[@]}" | sort -t'|' -k1)
      checkmarks=("${(f)sorted_checkmarks_str}")
    fi
    
    # Display warnings first, then checkmarks
    for entry in "${warnings[@]}"; do
      local token clean_inst clean_real clean_latest
      IFS='|' read -r token clean_inst clean_real clean_latest <<< "$entry"
      printf "  \033[0;33m⚠\033[0m %s (installed: %s, real: %s, latest: %s)\n" \
        "$token" "$clean_inst" "$clean_real" "$clean_latest"
    done
    
    for entry in "${checkmarks[@]}"; do
      local token clean_inst clean_real clean_latest
      IFS='|' read -r token clean_inst clean_real clean_latest <<< "$entry"
      printf "  \033[0;32m✓\033[0m %s (installed: %s, real: %s, latest: %s)\n" \
        "$token" "$clean_inst" "$clean_real" "$clean_latest"
    done
    
    echo ""
  fi

  # Restore TYPESET_SILENT state if we changed it
  if [[ $_bauc_typeset_silent_was_on -eq 0 ]]; then
    unsetopt TYPESET_SILENT
  fi
}

brew_greedy_cask_upgrade() {
  local cask="$1"
  if [[ -z $cask ]]; then
    echo "Usage: bug <cask_token>" >&2
    return 1
  fi
  brew upgrade --cask --greedy "$cask"
}

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

  # Ensure version comparison helper is available (zsh builtin).
  autoload -Uz is-at-least 2>/dev/null || true

  # Ensure local/typed variables don't spam output when xtrace is enabled.
  # In zsh, TYPESET_SILENT suppresses the extra trace output for typeset/local.
  local _bauu_typeset_silent_was_on=0
  if setopt 2>/dev/null | grep -qx 'typeset_silent'; then
    _bauu_typeset_silent_was_on=1
  else
    setopt TYPESET_SILENT
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
  
  # Get metadata for casks whose Homebrew-installed version differs from the latest.
  # We will then check the *real* app version (via mdls) only for these candidates.
  local caskroom
  caskroom="$(brew --prefix)/Caskroom"
  
  local outdated_info
  outdated_info=$(brew info --cask --json=v2 "${casks[@]}" 2>/dev/null \
    | jq -r '
      .casks[]
      | select(.auto_updates == true)
      | .token as $token
      | .version as $latest
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
      | .artifacts[]?
      | select(has("app"))
      | .app[0] as $app
      | "\($token)\t\($inst)\t\($latest)\t\($app)"
    ' 2>/dev/null)
  
  local updated=0
  local failed=0
  local skipped=0
  local updated_casks=()
  local skipped_casks=()
  local total=${#casks[@]}
  
  for cask in "${casks[@]}"; do
    # Find metadata for this cask among those with installed != latest.
    local info_line token inst latest app_name

    # Use a single local assignment so TYPESET_SILENT can suppress xtrace noise.
    local info_line=$(printf '%s\n' "$outdated_info" | awk -F '\t' -v c="$cask" '$1 == c { print; exit }')

    if [[ -z "$info_line" ]]; then
      # Homebrew installed version already matches latest; no need to check real app version.
      # Fetch versions once for summary display (no mdls here).
      local meta_inst meta_latest
      meta_inst="$(brew info --cask --json=v2 "$cask" 2>/dev/null \
        | jq -r '
          .casks[0] as $c
          | (
              if ($c.installed | type) == "array" and ($c.installed | length) > 0 then
                $c.installed[0].version
              elif ($c.installed | type) == "string" then
                $c.installed
              else
                empty
              end
            )'
      )"
      meta_latest="$(brew info --cask --json=v2 "$cask" 2>/dev/null \
        | jq -r '.casks[0].version'
      )"
      local clean_meta_inst clean_meta_latest
      clean_meta_inst="${meta_inst%%,*}"
      clean_meta_latest="${meta_latest%%,*}"

      printf "\033[0;36m==>\033[0m %s is already up-to-date (brew metadata %s)\n" "$cask" "$clean_meta_latest"
      skipped_casks+=("$cask (installed: $clean_meta_inst, latest: $clean_meta_latest)")
      ((skipped++))
      continue
    fi

    IFS=$'\t' read -r token inst latest app_name <<< "$info_line"

    # Normalize versions by stripping any ",build" suffix so that
    # "0.3.35,1" and "0.3.35" can be compared consistently.
    local clean_inst clean_latest
    clean_inst="${inst%%,*}"
    clean_latest="${latest%%,*}"

    # Determine the real app version from the installed app bundle.
    local app_path real_version clean_real
    app_path="$caskroom/$token/$inst/$app_name"

    if [[ -e "$app_path" ]]; then
      real_version=$(mdls -name kMDItemVersion -raw "$app_path" 2>/dev/null | tr -d '\r')
      clean_real="${real_version%%,*}"
    else
      real_version=""
      clean_real=""
    fi

    # Decide whether to update:
    # - Prefer the real app version: only update when the real version is LOWER than the latest.
    # - If we can't read the real version, fall back to Homebrew metadata (clean_inst vs clean_latest).
    if [[ -n "$clean_real" ]]; then
      # If real version is equal to or newer than latest, skip.
      if is-at-least "$clean_real" "$clean_latest"; then
        printf "\033[0;36m==>\033[0m %s is already up-to-date (real app version %s), skipping\n" "$cask" "$real_version"
        skipped_casks+=("$cask (installed: $clean_inst, real app: $real_version, latest: $clean_latest)")
        ((skipped++))
        continue
      fi
    else
      if [[ "$clean_inst" == "$clean_latest" ]]; then
        printf "\033[0;36m==>\033[0m %s is already up-to-date, skipping\n" "$cask"
        skipped_casks+=("$cask (installed: $clean_inst, latest: $clean_latest)")
        ((skipped++))
        continue
      fi
    fi

    # At this point, real app version (if known) differs from latest, so update.
    printf "\033[0;34m==>\033[0m Updating %s...\n" "$cask"
    if brew_greedy_cask_upgrade "$cask"; then
      if [[ -n "$clean_real" ]]; then
        printf "\033[0;32m==>\033[0m Successfully updated %s (%s -> %s)\n" "$cask" "$clean_real" "$clean_latest"
        updated_casks+=("$cask ($clean_real -> $clean_latest)")
      else
        printf "\033[0;32m==>\033[0m Successfully updated %s (%s -> %s)\n" "$cask" "$clean_inst" "$clean_latest"
        updated_casks+=("$cask ($clean_inst -> $clean_latest)")
      fi
      ((updated++))
    else
      printf "\033[0;31m==>\033[0m Failed to update %s\n" "$cask"
      ((failed++))
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

  # Restore TYPESET_SILENT state if we changed it
  if [[ $_bauu_typeset_silent_was_on -eq 0 ]]; then
    unsetopt TYPESET_SILENT
  fi
}


