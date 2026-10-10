#!/usr/bin/env bash
# Automatically push the current work state (including untracked files)
# to `wip/<branch name>`.
#
# A backup is made when EITHER of these is true (and MIN_INTERVAL has passed):
#   - the amount of change since the last backup reaches CHANGE_THRESHOLD
#   - MAX_INTERVAL has passed since the last backup and something has changed
#
# To keep polling cheap, every POLL seconds only a lightweight fingerprint of the
# working tree is computed (stat information of modified/untracked files, no file
# contents are read). The full snapshot is taken only when the fingerprint changes.
#
# Notifications: events (success / failure / pending) are written to a status file
# as one JSON object. The VS Code extension in .devcontainer/autosave-notify shows
# them as pop-ups. The script works without the extension.
#
# Env vars:
#   AUTOSAVE_POLL              seconds between change checks              (default: 10)
#   AUTOSAVE_MIN_INTERVAL      never push more often than this, seconds   (default: 30)
#   AUTOSAVE_MAX_INTERVAL      push after this long if anything changed   (default: 300)
#   AUTOSAVE_CHANGE_THRESHOLD  changed lines (added + deleted, a binary file counts
#                              as 1) since the last backup that trigger a push
#                                                                          (default: 50)
#   AUTOSAVE_EXCLUDE_FILE      gitignore-format exclude file
#                              (default: <repo>/.devcontainer/autosave.ignore)
#   AUTOSAVE_STATUS_FILE       where events are written; empty = disabled
#                                                          (default: /tmp/autosave.status)
#   AUTOSAVE_WARN_AFTER        "pending": seconds with unbacked-up changes   (default: 600)
#   AUTOSAVE_WARN_CHANGES      "pending": unbacked-up changed lines          (default: 200)
#   AUTOSAVE_NOTIFY_REPEAT     seconds before the same warning/failure is repeated
#                                                                          (default: 300)
#   AUTOSAVE_ONCE              1 = take one snapshot, push it immediately and exit
#                              (ignores the thresholds; for tests)
POLL="${AUTOSAVE_POLL:-10}"
MIN_INTERVAL="${AUTOSAVE_MIN_INTERVAL:-30}"
MAX_INTERVAL="${AUTOSAVE_MAX_INTERVAL:-300}"
THRESHOLD="${AUTOSAVE_CHANGE_THRESHOLD:-50}"
STATUS_FILE="${AUTOSAVE_STATUS_FILE-/tmp/autosave.status}"
WARN_AFTER="${AUTOSAVE_WARN_AFTER:-600}"
WARN_CHANGES="${AUTOSAVE_WARN_CHANGES:-200}"
NOTIFY_REPEAT="${AUTOSAVE_NOTIFY_REPEAT:-300}"
REPO_DIR="${1:-$(pwd)}"
 
cd "$REPO_DIR" || exit 1
REPO_DIR="$(pwd)"
 
