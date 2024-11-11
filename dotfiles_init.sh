#!/usr/bin/env bash
### USAGE: dotfiles_init.sh [-h|--help] [--git-dir <GIT_DIR>]
###                         [--dotfiles-dir <DOTFILES_DIR>]
###                         [--git-remote <GIT_REMOTE>]
###
### Starts managing your `$HOME` directory as a bare git repo. 
### Based on https://www.atlassian.com/git/tutorials/dotfiles.
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
  head -20 "$0" | # print the first 20 lines of this file ("$0")
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

is_installed() {
  local missing=(); # create a bash array
  for cmd in "$@"; do # iterate over each argument to this function
    # "$@" means the arguments $1, $2, ... as an array
    if ! command -v "$cmd" &>/dev/null; then
      log_error "missing \`$cmd\`"
      # watch out! Backticks evaluate their contents as commands unless they're
      # escaped in double-quotes. You don't need to escape backticks inside
      # single quotes, but you can't use "$variable_substitution" either.

      missing+=("$cmd") # append the missing command to the arrary
    fi
  done
  if test "${#missing[@]}" -gt 0; then
    # if the number of missing programs is greater than 0...

    # ("${#variable}" evaluates to the length of the variable iff the variable
    # is a string.  For arrays, "${#array}" evaluates to the lenght of the first
    # element.  To get the length of the array as the array's number of elements,
    # you have to write "${array[@]}")

    return 1 # return 0 means succeed, anything else is a failure code
  fi
}


supports_color() {
  test -t 1 && # stdout (device 1) must be an interacive terminal, a.k.a a tty
  is_empty_string "${NO_COLOR:-}"; # respect the NO_COLOR environment variable
  # "${var_name:-}" evaluates either to the value of `var_name` or "" if `var_name`
  # is unset.
}

# look up ansi color codes
red="$(tput setaf 1)"
blue="$(tput setaf 4)"
reset="$(tput sgr0)"

log_error() {
  if (supports_color); then
    for message in "$@"; do echo "${red}[ERROR]${reset} $message" >&2; done;
    # ANSI escape codes for red     ^^^        ^^^^^  and resetting the color
    # "$@" is this function's arguments array
    # >&2 redirects stdout (device 1) to stderr (device 2)
  else
    for message in "$@"; do echo "[ERROR] $message" >&2; done;
  fi
}

log_info() {
  if (supports_color); then
    for message in "$@"; do echo "${blue}[INFO]${reset} $message" >&2; done;
    # ANSI escape codes for blue  ^^^^^^^^      ^^^^^^ and resetting the color
  else
    for message in "$@"; do echo "[INFO] $message" >&2; done;
  fi
}

is_git_dir() { git --git-dir="$1" rev-parse &>/dev/null; }

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
      "desired remote '${git_remote}'" \
      "pre-existing remote   '${current_remote}'";
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
  echo "$dotfile_alias" > /tmp/dotfile_alias
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

  is_installed git

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
  log_info "to start using your \`dotfiles\` command, start a new login shell"
  log_info "(\`$SHELL -l\`) or evaluate the following in your current terminal:"
  echo
  cat /tmp/dotfile_alias
  echo "dotfiles --help"
  echo;
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # this file ($0) will only be the 0th element in the BASH_SOURCE array when
  # this file is being run directly. It's useful to write bash scripts this way,
  # with only functions and variable definitions at the top level, so you can
  # safely source the file (`source path/to/script`) and try out your
  # functions individually.

  # you may recognize this pattern in other programming languages.

  main "$@"; # accept arguments ("$@") and pass them to the main function
fi
