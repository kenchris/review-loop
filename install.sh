#!/usr/bin/env bash
# Install the review-loop skills and the `review-loop` command.
#
#   ./install.sh                     copy the skills into ~/.claude/skills and put `review-loop` into ~/.local/bin
#   ./install.sh --for <where>       claude (default): .claude/skills, read by Claude Code and by VS Code (Copilot agent skills too)
#                                    copilot: ~/.copilot/skills, or <project>/.github/skills with --project
#                                    all: both
#   ./install.sh --link              link the skills to this checkout instead of copying (updates with git pull)
#   ./install.sh --project <dir>     install the skills into <dir> (.claude/skills, .github/skills), shared through its repository
#   ./install.sh --bin <dir>         put the command in <dir> instead of ~/.local/bin
#   ./install.sh --no-bin            skills only
#   ./install.sh --add-to-path       also put the launcher folder on your PATH (~/.bashrc, ~/.zshrc, and on Windows your user PATH)
#   ./install.sh --no-path           never touch the PATH or a shell profile (the default asks, in a terminal, when the folder is not on it)
#   ./install.sh --uninstall         remove what this script installed (same options select where)
#
# Needs bash and git (written to avoid bash 4 features; tested on bash 5). On Windows, use Git Bash.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
link=0; project=""; bindir="$HOME/.local/bin"; want_bin=1; uninstall=0; target="claude"; add_path=ask
while [ $# -gt 0 ]; do
  case "$1" in
    --link) link=1 ;;
    --for) shift; target="${1:?--for needs claude, copilot or all}" ;;
    --project) shift; project="${1:?--project needs a directory}" ;;
    --bin) shift; bindir="${1:?--bin needs a directory}" ;;
    --no-bin) want_bin=0 ;;
    --add-to-path) add_path=1 ;;
    --no-path) add_path=0 ;;
    --uninstall) uninstall=1 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

# Puts a folder on the PATH for new shells: a marked line in ~/.bashrc (and ~/.zshrc when it exists), once; on Windows also the user PATH.
add_to_path() {
  local dir="$1" rc
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ "$rc" = "$HOME/.bashrc" ] || [ -f "$rc" ]; then
      if grep -qs '# review-loop' "$rc"; then echo "already in $rc"; else
        printf '\nexport PATH="%s:$PATH"  # review-loop\n' "$dir" >> "$rc"; echo "added to $rc"
      fi
    fi
  done
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*)
      if [ -z "${REVIEW_LOOP_SKIP_WINDOWS_PATH:-}" ] && command -v powershell.exe >/dev/null 2>&1; then
        local win helper
        win="$(cygpath -w "$dir" 2>/dev/null || echo "$dir")"
        helper="$(cygpath -w "$here/skills/pre-pr-review/scripts/add-to-user-path.ps1" 2>/dev/null || echo "$here/skills/pre-pr-review/scripts/add-to-user-path.ps1")"
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$helper" -Dir "$win" || echo "could not update the Windows user PATH: add $win to it yourself"
      fi ;;
  esac
  echo "Open a new terminal for the PATH change to take effect."
}

dests=()
case "$target" in claude|all)
  if [ -n "$project" ]; then dests+=("$project/.claude/skills"); else dests+=("$HOME/.claude/skills"); fi ;; esac
case "$target" in copilot|all)
  if [ -n "$project" ]; then dests+=("$project/.github/skills"); else dests+=("$HOME/.copilot/skills"); fi ;; esac
[ "${#dests[@]}" -gt 0 ] || { echo "--for must be claude, copilot or all" >&2; exit 2; }
skills=(); for d in "$here"/skills/*/; do skills+=("$(basename "$d")"); done

if [ "$uninstall" -eq 1 ]; then
  for dest in "${dests[@]}"; do
    for s in "${skills[@]}"; do
      if [ -e "$dest/$s" ] || [ -L "$dest/$s" ]; then rm -rf "$dest/$s"; echo "removed $dest/$s"; fi
    done
  done
  if [ "$want_bin" -eq 1 ]; then
    for f in "$bindir/review-loop" "$bindir/review-loop.cmd"; do
      if [ -e "$f" ]; then rm -f "$f"; echo "removed $f"; fi
    done
  fi
  exit 0
fi

for dest in "${dests[@]}"; do
  mkdir -p "$dest"
  for s in "${skills[@]}"; do
    rm -rf "$dest/$s"
    if [ "$link" -eq 1 ] && ln -s "$here/skills/$s" "$dest/$s" 2>/dev/null && [ -L "$dest/$s" ]; then
      echo "linked   $dest/$s -> $here/skills/$s"
    else
      if [ "$link" -eq 1 ]; then echo "note: cannot link here, copying $s (re-run after an update)"; fi
      cp -r "$here/skills/$s" "$dest/$s"
      echo "copied   $dest/$s"
    fi
  done
done

if [ "$want_bin" -eq 1 ]; then
  mkdir -p "$bindir"
  # The command stays in this checkout and is found through a small launcher, so a git pull updates it.
  printf '#!/usr/bin/env bash\nexec env REVIEW_LOOP_HOME=%q bash %q "$@"\n' "$here" "$here/bin/review-loop" > "$bindir/review-loop"
  chmod +x "$bindir/review-loop" "$here/bin/review-loop" "$here"/skills/*/scripts/*.sh 2>/dev/null || true
  echo "command  $bindir/review-loop"
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*)
      printf '@echo off\r\nbash "%%~dp0review-loop" %%*\r\n' > "$bindir/review-loop.cmd"
      echo "command  $bindir/review-loop.cmd (for cmd.exe and PowerShell; needs bash on the PATH)" ;;
  esac
  case ":$PATH:" in
    *":$bindir:"*) ;;
    *)
      echo "note: $bindir is not on your PATH"
      do_path=no
      if [ "$add_path" = 1 ]; then do_path=yes
      elif [ "$add_path" = ask ] && [ -t 0 ] && [ -t 1 ]; then
        printf 'Add it to your PATH now (a line in ~/.bashrc, and on Windows your user PATH)? [y/N] '
        read -r answer
        case "$answer" in y|Y|yes|YES) do_path=yes ;; esac
      fi
      if [ "$do_path" = yes ]; then add_to_path "$bindir"; fi ;;
  esac
fi

echo
echo "Done. In a repository: review-loop init (add --vscode for editor tasks), then review-loop doctor."