EXCLUDE_FILE="${AUTOSAVE_EXCLUDE_FILE:-$REPO_DIR/.devcontainer/autosave.ignore}"
case "$EXCLUDE_FILE" in
  /*) ;;                                   # absolute path
  *)  EXCLUDE_FILE="$REPO_DIR/$EXCLUDE_FILE" ;;
esac
 
# ---- state -------------------------------------------------------------------
START=$(date +%s)
LAST_TREE=""            # tree of the last successful backup
LAST_PUSH=$START        # time of the last successful backup
LAST_ATTEMPT=$START     # time of the last push attempt (limits retries)
FINGERPRINT=""          # lightweight fingerprint at the last check
CUR_TREE=""             # snapshot taken when the fingerprint last changed
CUR_CHANGES=0           # changed lines of CUR_TREE relative to the last backup (or HEAD)
UNSAVED_SINCE=""        # when the current unbacked-up state was first seen
FAIL_SINCE=""           # set while pushes keep failing
LAST_FAIL_NOTIFY=0      # time of the last "failure" event
LAST_PENDING_NOTIFY=0   # time of the last "pending" event
TREE=""                 # result of snapshot_tree
 
# git with the exclusion file applied. Evaluated on every call, so edits to the
# exclusion file take effect without restarting the script.
gitx() {
  if [ -f "$EXCLUDE_FILE" ]; then
    git -c "core.excludesFile=$EXCLUDE_FILE" "$@"
  else
    git "$@"
  fi
}
 
# Lightweight fingerprint: HEAD, index/exclusion-file timestamps, and the names and
# stat data (mtime, size) of modified, deleted and untracked files. No content is read.
fingerprint() {
  {
    git rev-parse HEAD 2>/dev/null
    stat -c '%y' "$(git rev-parse --git-path index)" "$EXCLUDE_FILE" 2>/dev/null
    gitx ls-files -d --exclude-standard
    gitx ls-files -z -m -o --exclude-standard | xargs -0 -r stat -c '%n %y %s' 2>/dev/null
  } | cksum
}
 
# Full snapshot: a tree of all files, built with a temporary index so that the real
# index, working tree and stash are untouched. Sets TREE.
snapshot_tree() {
  local tmp
  tmp=$(mktemp -u) || return 1
  cp "$(git rev-parse --git-path index)" "$tmp" 2>/dev/null
  TREE=$(
    export GIT_INDEX_FILE="$tmp"
    gitx add -A >/dev/null 2>&1 && git write-tree
  )
  rm -f "$tmp"
  [ -n "$TREE" ]
}
 
# Changed lines between two trees (added + deleted; each binary file counts as 1).
count_changes() {
  git diff --numstat --no-renames "$1" "$2" 2>/dev/null |
    awk '{ if ($1 == "-") n += 1; else n += $1 + $2 } END { print n + 0 }'
}
 
# ---- notifications -----------------------------------------------------------
 
# Make a string safe inside a JSON string (single line, at most 300 chars).
json_escape() {
  printf '%s' "$1" | head -c 300 | tr '\n\r\t' '   ' | tr -d '\000-\037' |
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
 
# emit <event> <branch> <changed lines> <unsaved seconds> [detail]
# Writes the latest event atomically. A failure here never affects the backup.
emit() {
  [ -n "$STATUS_FILE" ] || return 0
  local tmp="$STATUS_FILE.$$"
  printf '{"id":"%s","event":"%s","time":"%s","branch":"%s","changes":%s,"unsaved_seconds":%s,"detail":"%s"}\n' \
    "$(date +%s%N)" "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(json_escape "$2")" \
    "${3:-0}" "${4:-0}" "$(json_escape "${5:-}")" >"$tmp" 2>/dev/null &&
    mv -f "$tmp" "$STATUS_FILE" 2>/dev/null
  rm -f "$tmp" 2>/dev/null
  return 0
}
 
# Warn when changes have been left unbacked-up for too long / grown too large.
# Not used while pushes are failing (the failure event already says so).
warn_pending() {
  local branch="$1" now="$2" age
  [ -z "$FAIL_SINCE" ] || return 0
  [ "$CUR_CHANGES" -gt 0 ] || return 0
  age=$((now - UNSAVED_SINCE))
  if [ "$CUR_CHANGES" -ge "$WARN_CHANGES" ] || [ "$age" -ge "$WARN_AFTER" ]; then
    [ $((now - LAST_PENDING_NOTIFY)) -ge "$NOTIFY_REPEAT" ] || return 0
    emit pending "$branch" "$CUR_CHANGES" "$age"
    LAST_PENDING_NOTIFY=$now
  fi
}
 
# ---- main check --------------------------------------------------------------
 
# One check. $1 = 1 forces a snapshot and an immediate push (AUTOSAVE_ONCE).
# Returns 0 when nothing needed to be done or the push succeeded, 1 when the push failed.
check() {
  local force="${1:-0}" fp branch head_sha base now elapsed sha due=0
  local pushed_changes was_failing push_err
 
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 0
  [ "$branch" = "HEAD" ] && return 0                # detached HEAD is excluded
  head_sha=$(git rev-parse HEAD 2>/dev/null) || return 0
 
  # 1) cheap check: take a full snapshot only when something has changed
  fp=$(fingerprint)
  if [ "$force" = 1 ] || [ "$fp" != "$FINGERPRINT" ]; then
    snapshot_tree || return 0
    CUR_TREE="$TREE"
    base="${LAST_TREE:-$(git rev-parse 'HEAD^{tree}')}"
    CUR_CHANGES=$(count_changes "$base" "$CUR_TREE")
    FINGERPRINT="$fp"
  fi
 
  [ -z "$CUR_TREE" ] && return 0
  if [ "$CUR_TREE" = "$LAST_TREE" ]; then           # nothing new since the last backup
    UNSAVED_SINCE=""
    return 0
  fi
 
  # 2) decide with two axes: amount of change OR elapsed time
  now=$(date +%s)
  [ -z "$UNSAVED_SINCE" ] && UNSAVED_SINCE=$now
  elapsed=$((now - LAST_PUSH))
  if [ "$force" = 1 ]; then
    due=1
  elif [ $((now - LAST_ATTEMPT)) -ge "$MIN_INTERVAL" ] &&
       { [ "$CUR_CHANGES" -ge "$THRESHOLD" ] || [ "$elapsed" -ge "$MAX_INTERVAL" ]; }; then
    due=1
  fi
  if [ "$due" = 0 ]; then
    warn_pending "$branch" "$now"
    return 0
  fi
 
  # 3) push
  LAST_ATTEMPT=$now
  pushed_changes=$CUR_CHANGES
  if [ "$CUR_TREE" = "$(git rev-parse 'HEAD^{tree}')" ]; then
    sha="$head_sha"                                 # no changes: push HEAD as-is
  else
    sha=$(git -c user.name=autosave -c user.email=autosave@localhost \
          commit-tree "$CUR_TREE" -p "$head_sha" -m "autosave: $(date -Is)") || return 0
  fi
 
  if push_err=$(git push origin "$sha:refs/heads/wip/$branch" --force --quiet 2>&1); then
    was_failing="$FAIL_SINCE"
    LAST_TREE="$CUR_TREE"
    LAST_PUSH=$(date +%s)
    CUR_CHANGES=0
    UNSAVED_SINCE=""
    FAIL_SINCE=""
    LAST_FAIL_NOTIFY=0
    # Pushing an unchanged HEAD (e.g. right after start) is not worth a pop-up,
    # unless it is the recovery from failing pushes.
    if [ "$pushed_changes" -gt 0 ] || [ -n "$was_failing" ]; then
      emit success "$branch" "$pushed_changes" 0
    fi
    return 0
  fi
 
  FAIL_SINCE="${FAIL_SINCE:-$now}"
  if [ $((now - LAST_FAIL_NOTIFY)) -ge "$NOTIFY_REPEAT" ]; then
    emit failure "$branch" "$CUR_CHANGES" "$((now - UNSAVED_SINCE))" "$(printf '%s\n' "$push_err" | head -n 1)"
    LAST_FAIL_NOTIFY=$now
  fi
  return 1
}
 
[ -f "$EXCLUDE_FILE" ] || echo "[autosave] exclude file not found: $EXCLUDE_FILE (only .gitignore is applied)" >&2
 
if [ "${AUTOSAVE_ONCE:-0}" = "1" ]; then
  check 1
  exit $?
fi
 
while true; do
  sleep "$POLL"
  check || true
done