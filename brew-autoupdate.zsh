# Homebrew Autoupdate Cask Management
#
# This file provides functions to manage Homebrew casks with auto-update enabled.
# Some casks update themselves and are excluded from normal brew upgrade. These
# functions help track and update such casks by comparing Homebrew's recorded
# installed cask version with the latest cask version.

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

# Normalize version by removing non-significant suffixes: ",build", "-build", "+build"
# e.g., "1.2.3,4" -> "1.2.3", "3.5.4-9dfb8d8d" -> "3.5.4", "0.4.7+4" -> "0.4.7"
_brew_normalize_version() {
  local version="$1"
  version="${version%%,*}"  # Remove from first comma
  version="${version%%+*}"  # Remove from first plus
  echo "${version%%-*}"     # Remove from first dash
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
  # Compare Homebrew's recorded installed cask version with the latest cask
  # version. By default scoped to casks in the tracked list (baul); pass
  # --all to check every installed auto-update cask instead. Note: for
  # auto-updating casks, .installed is frozen at the last `brew install`/
  # `brew upgrade` time, so it may lag the app's actual version on disk —
  # this function reports brew's view, not the app's live state.

  # Parse arguments
  local all_mode=0
  while (( $# > 0 )); do
    case "$1" in
      --all)
        all_mode=1
        shift
        ;;
      -h|--help)
        echo "Usage: bauc [--all]"
        echo "  Check tracked auto-update casks for available updates."
        echo "  --all    Check all installed auto-update casks, not just the tracked list."
        return 0
        ;;
      *)
        echo "bauc: unknown argument '$1'" >&2
        echo "Usage: bauc [--all]" >&2
        return 1
        ;;
    esac
  done

  # Determine candidate casks based on scope.
  local -a candidate_casks=()
  local scope_label
  if (( all_mode )); then
    scope_label="All"
    while IFS= read -r cask; do
      [[ -n "$cask" ]] && candidate_casks+=("$cask")
    done <<< "$(brew ls --cask 2>/dev/null)"
    printf "%s\n" "Checking all installed auto-update casks..."
  else
    scope_label="Tracked"
    if [[ ! -f "$BREW_AUTOUPDATE_FILE" ]] || [[ ! -s "$BREW_AUTOUPDATE_FILE" ]]; then
      _brew_format_message "$BREW_COLOR_YELLOW" "No casks in autoupdate list"
      printf "Use 'baua <cask>' to add casks, or run 'bauc --all' to check all installed auto-update casks\n"
      return 0
    fi
    while IFS= read -r cask; do
      [[ -n "$cask" ]] && candidate_casks+=("$cask")
    done < "$BREW_AUTOUPDATE_FILE"
    printf "%s\n" "Checking tracked autoupdate casks..."
  fi

  if (( ${#candidate_casks[@]} == 0 )); then
    _brew_format_message "$BREW_COLOR_YELLOW" "No casks to check"
    return 0
  fi

  # Manage TYPESET_SILENT option
  _brew_typeset_silent_on
  local _typeset_silent_changed=$?

  # Arrays to collect results for grouped output
  local -a outdated=()
  local -a up_to_date=()

  # Fetch installed/latest for each candidate cask.
  # Restrict to auto_updates casks only — bauX commands only handle
  # auto-updatable casks (non-auto-update casks are ignored).
  brew info --cask --json=v2 "${candidate_casks[@]}" 2>/dev/null \
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
      | "\($token)\t\($inst)\t\($latest)"
    ' 2>/dev/null \
    | while IFS=$'\t' read -r token inst latest; do
        # Skip incomplete lines
        [[ -z "$token" || -z "$inst" || -z "$latest" ]] && continue

        # Normalize versions using helper function
        local clean_inst clean_latest
        clean_inst=$(_brew_normalize_version "$inst")
        clean_latest=$(_brew_normalize_version "$latest")

        if [[ "$clean_inst" == "$clean_latest" ]]; then
          up_to_date+=("$token|$clean_inst|$clean_latest")
        else
          outdated+=("$token|$clean_inst|$clean_latest")
        fi
      done

  echo ""

  # 1) Casks whose installed version differs from latest
  if (( ${#outdated[@]} > 0 )); then
    _brew_format_bold_message "$BREW_COLOR_BLUE" "${scope_label} autoupdate casks needing updates:"

    # Sort by token (cask name)
    local sorted_outdated_str
    sorted_outdated_str=$(printf '%s\n' "${outdated[@]}" | sort -t'|' -k1)
    outdated=("${(f)sorted_outdated_str}")

    for entry in "${outdated[@]}"; do
      local token clean_inst clean_latest
      IFS='|' read -r token clean_inst clean_latest <<< "$entry"
      printf "  ${BREW_COLOR_RED}- %s (installed: %s -> latest: %s)${BREW_COLOR_RESET}\n" "$token" "$clean_inst" "$clean_latest"
    done
    echo ""
  fi

  # 2) Casks that are up-to-date (installed == latest)
  if (( ${#up_to_date[@]} > 0 )); then
    _brew_format_bold_message "$BREW_COLOR_BLUE" "${scope_label} autoupdate casks that are up-to-date:"

    # Sort by token (cask name)
    local sorted_str
    sorted_str=$(printf '%s\n' "${up_to_date[@]}" | sort -t'|' -k1)
    up_to_date=("${(f)sorted_str}")

    for entry in "${up_to_date[@]}"; do
      local token clean_inst clean_latest
      IFS='|' read -r token clean_inst clean_latest <<< "$entry"
      printf "  ${BREW_COLOR_GREEN}✓${BREW_COLOR_RESET} %s (installed: %s, latest: %s)\n" \
        "$token" "$clean_inst" "$clean_latest"
    done

    echo ""
  fi

  # If nothing matched (e.g. candidates had no auto-update casks), say so.
  if (( ${#outdated[@]} == 0 && ${#up_to_date[@]} == 0 )); then
    _brew_format_message "$BREW_COLOR_YELLOW" "No auto-updatable casks found to check"
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
alias bauc="brew_autoupdate_check"  # Check tracked auto-update casks for updates (pass --all to check all installed)
alias baua="brew_autoupdate_add"  # Add cask(s) to the autoupdate list
alias baur="brew_autoupdate_remove"  # Remove cask(s) from the autoupdate list
alias baul="brew_autoupdate_list"  # List all casks in the autoupdate list
alias bauu="brew_autoupdate_update"  # Upgrade tracked auto-update casks (--greedy). Pass --all to upgrade all installed

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

  # Manage TYPESET_SILENT option (suppress xtrace noise from local assignments)
  _brew_typeset_silent_on
  local _typeset_silent_changed=$?

  local added=0
  for cask in "$@"; do
    # Query Homebrew for this name (returns both casks and formulae).
    local info
    info=$(brew info --json=v2 "$cask" 2>/dev/null)
    if [[ -z "$info" ]]; then
      _brew_format_message "$BREW_COLOR_YELLOW" "'$cask' not found in Homebrew, skipping"
      continue
    fi

    # Classify (cask / formula / none) and pull cask fields in one jq pass.
    # When a name matches both, we prefer cask (that's what baua is for).
    # Use '|' as delimiter (non-whitespace) so `read` doesn't merge empty
    # fields — the "installed" field is empty when the cask isn't installed.
    local parsed kind installed auto_updates
    parsed=$(echo "$info" | jq -r '
      if ((.casks // []) | length) > 0 then
        "cask|\(.casks[0].installed // "")|\(.casks[0].auto_updates // false)"
      elif ((.formulae // []) | length) > 0 then
        "formula||"
      else
        "none||"
      end
    ')
    IFS='|' read -r kind installed auto_updates <<< "$parsed"

    case "$kind" in
      formula)
        _brew_format_message "$BREW_COLOR_YELLOW" "'$cask' is a formula, not a cask — skipping"
        continue
        ;;
      none)
        _brew_format_message "$BREW_COLOR_YELLOW" "'$cask' not found in Homebrew, skipping"
        continue
        ;;
    esac

    # It's a cask. Warn if not installed.
    if [[ -z "$installed" ]]; then
      _brew_format_message "$BREW_COLOR_YELLOW" "Cask '$cask' is not installed — skipping"
      continue
    fi

    # Warn if the cask isn't auto-updatable (baua is only for auto-update casks).
    if [[ "$auto_updates" != "true" ]]; then
      _brew_format_message "$BREW_COLOR_YELLOW" "Cask '$cask' is not auto-updatable — skipping"
      continue
    fi

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

  # Restore TYPESET_SILENT state
  _brew_typeset_silent_restore "$_typeset_silent_changed"
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
  # Parse arguments
  local all_mode=0
  while (( $# > 0 )); do
    case "$1" in
      --all)
        all_mode=1
        shift
        ;;
      -h|--help)
        echo "Usage: bauu [--all]"
        echo "  Upgrade tracked auto-update casks with --greedy."
        echo "  --all    Upgrade all installed auto-update casks, not just the tracked list."
        return 0
        ;;
      *)
        echo "bauu: unknown argument '$1'" >&2
        echo "Usage: bauu [--all]" >&2
        return 1
        ;;
    esac
  done

  # Determine candidate casks based on scope.
  local -a candidate_casks=()
  local scope_label
  if (( all_mode )); then
    scope_label="all installed auto-update"
    while IFS= read -r cask; do
      [[ -n "$cask" ]] && candidate_casks+=("$cask")
    done <<< "$(brew ls --cask 2>/dev/null)"
  else
    scope_label="tracked"
    if [[ ! -f "$BREW_AUTOUPDATE_FILE" ]] || [[ ! -s "$BREW_AUTOUPDATE_FILE" ]]; then
      _brew_format_message "$BREW_COLOR_YELLOW" "No casks in autoupdate list"
      printf "Use 'baua <cask>' to add casks, or run 'bauu --all' to upgrade all installed auto-update casks\n"
      return 0
    fi
    while IFS= read -r cask; do
      [[ -n "$cask" ]] && candidate_casks+=("$cask")
    done < "$BREW_AUTOUPDATE_FILE"
  fi

  if (( ${#candidate_casks[@]} == 0 )); then
    _brew_format_message "$BREW_COLOR_YELLOW" "No casks to update"
    return 0
  fi

  # Manage TYPESET_SILENT option
  _brew_typeset_silent_on
  local _typeset_silent_changed=$?

  _brew_format_bold_message "$BREW_COLOR_BLUE" "Updating Homebrew to check for latest versions..."
  brew update >/dev/null 2>&1
  echo ""

  # Get installed/latest version metadata, filtering to auto-update casks only.
  # Non-auto-update candidates (e.g. a non-auto-update cask in baul, or
  # regular casks picked up by 'brew ls --cask' in --all mode) are silently
  # filtered out here — bauX commands only handle auto-updatable casks.
  local cask_info
  cask_info=$(brew info --cask --json=v2 "${candidate_casks[@]}" 2>/dev/null \
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
      | "\($token)\t\($inst)\t\($latest)"
    ' 2>/dev/null)

  # Build ordered list of auto-update casks from the filtered info.
  local casks=()
  while IFS=$'\t' read -r t _rest; do
    [[ -n "$t" ]] && casks+=("$t")
  done <<< "$cask_info"

  if (( ${#casks[@]} == 0 )); then
    _brew_format_message "$BREW_COLOR_YELLOW" "No auto-updatable casks found to update"
    _brew_typeset_silent_restore "$_typeset_silent_changed"
    return 0
  fi

  _brew_format_bold_message "$BREW_COLOR_BLUE" "Checking ${#casks[@]} ${scope_label} cask(s) for updates:"
  printf "  %s\n\n" "${casks[*]}"

  local updated=0
  local failed=0
  local skipped=0
  local updated_casks=()
  local skipped_casks=()
  local total=${#casks[@]}

  for cask in "${casks[@]}"; do
    local info_line token inst latest

    # Use a single local assignment so TYPESET_SILENT can suppress xtrace noise.
    local info_line=$(printf '%s\n' "$cask_info" | awk -F '\t' -v c="$cask" '$1 == c { print; exit }')

    if [[ -z "$info_line" ]]; then
      # Should not happen since $casks was derived from $cask_info, but guard anyway.
      _brew_format_message "$BREW_COLOR_YELLOW" "$cask: no metadata found, skipping"
      ((skipped++))
      continue
    fi

    IFS=$'\t' read -r token inst latest <<< "$info_line"

    # Normalize versions using helper function
    local clean_inst clean_latest
    clean_inst=$(_brew_normalize_version "$inst")
    clean_latest=$(_brew_normalize_version "$latest")

    # Skip if brew's installed version already matches the latest.
    if [[ "$clean_inst" == "$clean_latest" ]]; then
      _brew_format_message "$BREW_COLOR_CYAN" "$cask is already up-to-date, skipping"
      skipped_casks+=("$cask (installed: $clean_inst, latest: $clean_latest)")
      ((skipped++))
      continue
    fi

    # Installed differs from latest, upgrade.
    _brew_format_message "$BREW_COLOR_BLUE" "Updating $cask..."
    if brew_greedy_cask_upgrade "$cask"; then
      _brew_format_message "$BREW_COLOR_GREEN" "Successfully updated $cask ($clean_inst -> $clean_latest)"
      updated_casks+=("$cask ($clean_inst -> $clean_latest)")
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


