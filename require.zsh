# Lazy Homebrew Dependencies
#
# _zsh_addons_require COMMAND FORMULA
#
# Returns 0 when COMMAND is available, first installing the Homebrew formula
# that provides it if it is not. Modules call this at the point where a
# function actually needs the tool, so sourcing a module costs nothing and
# nothing is installed until it is used. Returns 1 with a message when brew is
# missing or the install fails, so the caller can fall back or report instead
# of running a command that is not there.
#
# The Homebrew formula (yonote-org/tap/zsh-addons) declares the same tools as
# dependencies, so with it this only ever runs when one was removed by hand.

_zsh_addons_require() {
  local cmd="$1" formula="$2" here
  command -v "$cmd" >/dev/null 2>&1 && return 0
  if ! command -v brew >/dev/null 2>&1; then
    print -u2 "zsh-addons: '$cmd' is needed but not installed (Homebrew formula '$formula'), and brew is not available"
    return 1
  fi
  # From the formula install, $formula is a declared dependency of zsh-addons
  # and came with it, so its absence deserves a warning, not a quiet install.
  here="${${(%):-%x}:A:h}"
  if [[ "$here" == */Cellar/zsh-addons/* ]]; then
    print -u2 "zsh-addons: warning: '$cmd' is missing, although the '$formula' formula is a dependency of zsh-addons and was installed with it — installing it again..."
  else
    print -u2 "zsh-addons: '$cmd' is not installed; installing the '$formula' formula, which provides it..."
  fi
  # brew's own output goes to stderr too, so callers capturing stdout stay clean.
  if ! brew install --formula "$formula" >&2; then
    print -u2 "zsh-addons: installing '$formula' failed; '$cmd' is still unavailable"
    return 1
  fi
  rehash
  command -v "$cmd" >/dev/null 2>&1 && return 0
  print -u2 "zsh-addons: '$formula' is installed but '$cmd' is still not found — is $(brew --prefix)/bin on your PATH?"
  return 1
}
