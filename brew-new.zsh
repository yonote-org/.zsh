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
#                    locally (API mode), so this reads the tap history from
#                    GitHub, where every addition carries a line of the form
#                    "name 1.2.3 (new formula)" / "(new cask)".
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

Returns non-zero if a section could not be retrieved, so a failed query is
never reported as an empty one. Set BREW_NEW_DEBUG=1 to log commit lines that
were skipped as ambiguous.
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

# Turn an API error into an actionable message.
_brew_new_explain_err() {
  local msg="$1" reset now
  # GitHub has two throttles. The primary search limit (30/min) is reported by
  # the rate_limit endpoint; the secondary burst limit is not, and its counter
  # can still read plenty of quota while requests are being refused. Don't
  # quote a countdown that does not apply to the block actually in force.
  if printf '%s' "$msg" | grep -qi 'secondary rate limit'; then
    printf 'GitHub secondary (burst) rate limit hit — wait a minute before retrying'
  elif printf '%s' "$msg" | grep -qi 'rate limit'; then
    reset=$(gh api rate_limit --jq '.resources.search.reset' 2>/dev/null)
    now=$(date -u +%s)
    if [ -n "$reset" ] && [ "$reset" -gt "$now" ] 2>/dev/null; then
      printf 'GitHub search rate limit exceeded (30/min) — retry in %ss' "$((reset - now))"
    else
      printf 'GitHub search rate limit exceeded (30/min) — retry in a moment'
    fi
  else
    printf '%s' "$(printf '%s' "$msg" | grep -v '^[[:space:]]*$' | head -2 | tr '\n' ' ')"
  fi
}

