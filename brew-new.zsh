# Homebrew New Formulae and Casks
#
# This file provides a function to list formulae and casks newly added to
# Homebrew, split into two sections.
#
# Two engines:
#   local (default)  What your most recent `brew update` pulled in. No network
#                    at all: reproduces brew's own "New Formulae/Casks" report,
#                    plus a description per item, by diffing the name lists in
#                    brew's API cache. Covers only the gap between your last two
#                    updates, and has no dates.
#   online           Any date window. Homebrew's core/cask taps are not cloned
#                    locally (API mode), so this keeps a commit-only shallow
#                    mirror of each tap under ~/.cache/brew-new (no trees or
#                    blobs: a few MB per month of window) and reads the
#                    additions from its history, where every one carries a
#                    line of the form "name 1.2.3 (new formula)" / "(new cask)".
#                    One git fetch per tap; no GitHub API, so no rate limits or
#                    result caps.
#
# Any date argument (--on, --since, --from, --to, or a day count) selects the
# online engine; with no arguments you get the local report.

#==================================================================================
# Helper Functions
#==================================================================================

# Lazy Homebrew dependencies (see require.zsh), also when sourced on its own
(( $+functions[_zsh_addons_require] )) || source "${${(%):-%x}:A:h}/require.zsh"

_brew_new_usage() {
  cat <<'USAGE'
brew-new — list formulae and casks newly added to Homebrew.

Usage: bn [-d] [-f|-c] [-u] [--online] [--on DATE] [--since DATE]
          [--from DATE] [--to DATE] [days]
  -d            also show descriptions [online]; the local report always has them
  -f            formulae only
  -c            casks only
  -u            force the local engine (the default; rejects date arguments)
  --online      force the online engine over its default 7-day window
  --on DATE     additions on that one day (SQL format, yyyy-MM-dd) [online]
  --since DATE  additions from that date until now [online]
  --from DATE   window start, inclusive (SQL format, yyyy-MM-dd) [online]
  --to DATE     window end, inclusive (SQL format, yyyy-MM-dd) [online]
  days          how far back to look (default: 7); used only when --from is
                absent, counting back from --to when given, else from today

Engines:
  local   (no date argument) what your last `brew update` pulled in, with a
          description per item. No network: diffs the name lists in brew's
          API cache, as `brew update` itself does. No per-item dates.
  online  (any date argument) any window, with date and version per item,
          read from the taps' git history. Keeps a commit-only shallow mirror
          of homebrew-core and homebrew-cask under BREW_NEW_CACHE (default
          ~/.cache/brew-new; deleting it is always safe), refreshed by one
          git fetch per tap on every run: about 4 s on first use, 2 s after,
          a few MB on disk. No GitHub API, so no rate limits. Needs git.
          Dates are the UTC day the addition landed on the tap's main branch.

Returns non-zero if a section could not be retrieved, so a failed fetch is
never reported as an empty one. Set BREW_NEW_DEBUG=1 to log commit lines
skipped as ambiguous.
USAGE
}

_brew_new_die() { echo "brew-new: $1" >&2; }

# Accept only yyyy-MM-dd, and reject dates that do not exist. BSD date happily
# rolls 2026-02-30 into March, so require the parsed date to echo back
# unchanged; GNU date is tried second for portability.
_brew_new_norm_date() {
  local in="$1" out
  case "$in" in
    [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) ;;
    *) return 1 ;;
  esac
  out=$(date -j -f "%Y-%m-%d" "$in" +%Y-%m-%d 2>/dev/null) \
    || out=$(date -d "$in" +%Y-%m-%d 2>/dev/null) \
    || return 1
  [ "$out" = "$in" ] || return 1
  printf '%s\n' "$in"
}

# Subtract N days from a date (empty date = today).
_brew_new_days_before() {
  local n="$1" base="${2:-}" out
  if [ -n "$base" ]; then
    out=$(date -j -v-"${n}"d -f "%Y-%m-%d" "$base" +%Y-%m-%d 2>/dev/null) \
      || out=$(date -d "$base - $n days" +%Y-%m-%d 2>/dev/null) || return 1
  else
    out=$(date -u -v-"${n}"d +%Y-%m-%d 2>/dev/null) \
      || out=$(date -u -d "$n days ago" +%Y-%m-%d 2>/dev/null) || return 1
  fi
  printf '%s\n' "$out"
}

