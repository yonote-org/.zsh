# Homebrew Autoupdate Cask Management
#
# This file provides functions to manage Homebrew casks with auto-update enabled.
# Some casks update themselves and are excluded from normal brew upgrade. These
# functions help track and update such casks by comparing the real app version
# (from mdls) with the latest cask version.

#==================================================================================
# Color Constants
#==================================================================================
# Only set these if not already defined (to allow re-sourcing without errors)
if [[ -z "$BREW_COLOR_BLUE" ]]; then
  readonly BREW_COLOR_BLUE='\033[0;34m'
  readonly BREW_COLOR_GREEN='\033[0;32m'
  readonly BREW_COLOR_YELLOW='\033[0;33m'
  readonly BREW_COLOR_RED='\033[0;31m'
  readonly BREW_COLOR_CYAN='\033[0;36m'
  readonly BREW_COLOR_RESET='\033[0m'
fi

#==================================================================================
# Helper Functions
#==================================================================================

# Manage TYPESET_SILENT option to prevent xtrace spam for local variable declarations
# This function modifies the shell option directly and stores state in a variable
_brew_typeset_silent_on() {
  if setopt 2>/dev/null | grep -qx 'typeset_silent'; then
    # TYPESET_SILENT is already on, return 1 to indicate we didn't change it
    return 1
  else
    # TYPESET_SILENT is off, turn it on and return 0 to indicate we changed it
    setopt TYPESET_SILENT
    return 0
  fi
}

_brew_typeset_silent_restore() {
  # If argument is 0, it means we turned it on, so turn it off
  # If argument is 1, it means it was already on, so leave it on
  if [[ "$1" -eq 0 ]]; then
    unsetopt TYPESET_SILENT
  fi
}

# Normalize version by removing ",build" suffix (e.g., "1.2.3,4" -> "1.2.3")
_brew_normalize_version() {
  local version="$1"
  echo "${version%%,*}"
}

# Get real app version from installed .app bundle using mdls
# Returns empty string if app path doesn't exist or version can't be determined
_brew_get_real_app_version() {
  local app_path="$1"
  if [[ -e "$app_path" ]]; then
    mdls -name kMDItemVersion -raw "$app_path" 2>/dev/null | tr -d '\r'
  else
    echo ""
  fi
}

# Compare two versions semantically using sort -V
# Returns 0 if version1 < version2, 1 otherwise
_brew_version_is_lower() {
  local version1="$1"
  local version2="$2"

  # Use sort -V for semantic version comparison
  local earliest
  earliest=$(printf '%s\n%s\n' "$version1" "$version2" | sort -V | head -n1)

  # If earliest equals version1, then version1 < version2
  [[ "$earliest" == "$version1" && "$version1" != "$version2" ]]
}

# Format a colored message with an arrow prefix
_brew_format_message() {
  local color="$1"
  local message="$2"
  printf "${color}==>${BREW_COLOR_RESET} %s\n" "$message"
}

# Format a colored message with bold text
_brew_format_bold_message() {
  local color="$1"
  local message="$2"
  printf "${color}==>${BREW_COLOR_RESET} $(tput bold)%s$(tput sgr0)\n" "$message"
}

#==================================================================================
# Main Functions
#==================================================================================

