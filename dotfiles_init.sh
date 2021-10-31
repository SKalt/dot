#!/usr/bin/env bash
### USAGE: dotfiles_init.sh [-h|--help] [--git-dir <GIT_DIR>]
###                         [--dotfiles-dir <DOTFILES_DIR>]
###                         [--git-remote <GIT_REMOTE>]
###
### set up your dotfiles, roughly following
### https://www.atlassian.com/git/tutorials/dotfiles
###
### ARGS:
###     -h|--help          print this message and exit
###        --git-remote    (required) the git url to use for your dotfiles
###        --git-dir       the directory in which to store the git state of your
###                        dotfiles repo. Default: ~/.dotfiles.git
###        --dotfiles-dir  path in which to keep nonstandard or overloaded
###                        configuration files such as "functions.sh" or
###                        ".gitignore". Default: ~/.dotfiles

# utility functions ############################################################
usage() {
  head -20 "$0" | # print the first 20 lines of this file
  grep -e '^###' | # find the lines that start (`^`) with `###`
  sed 's/^### //g; s/^###//g'; # delete all leading instances of `###`
  # note that $0 is the first elements of the command-line arguments array;
  # it's always the name of the program your invoked.
}

is_empty_string() { test -z "$1"; }
path_exists()     { test -e "$1"; }
is_directory()    { test -d "$1"; }
# $1, $2, etc. are variables that represent the $nth element in a function's
# array of arguments

supports_color() {
  test -t 1 && # stdout must be an interacive terminal
  is_empty_string "${NO_COLOR:-}"; # respect the NO_COLOR environment variable
  # "${var_name:-}" evaluates either to the value of `var_name` or "" if `var_name`
  # is unset
}
red="$(tput setaf 1)"
reset="$(tput sgr0)"

log_error() {
  if (supports_color); then
    for message in "$@"; do echo "${red}ERROR\x1b${reset} $message" >&2; done;
    # ANSI escape codes for red    ^^^^^^^^      ^^^^^^ and resetting the color
    # "$@" is this function's arguments array
    # >&2 redirects stdout (device 1) to stderr (device 2)
  else
    for message in "$@"; do echo "[ERROR] $message" >&2; done;
  fi
}

log_info() {
  if (supports_color); then
    for message in "$@"; do echo "[\x1b[34mINFO\x1b[0m] $message" >&2; done;
    # ANSI escape codes for blue  ^^^^^^^^      ^^^^^^ and resetting the color
  else
    for message in "$@"; do echo "[INFO] $message" >&2; done;
  fi
}

is_git_dir() { git --git-dir="$1" rev-parse; }

# setup functions ##############################################################

initialize_bare_repo() {
  local git_dir="${1:?absolute path to git dir required}"
  local git_remote="${2:?git remote required}"
  # ${variable_name:?message} raises an error with a message if `variable_name`
  # is unset.
  # `local` scopes a variable to just the current function-block.

  log_info "ensuring a git repo is present at $git_dir"
  if ! path_exists "$git_dir"; then mkdir -p "$git_dir"; fi
  if ! is_directory "$git_dir"; then
    log_error "'$git_dir' is not a directory: $(ls -l "$git_dir")"
    # $(command) is subshell interpolation: it runs `command` in a subshell
    # and evaluates to whatever `command` prints to stdout.
    return 1
  fi
  if ! is_git_dir "$git_dir"; then
    log_info "initializing a new bare git directory at $git_dir"
    git init --bare "$git_dir";
  fi

  local current_remote;
  current_remote="$(
    git --git-dir="$git_dir" remote get-url origin 2>/dev/null || true
  )"
  # `2>/dev/null`: redirect any error messages in device 2 (stderr) to the null
  # device, a.k.a /dev/null, a.k.a the void
  # `|| true` if ^this command fails, don't consider the subshell to have failed

  if [ "$current_remote" = "" ]; then
    # the remote hasn't yet been set; set "origin" to point at $git_remote
    log_info "setting '$git_remote' as '$git_dir's remote 'origin'"
    git --git-dir="$git_dir" remote add origin "$git_remote";
    log_info "done poiting '$git_dir's remote 'origin' at '$git_remote'"
    return 0;
  elif [ "$current_remote" = "$git_remote" ]; then
    log_info "'$git_dir' has the correct remote $git_remote"
    return 0;
  else
    log_error \
      "expected remote '${git_remote}'" \
      "actual remote   '${current_remote}'";
    return 1;
  fi
}