# Add N days to a date.
_brew_new_days_after() {
  local n="$1" base="$2" out
  out=$(date -j -v+"${n}"d -f "%Y-%m-%d" "$base" +%Y-%m-%d 2>/dev/null) \
    || out=$(date -d "$base + $n days" +%Y-%m-%d 2>/dev/null) || return 1
  printf '%s\n' "$out"
}

_brew_new_file_mtime() {
  stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$1" 2>/dev/null \
    || date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null \
    || stat -c '%y' "$1" 2>/dev/null | cut -c1-16
}

# Fetch, or refresh, the commit-only shallow mirror of one tap under
# $BREW_NEW_CACHE: --filter=tree:0 skips every tree and blob, --shallow-since
# bounds the history to the window (git deepens or shortens an existing mirror
# to match). Meant to run in the background: on failure it leaves the reason
# in sync.err.$kind and touches sync.failed.$kind for _brew_new_section.
_brew_new_sync() {
  local repo="$1" kind="$2" dir="$BREW_NEW_CACHE/$1.git" branch
  local errf="$BREW_NEW_TMPDIR/sync.err.$2"
  if [ -d "$dir" ]; then
    # A bare --single-branch clone stores no fetch refspec, so name the branch.
    branch=$(git -C "$dir" symbolic-ref --short HEAD 2>>"$errf") \
      && git -C "$dir" fetch -q --shallow-since="$QFROM" origin \
           "+refs/heads/${branch}:refs/heads/${branch}" 2>>"$errf" \
      && return 0
    printf '(delete %s to start over)\n' "$dir" >>"$errf"
  else
    mkdir -p "$BREW_NEW_CACHE" 2>>"$errf" \
      && git clone -q --bare --filter=tree:0 --shallow-since="$QFROM" --single-branch \
           "https://github.com/Homebrew/$repo.git" "$dir" 2>>"$errf" \
      && return 0
    rm -rf "$dir"  # never leave a half clone behind
  fi
  : >"$BREW_NEW_TMPDIR/sync.failed.$kind"
  return 1
}

# NUL-separated "date<TAB>message" records from git log -> "date<TAB>line",
# where line is the first "(new X)" marker line with the marker stripped. The
# marker is the subject of the PR's own commit and sits in the body of the
# merge commit (the PR title); a revert quotes it, and is skipped.
_brew_new_markers() {
  tr '\0' '\036' | awk -v RS=$'\036' -v kind="$1" '
    $0 == "" { next }
    {
      date = substr($0, 1, index($0, "\t") - 1)
      n = split(substr($0, index($0, "\t") + 1), lines, "\n")
      for (i = 1; i <= n; i++) {
        line = lines[i]
        if (index(line, "(new " kind ")") == 0) continue
        sub(/^[ \t]+/, "", line)
        if (line ~ /^Revert/) break
        sub(" *\\(new " kind "\\).*$", "", line)
        print date "\t" line
        break
      }
    }'
}

# Keep only clean "name version" additions. Combined commits such as
# "mysql mysql-server 26.7.0 / mysql@9.7 mysql-client@9.7 9.7.2" mix version
# bumps with additions and cannot be split reliably — every genuine addition in
# one also lands its own per-formula commit, so dropping them loses nothing.
_brew_new_parse() {
  awk -F'\t' -v dbg="${BREW_NEW_DEBUG:-0}" '
    { n = split($2, t, /[ \t]+/) }
    n == 2 && t[1] !~ /[\/,]/ { print $1 "\t" t[1] "\t" t[2]; next }
    dbg == "1" { print "brew-new: skipped ambiguous line: " $2 > "/dev/stderr" }
  '
}

# An item's canonical date is the latest of its marker commits: the moment the
# addition actually landed on the default branch. Resolving it here rather than
# per-window keeps the reported date stable no matter what window was asked for,
# and collapses the squashed/merge pair into one row.
_brew_new_resolve() {
  awk -F'\t' -v from="$FROM" -v to="$TO" '
    { if (!($2 in best) || $1 > best[$2]) { best[$2] = $1; ver[$2] = $3 } }
    END {
      for (n in best)
        if (best[n] >= from && (to == "" || best[n] <= to))
          print best[n] "\t" n "\t" ver[n]
    }
  '
}