# Ask GitHub's commit search for additions in one tap, and emit
# "date<TAB>line" where line is the "(new X)" marker line with the marker
# stripped. The marker is the subject on squashed commits and sits in the body
# on merge commits, so we search the whole message for it.
# Returns 1 and sets SCAN_ERR if the query failed — never an empty result.
_brew_new_scan() {
  local repo="$1" kind="$2" query filter errf outf gh_rc page resp code payload n
  SCAN_ERR=""
  query="repo:Homebrew/$repo \"(new $kind)\" committer-date:>=$QFROM"
  [ -n "$QTO" ] && query="$query committer-date:<=$QTO"
  # GitHub returns committer dates in the committer's own offset, so the
  # leading 10 characters are their local date, not the UTC one. Normalise.
  filter='def utcdate:
      capture("^(?<t>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(\\.[0-9]+)?(?<z>Z|[+-][0-9]{2}:[0-9]{2})$") as $m
      | (($m.t + "Z") | fromdateiso8601) as $e
      | (if $m.z == "Z" then 0
         else (($m.z[1:3] | tonumber) * 3600 + ($m.z[4:6] | tonumber) * 60) as $sec
              | (if ($m.z[0:1] == "-") then -$sec else $sec end)
         end) as $off
      | (($e - $off) | todate)[0:10];
    (if .incomplete_results then "@@INCOMPLETE@@" else empty end),
    (.items[]
    | {d: .commit.committer.date,
       m: (.commit.message | split("\n")
            | map(select(test("\\(new '"$kind"'\\)")) | sub("^[[:space:]]+"; ""))
            | first // "")}
    | select(.m != "" and (.m | test("^Revert") | not))
    | [(.d | utcdate), (.m | sub(" *\\(new '"$kind"'\\).*$"; ""))]
    | @tsv)'
  errf="$BREW_NEW_TMPDIR/err.$kind"

  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    outf="$BREW_NEW_TMPDIR/out.$kind"
    gh api -X GET search/commits -f q="$query" -f per_page=100 \
      --paginate --jq "$filter" >"$outf" 2>"$errf"
    gh_rc=$?
    if [ "$gh_rc" -ne 0 ]; then
      SCAN_ERR=$(_brew_new_explain_err "$(cat "$errf")")
      return 1
    fi
    # HTTP 200 with incomplete_results means the search index timed out and the
    # page is partial or empty. Treating that as a real answer would silently
    # under-report, so fail instead.
    if grep -qx '@@INCOMPLETE@@' "$outf"; then
      SCAN_ERR="GitHub search returned incomplete results (index timeout) — retry"
      return 1
    fi
    cat "$outf"
    return 0
  fi

  # Unauthenticated fallback: 10 searches/minute, so page conservatively.
  # It parses the JSON with jq (gh has jq built in); installed on first use.
  if ! _zsh_addons_require jq jq; then
    SCAN_ERR="jq is required for unauthenticated GitHub queries (install jq, or install and log in to gh)"
    return 1
  fi
  page=1
  while [ "$page" -le 10 ]; do
    resp=$(curl -sSL -w '\n%{http_code}' -H 'Accept: application/vnd.github+json' \
      --data-urlencode "q=$query" --get \
      "https://api.github.com/search/commits?per_page=100&page=$page" 2>"$errf")
    if [ -z "$resp" ]; then
      SCAN_ERR=$(_brew_new_explain_err "$(cat "$errf")")
      [ -n "$SCAN_ERR" ] || SCAN_ERR="network request failed"
      return 1
    fi
    code=${resp##*$'\n'}
    payload=${resp%$'\n'*}
    if [ "$code" != "200" ]; then
      SCAN_ERR=$(_brew_new_explain_err "$(printf '%s' "$payload" | jq -r '.message? // empty' 2>/dev/null)")
      [ -n "$SCAN_ERR" ] || SCAN_ERR="GitHub API returned HTTP $code"
      return 1
    fi
    if [ "$(printf '%s' "$payload" | jq -r '.incomplete_results' 2>/dev/null)" = "true" ]; then
      SCAN_ERR="GitHub search returned incomplete results (index timeout) — retry"
      return 1
    fi
    n=$(printf '%s' "$payload" | jq '.items | length' 2>/dev/null) || n=0
    [ "$n" -gt 0 ] 2>/dev/null || break
    printf '%s' "$payload" | jq -r "$filter"
    [ "$n" -lt 100 ] && break
    page=$((page + 1))
  done
  return 0
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
  local title="$1" repo="$2" kind="$3" kind_flag="$4" raw body count
  raw="$BREW_NEW_TMPDIR/raw.$kind"
  if ! _brew_new_scan "$repo" "$kind" >"$raw"; then
    printf '==> New %s (unavailable)\n  %s\n' "$title" "$SCAN_ERR"
    FAILED=1
    return 0
  fi
  body=$(_brew_new_parse <"$raw" | _brew_new_resolve | _brew_new_render "$kind_flag")
  count=$(printf '%s' "$body" | grep -c .)
  printf '==> New %s\n' "$title"
  printf '%s\n' "${body:-  none}"
  # GitHub's search API caps a query at 1000 results.
  [ "$count" -ge 990 ] && printf '  (note: hit GitHub search result cap — narrow the window)\n'
  return 0
}

# Reproduce brew's own new-formula/cask report with no network at all.
# brew (cmd/update_report/reporter.rb) diffs two plain name lists in its API
# cache and treats every added line as a new package; cmd/update.sh rotates
# *_names.txt to *_names.before.txt on each update. A set difference is used
# here rather than `comm`: the lists are not in `sort` order (locale
# collation), so `comm` silently drops entries.
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
  local SCAN_ERR="" FAILED=0 DATE_ARGS=0 QFROM="" QTO="" API_CACHE=""

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

  # An addition has two marker commits (the squashed one and the merge) whose
  # dates can straddle midnight, so query wider than asked and resolve each
  # item's canonical date afterwards. Without this the same item can surface
  # under two adjacent --on days with a different date each time.
  QFROM=$(_brew_new_days_before 2 "$FROM") || { _brew_new_die "cannot compute query start date"; return 1; }
  if [ -n "$TO" ]; then
    QTO=$(_brew_new_days_after 2 "$TO") || { _brew_new_die "cannot compute query end date"; return 1; }
  fi

  if [ -n "$ON" ]; then
    printf 'New in Homebrew on %s\n' "$ON"
  elif [ -n "$TO" ]; then
    printf 'New in Homebrew from %s to %s (inclusive)\n' "$FROM" "$TO"
  elif [ "$EXPLICIT_FROM" = 1 ]; then
    printf 'New in Homebrew since %s\n' "$FROM"
  else
    printf 'New in Homebrew since %s (last %s day(s))\n' "$FROM" "$DAYS"
  fi
  [ "$WANT_FORMULA" = 1 ] && _brew_new_section "Formulae" homebrew-core formula --formula
  [ "$WANT_CASK" = 1 ]    && _brew_new_section "Casks"    homebrew-cask cask    --cask
  return "$FAILED"
}

brew_new() {
  emulate -L zsh
  setopt pipe_fail

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