ignore_everything() {
  local git_dir="${1:?absolute path to git dir required}"
  local dotfiles_dir="${2:?absolute path to dotfiles dir required}"
  mkdir -p "$dotfiles_dir";
  local excludesfile="$dotfiles_dir/.gitignore"

  log_info "ensuring '$excludesfile' ignores everything"
  if ! path_exists "$excludesfile"; then # if the file doesn't yet exist
    echo "*" > "$excludesfile"; # create the file as just "*", ignoring everything
    # note that `>` truncates a file before writing to it!
  elif ! (grep -qe '^\*$' "$excludesfile"); then # if no line that's just "*" found:
    # still ensure everything is ignored, but don't overwrite any previous rules
    echo "*" >> "$excludesfile"
    # >> appends to a file
  fi
  # use the above gitignore to ignore all files in $HOME
  log_info "ensuring '$git_dir' uses '$excludesfile'"
  git --git-dir="$git_dir" config core.excludesFile "$excludesfile"

  # don't show untracked files in `git status`
  git --git-dir="$git_dir" config --local status.showUntrackedFiles no

  # ensure that the above gitignore is tracked!
  git --git-dir="$git_dir" --work-tree="$HOME" add --force "$excludesfile"
}

create_alias() {
  local git_dir="${1:?absolute path to git dir required}"
  # an alias is a string that your shell expands to another string.
  # shellcheck disable=2139
  local dotfile_alias="alias dotfiles='git --git-dir=$git_dir --work-tree=$HOME'"
  if path_exists "$HOME/.bashrc"; then
    if (grep -qve '^alias dotfiles=' ~/.bashrc); then
     echo "$dotfile_alias" >> "$HOME/.bashrc";
    fi
  fi
  if path_exists "$HOME/.zshrc"; then
    if grep -qve '^alias dotfiles=' ~/.zshrc; then
      echo "$dotfile_alias" >> "$HOME/.zshrc";
    fi
  fi
}

main() {
  local git_dir=$HOME/.dotfiles.git;
  local git_remote;
  while [ -n "${1:-}" ]; do
    case "$1" in
      -h|--help) usage && exit 0;;
      --git-remote=*) git_remote="${1##*=}"; shift;;
      --git-remote) shift; git_remote=$1; shift;;
      --git-dir=*)
          log_info "h"
          git_dir="${1##*=}";
          shift;;
      --git-dir) shift; git_dir=$1; shift;;
      *) usage && exit 1;
    esac
  done

  # configure bash for this shell session:
  set -e # on any error, exit nonzero
  set -u # on any unset variable, exit nonzero
  set -o pipefail
  # ^ if any part of a chain of pipes fails, the entire pipeline fails rather
  # than continuing with empty input from the failed step
  set -o errtrace # retain error traces: what called what

  if is_empty_string "${git_remote:-}"; then
    # read in the git_remote variable from human input
    read -r -p "git url for your remote dotfiles repo: " git_remote
    echo "" >&2; # bump the terminal to a new line
  fi

  log_info "git_dir=$git_dir"
  if is_empty_string "$git_remote"; then
    log_error "missing a git remote";
    return 1;
  fi
  log_info "git_remote=$git_remote"

  initialize_bare_repo "$git_dir" "$git_remote"
  ignore_everything "$git_dir" "${dotfiles_dir:-$HOME/.dotfiles}"
  create_alias "$git_dir"
  log_info "================================ DONE ================================"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