# date<TAB>name<TAB>version -> aligned columns, newest first.
_brew_new_render() {
  local kind_flag="$1" d name version desc
  sort -r | while IFS=$'\t' read -r d name version; do
    if [ "$WANT_DESC" = 1 ]; then
      # Strip the "name: " prefix with parameter expansion — names contain
      # characters (@, /, +) that would break an interpolated sed expression.
      desc=$(brew desc "$kind_flag" "$name" 2>/dev/null)
      desc=${desc#"$name: "}
      printf '  %s  %-34s %-16s %s\n' "$d" "$name" "$version" "$desc" | sed 's/[[:space:]]*$//'
    else
      printf '  %s  %-34s %s\n' "$d" "$name" "$version"
    fi
  done
}

_brew_new_section() {
  local title="$1" repo="$2" kind="$3" kind_flag="$4" dir errf body
  local -a range
  dir="$BREW_NEW_CACHE/$repo.git"
  errf="$BREW_NEW_TMPDIR/sync.err.$kind"
  if [ -e "$BREW_NEW_TMPDIR/sync.failed.$kind" ]; then
    printf '==> New %s (unavailable)\n' "$title"
    { grep -v '^[[:space:]]*$' "$errf" 2>/dev/null \
        || echo "could not fetch https://github.com/Homebrew/$repo"; } | tail -3 | sed 's/^/  /'
    FAILED=1
    return 0
  fi
  # Dates are UTC: bound the log in UTC and print UTC dates. Every commit in the
  # mirror is reachable from the default branch, so the marker can be matched
  # anywhere; homebrew-cask's merges are not all on the first-parent chain.
  range=(--since="$QFROM 00:00 +0000")
  [ -n "$QTO" ] && range+=(--until="$QTO 23:59:59 +0000")
  body=$(TZ=UTC git -C "$dir" log -z "${range[@]}" \
           --date=format-local:%Y-%m-%d --format='%cd%x09%B' --grep="(new $kind)" 2>"$errf" \
         | _brew_new_markers "$kind" | _brew_new_parse | _brew_new_resolve | _brew_new_render "$kind_flag") \
    || { printf '==> New %s (unavailable)\n  %s\n' "$title" "$(tail -1 "$errf")"; FAILED=1; return 0; }
  printf '==> New %s\n' "$title"
  printf '%s\n' "${body:-  none}"
  return 0
}

# Names on stdin -> "name: description" lines as `brew desc` prints them, in
# input order. Casks come out as "token: (Display Name) desc"; the display name
# is dropped so both sections read alike.
_brew_new_describe() {
  local kind_flag="$1" strip='' in names out name
  in=$(cat)
  [ -n "$in" ] || return 0
  [ "$kind_flag" = --cask ] && strip='s/^([^:]+): \([^()]*\) /\1: /'
  names=("${(@f)in}")
  # One brew invocation for the whole list: Ruby start-up dominates the cost of
  # each call, so a batch takes well under a second where a per-name loop took
  # several.
  if out=$(brew desc "$kind_flag" "${names[@]}" 2>/dev/null) && [ -n "$out" ]; then
    printf '%s\n' "$out" | sed -E "$strip"
    return 0
  fi
  # One unknown name aborts the whole batch, so fall back to a call per name and
  # print the bare name for whatever brew cannot describe.
  for name in "${names[@]}"; do
    out=$(brew desc "$kind_flag" "$name" 2>/dev/null) && [ -n "$out" ] || out="$name"
    printf '%s\n' "$out" | sed -E "$strip"
  done
}

_brew_new_section_local() {
  local title="$1" stem="$2" kind_flag="$3" before after names
  before="$API_CACHE/${stem}_names.before.txt"
  after="$API_CACHE/${stem}_names.txt"
  if [ ! -r "$before" ] || [ ! -r "$after" ]; then
    printf '==> New %s (unavailable)\n  no cached name lists at %s\n' "$title" "$API_CACHE"
    printf '  (needs Homebrew in API mode, and at least one `brew update`)\n'
    FAILED=1
    return 0
  fi
  names=$(awk 'NR==FNR{a[$0];next} !($0 in a)' "$before" "$after" | grep . | sort)
  printf '==> New %s\n' "$title"
  if [ -n "$names" ]; then
    printf '%s\n' "$names" | _brew_new_describe "$kind_flag"
  else
    printf '  none\n'
  fi
  return 0
}

#==================================================================================
# Main Function
#==================================================================================

_brew_new_run() {
  local DAYS=7 WANT_DESC=0 WANT_FORMULA=1 WANT_CASK=1
  local FROM="" TO="" ON="" MODE="" EXPLICIT_DAYS=0 EXPLICIT_FROM=1
  local FAILED=0 DATE_ARGS=0 QFROM="" QTO="" API_CACHE=""
  local BREW_NEW_CACHE="${BREW_NEW_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/brew-new}"

  while [ $# -gt 0 ]; do
    case "$1" in
      -d|--desc)    WANT_DESC=1 ;;
      -f|--formula) WANT_CASK=0 ;;
      -c|--cask)    WANT_FORMULA=0 ;;
      -h|--help)    _brew_new_usage; return 0 ;;
      -u|--last-update) MODE=local ;;
      --online)     MODE=online ;;
      --on)         [ $# -ge 2 ] || { _brew_new_die "--on needs a date (yyyy-MM-dd)"; return 1; }
                    ON=$(_brew_new_norm_date "$2") || { _brew_new_die "invalid --on date '$2' (expected yyyy-MM-dd)"; return 1; }
                    shift ;;
      --on=*)       ON=$(_brew_new_norm_date "${1#*=}") || { _brew_new_die "invalid --on date '${1#*=}' (expected yyyy-MM-dd)"; return 1; } ;;
      --since)      [ $# -ge 2 ] || { _brew_new_die "--since needs a date (yyyy-MM-dd)"; return 1; }
                    FROM=$(_brew_new_norm_date "$2") || { _brew_new_die "invalid --since date '$2' (expected yyyy-MM-dd)"; return 1; }
                    shift ;;
      --since=*)    FROM=$(_brew_new_norm_date "${1#*=}") || { _brew_new_die "invalid --since date '${1#*=}' (expected yyyy-MM-dd)"; return 1; } ;;
      --from)       [ $# -ge 2 ] || { _brew_new_die "--from needs a date (yyyy-MM-dd)"; return 1; }
                    FROM=$(_brew_new_norm_date "$2") || { _brew_new_die "invalid --from date '$2' (expected yyyy-MM-dd)"; return 1; }
                    shift ;;
      --from=*)     FROM=$(_brew_new_norm_date "${1#*=}") || { _brew_new_die "invalid --from date '${1#*=}' (expected yyyy-MM-dd)"; return 1; } ;;
      --to)         [ $# -ge 2 ] || { _brew_new_die "--to needs a date (yyyy-MM-dd)"; return 1; }
                    TO=$(_brew_new_norm_date "$2") || { _brew_new_die "invalid --to date '$2' (expected yyyy-MM-dd)"; return 1; }
                    shift ;;
      --to=*)       TO=$(_brew_new_norm_date "${1#*=}") || { _brew_new_die "invalid --to date '${1#*=}' (expected yyyy-MM-dd)"; return 1; } ;;
      -*)           _brew_new_die "unknown option $1"; _brew_new_usage >&2; return 1 ;;
      *)            DAYS="$1"; EXPLICIT_DAYS=1 ;;
    esac
    shift
  done

  case "$DAYS" in
    ''|*[!0-9]*) _brew_new_die "days must be a positive integer, got '$DAYS'"; return 1 ;;
  esac

  # --on is a one-day window; it cannot be combined with the other date options.
  if [ -n "$ON" ]; then
    if [ -n "$FROM" ] || [ -n "$TO" ] || [ "$EXPLICIT_DAYS" = 1 ]; then
      _brew_new_die "--on selects a single day; drop --since/--from/--to and the day count"
      return 1
    fi
    FROM="$ON"
    TO="$ON"
  fi

  # Date arguments only mean something to the online engine, so they select it.
  { [ -n "$FROM" ] || [ -n "$TO" ] || [ "$EXPLICIT_DAYS" = 1 ]; } && DATE_ARGS=1
  if [ "$MODE" = local ] && [ "$DATE_ARGS" = 1 ]; then
    _brew_new_die "the local engine reports the gap between your last two updates; it cannot take a date window (drop -u to query GitHub)"
    return 1
  fi
  if [ -z "$MODE" ]; then
    if [ "$DATE_ARGS" = 1 ]; then MODE=online; else MODE=local; fi
  fi

  #--------------------------------------------------------------------------
  # Local engine
  #--------------------------------------------------------------------------
  if [ "$MODE" = local ]; then
    API_CACHE="$(brew --cache 2>/dev/null)/api"
    if [ -r "$API_CACHE/formula_names.before.txt" ]; then
      printf 'New since your last brew update (%s -> %s)\n' \
        "$(_brew_new_file_mtime "$API_CACHE/formula_names.before.txt")" \
        "$(_brew_new_file_mtime "$API_CACHE/formula_names.txt")"
    else
      printf 'New since your last brew update\n'
    fi
    [ "$WANT_FORMULA" = 1 ] && _brew_new_section_local "Formulae" formula --formula
    [ "$WANT_CASK" = 1 ]    && _brew_new_section_local "Casks"    cask    --cask
    return "$FAILED"
  fi

  #--------------------------------------------------------------------------
  # Online engine
  #--------------------------------------------------------------------------
  # --from wins; otherwise count DAYS back from --to, or from today.
  if [ -z "$FROM" ]; then
    EXPLICIT_FROM=0
    FROM=$(_brew_new_days_before "$DAYS" "$TO") || { _brew_new_die "cannot compute start date"; return 1; }
  fi

  # yyyy-MM-dd sorts lexicographically, so string comparison is a date comparison.
  if [ -n "$TO" ] && [[ "$FROM" > "$TO" ]]; then
    _brew_new_die "--from ($FROM) is after --to ($TO)"
    return 1
  fi

  # An addition has two marker commits (the PR's own and the merge) whose dates
  # can straddle midnight, so read wider than asked and resolve each item's
  # canonical date afterwards; otherwise the same item could surface under two
  # adjacent --on days with a different date each time. The same margin keeps
  # the shallow boundary (which git cuts in local time) clear of the window.
  QFROM=$(_brew_new_days_before 2 "$FROM") || { _brew_new_die "cannot compute query start date"; return 1; }
  if [ -n "$TO" ]; then
    QTO=$(_brew_new_days_after 2 "$TO") || { _brew_new_die "cannot compute query end date"; return 1; }
  fi

  _zsh_addons_require git git || { _brew_new_die "git is required for the online engine"; return 1; }

  if [ -n "$ON" ]; then
    printf 'New in Homebrew on %s\n' "$ON"
  elif [ -n "$TO" ]; then
    printf 'New in Homebrew from %s to %s (inclusive)\n' "$FROM" "$TO"
  elif [ "$EXPLICIT_FROM" = 1 ]; then
    printf 'New in Homebrew since %s\n' "$FROM"
  else
    printf 'New in Homebrew since %s (last %s day(s))\n' "$FROM" "$DAYS"
  fi
  # Refresh the mirrors concurrently; each reports failure through a marker file.
  local -a pids=()
  if [ "$WANT_FORMULA" = 1 ]; then _brew_new_sync homebrew-core formula & pids+=($!); fi
  if [ "$WANT_CASK" = 1 ];    then _brew_new_sync homebrew-cask cask    & pids+=($!); fi
  wait "${pids[@]}"
  [ "$WANT_FORMULA" = 1 ] && _brew_new_section "Formulae" homebrew-core formula --formula
  [ "$WANT_CASK" = 1 ]    && _brew_new_section "Casks"    homebrew-cask cask    --cask
  return "$FAILED"
}

brew_new() {
  emulate -L zsh
  setopt pipe_fail
  # the online engine refreshes both mirrors in the background; no job notices
  setopt no_monitor no_notify

  # `brew desc` can trigger an auto-update, and cmd/update.sh rotates
  # *_names.txt -> *_names.before.txt, which would destroy the very window the
  # local engine reports on. Scoped to this call so the shell is unaffected.
  local -x HOMEBREW_NO_AUTO_UPDATE=1

  local BREW_NEW_TMPDIR rc
  BREW_NEW_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/brew-new.XXXXXX") || return 1
  _brew_new_run "$@"
  rc=$?
  rm -rf "$BREW_NEW_TMPDIR"
  return $rc
}

### New Formulae and Casks ###
alias bn="brew_new"  # List formulae and casks newly added to Homebrew (local by default)