brew_autoupdate_check() {
  # Use the real application version from the installed app bundle (via mdls)
  # instead of only relying on the Homebrew "installed" version metadata.
  # This is important for auto-updating casks where the app may have updated
  # itself independently of Homebrew.

  printf "%s\n" "Checking for autoupdate casks..."

  # Manage TYPESET_SILENT option
  _brew_typeset_silent_on
  local _typeset_silent_changed=$?

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

        # Get real app version using helper
        real_version=$(_brew_get_real_app_version "$app_path")

        # If we can't determine the real version, skip this cask for now.
        [[ -z "$real_version" ]] && continue

        # Normalize versions using helper function
        local clean_inst clean_latest clean_real
        clean_inst=$(_brew_normalize_version "$inst")
        clean_latest=$(_brew_normalize_version "$latest")
        clean_real=$(_brew_normalize_version "$real_version")

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
    _brew_format_bold_message "$BREW_COLOR_BLUE" "Tracked autoupdate casks needing updates (real vs latest):"
    for entry in "${tracked_outdated[@]}"; do
      local token clean_inst clean_real clean_latest
      IFS='|' read -r token clean_inst clean_real clean_latest <<< "$entry"
      printf "  ${BREW_COLOR_RED}- %s (real: %s -> latest: %s)${BREW_COLOR_RESET}\n" "$token" "$clean_real" "$clean_latest"
    done
    echo ""
  fi

  # 2) Auto-update casks not in the tracked list whose real version differs from latest
  if (( ${#untracked_outdated[@]} > 0 )); then
    _brew_format_bold_message "$BREW_COLOR_BLUE" "Untracked autoupdate casks needing updates (real vs latest):"
    for entry in "${untracked_outdated[@]}"; do
      local token clean_inst clean_real clean_latest
      IFS='|' read -r token clean_inst clean_real clean_latest <<< "$entry"
      printf "  ${BREW_COLOR_RED}- %s (real: %s -> latest: %s)${BREW_COLOR_RESET}\n" "$token" "$clean_real" "$clean_latest"
    done
    echo ""
  fi

  # 3) Auto-update casks that are up-to-date (real == latest)
  if (( ${#up_to_date[@]} > 0 )); then
    _brew_format_bold_message "$BREW_COLOR_BLUE" "Autoupdate casks that are up-to-date (real == latest):"
    
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
      printf "  ${BREW_COLOR_YELLOW}⚠${BREW_COLOR_RESET} %s (installed: %s, real: %s, latest: %s)\n" \
        "$token" "$clean_inst" "$clean_real" "$clean_latest"
    done

    for entry in "${checkmarks[@]}"; do
      local token clean_inst clean_real clean_latest
      IFS='|' read -r token clean_inst clean_real clean_latest <<< "$entry"
      printf "  ${BREW_COLOR_GREEN}✓${BREW_COLOR_RESET} %s (installed: %s, real: %s, latest: %s)\n" \
        "$token" "$clean_inst" "$clean_real" "$clean_latest"
    done

    echo ""
  fi

  # Restore TYPESET_SILENT state
  _brew_typeset_silent_restore "$_typeset_silent_changed"
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
      _brew_format_message "$BREW_COLOR_YELLOW" "Cask '$cask' is already in the autoupdate list"
    else
      echo "$cask" >> "$BREW_AUTOUPDATE_FILE"
      _brew_format_message "$BREW_COLOR_GREEN" "Added '$cask' to autoupdate list"
      ((added++))
    fi
  done

  if [[ $added -gt 0 ]]; then
    # Sort the file alphabetically and remove empty lines
    sort -u "$BREW_AUTOUPDATE_FILE" -o "$BREW_AUTOUPDATE_FILE"
    echo ""
    _brew_format_message "$BREW_COLOR_BLUE" "Autoupdate list saved: $BREW_AUTOUPDATE_FILE"
  fi
}

brew_autoupdate_remove() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: brew_autoupdate_remove <cask1> [cask2] ..." >&2
    return 1
  fi

  # If file doesn't exist, no casks to remove
  if [[ ! -f "$BREW_AUTOUPDATE_FILE" ]] || [[ ! -s "$BREW_AUTOUPDATE_FILE" ]]; then
    _brew_format_message "$BREW_COLOR_YELLOW" "No casks in autoupdate list"
    return 0
  fi

  local removed=0
  for cask in "$@"; do
    if grep -Fxq "$cask" "$BREW_AUTOUPDATE_FILE" 2>/dev/null; then
      # Remove the line using grep -vFx for exact literal matching (works on both macOS and Linux)
      grep -vFx "$cask" "$BREW_AUTOUPDATE_FILE" > "${BREW_AUTOUPDATE_FILE}.tmp" && \
        mv "${BREW_AUTOUPDATE_FILE}.tmp" "$BREW_AUTOUPDATE_FILE"
      _brew_format_message "$BREW_COLOR_GREEN" "Removed '$cask' from autoupdate list"
      ((removed++))
    else
      _brew_format_message "$BREW_COLOR_YELLOW" "Cask '$cask' not found in autoupdate list"
    fi
  done

  if [[ $removed -gt 0 ]]; then
    echo ""
    _brew_format_message "$BREW_COLOR_BLUE" "Autoupdate list updated: $BREW_AUTOUPDATE_FILE"
  fi
}

brew_autoupdate_list() {
  if [[ ! -f "$BREW_AUTOUPDATE_FILE" ]] || [[ ! -s "$BREW_AUTOUPDATE_FILE" ]]; then
    _brew_format_message "$BREW_COLOR_YELLOW" "No casks in autoupdate list"
    printf "Use 'brew_autoupdate_add <cask>' to add casks\n"
    return 0
  fi

  _brew_format_bold_message "$BREW_COLOR_BLUE" "Casks in autoupdate list:"
  cat "$BREW_AUTOUPDATE_FILE" | while read -r cask; do
    [[ -n "$cask" ]] && echo "  - $cask"
  done
  echo ""
}

brew_autoupdate_update() {
  # If file doesn't exist, no casks to update
  if [[ ! -f "$BREW_AUTOUPDATE_FILE" ]] || [[ ! -s "$BREW_AUTOUPDATE_FILE" ]]; then
    _brew_format_message "$BREW_COLOR_YELLOW" "No casks in autoupdate list"
    return 0
  fi

  # Manage TYPESET_SILENT option
  _brew_typeset_silent_on
  local _typeset_silent_changed=$?
  
  local casks=()
  while IFS= read -r cask; do
    [[ -n "$cask" ]] && casks+=("$cask")
  done < "$BREW_AUTOUPDATE_FILE"
  
  if [[ ${#casks[@]} -eq 0 ]]; then
    _brew_format_message "$BREW_COLOR_YELLOW" "No casks to update"
    return 0
  fi

  _brew_format_bold_message "$BREW_COLOR_BLUE" "Updating Homebrew to check for latest versions..."
  brew update >/dev/null 2>&1
  echo ""

  _brew_format_bold_message "$BREW_COLOR_BLUE" "Checking ${#casks[@]} cask(s) for updates:"
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
      clean_meta_inst=$(_brew_normalize_version "$meta_inst")
      clean_meta_latest=$(_brew_normalize_version "$meta_latest")

      _brew_format_message "$BREW_COLOR_CYAN" "$cask is already up-to-date (brew metadata $clean_meta_latest)"
      skipped_casks+=("$cask (installed: $clean_meta_inst, latest: $clean_meta_latest)")
      ((skipped++))
      continue
    fi

    IFS=$'\t' read -r token inst latest app_name <<< "$info_line"

    # Normalize versions using helper function
    local clean_inst clean_latest
    clean_inst=$(_brew_normalize_version "$inst")
    clean_latest=$(_brew_normalize_version "$latest")

    # Determine the real app version from the installed app bundle
    local app_path real_version clean_real
    app_path="$caskroom/$token/$inst/$app_name"

    real_version=$(_brew_get_real_app_version "$app_path")
    if [[ -n "$real_version" ]]; then
      clean_real=$(_brew_normalize_version "$real_version")
    else
      clean_real=""
    fi

    # Decide whether to update:
    # - Prefer the real app version: only update when the real version is LOWER than the latest.
    # - If we can't read the real version, fall back to Homebrew metadata (clean_inst vs clean_latest).
    if [[ -n "$clean_real" ]]; then
      # If real version equals latest or is higher, skip the update
      if [[ "$clean_real" == "$clean_latest" ]] || ! _brew_version_is_lower "$clean_real" "$clean_latest"; then
        _brew_format_message "$BREW_COLOR_CYAN" "$cask is already up-to-date (real app version $real_version), skipping"
        skipped_casks+=("$cask (installed: $clean_inst, real app: $real_version, latest: $clean_latest)")
        ((skipped++))
        continue
      fi
    else
      # Fall back to Homebrew metadata comparison
      if [[ "$clean_inst" == "$clean_latest" ]]; then
        _brew_format_message "$BREW_COLOR_CYAN" "$cask is already up-to-date, skipping"
        skipped_casks+=("$cask (installed: $clean_inst, latest: $clean_latest)")
        ((skipped++))
        continue
      fi
    fi

    # At this point, real app version (if known) differs from latest, so update.
    _brew_format_message "$BREW_COLOR_BLUE" "Updating $cask..."
    if brew_greedy_cask_upgrade "$cask"; then
      if [[ -n "$clean_real" ]]; then
        _brew_format_message "$BREW_COLOR_GREEN" "Successfully updated $cask ($clean_real -> $clean_latest)"
        updated_casks+=("$cask ($clean_real -> $clean_latest)")
      else
        _brew_format_message "$BREW_COLOR_GREEN" "Successfully updated $cask ($clean_inst -> $clean_latest)"
        updated_casks+=("$cask ($clean_inst -> $clean_latest)")
      fi
      ((updated++))
    else
      _brew_format_message "$BREW_COLOR_RED" "Failed to update $cask"
      ((failed++))
    fi
  done
  
  echo ""
  _brew_format_bold_message "$BREW_COLOR_BLUE" "Update summary:"
  if [[ $updated -gt 0 ]]; then
    printf "  ${BREW_COLOR_GREEN}Successfully updated ($updated out of $total):${BREW_COLOR_RESET}\n"
    for cask in "${updated_casks[@]}"; do
      printf "    - %s\n" "$cask"
    done
  fi
  if [[ $skipped -gt 0 ]]; then
    printf "  ${BREW_COLOR_CYAN}Already up-to-date ($skipped):${BREW_COLOR_RESET}\n"
    for cask in "${skipped_casks[@]}"; do
      printf "    - %s\n" "$cask"
    done
  fi
  [[ $failed -gt 0 ]] && printf "  ${BREW_COLOR_RED}Failed: $failed${BREW_COLOR_RESET}\n"
  echo ""

  # Restore TYPESET_SILENT state
  _brew_typeset_silent_restore "$_typeset_silent_changed"
}


