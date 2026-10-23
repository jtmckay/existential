# A command that must be on PATH, at the version if the line gives one (found in the output
# of `<name> --version`). install cannot know this system's package manager, so it names the
# command for a person to install, and fails.
# A kind defines check and install, each called with the line's name, version and source.
check() { command -v "$1" >/dev/null && { [ -z "$2" ] || "$1" --version 2>&1 | grep -qF "$2"; }; }
install() {
  echo "$1${2:+ $2} is not on PATH: install it, then continue the run" >&2
  return 1
}
