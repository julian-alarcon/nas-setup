#!/usr/bin/env bash
#
# Application-consistent dumps into the restic-backed directory.
# Run daily, BEFORE the restic -> S3 job. Dumps are overwritten each run;
# restic snapshots provide the history.
# Verify container names/DB paths with `docker ps`.
#
# On any failure it emails a report via `midclt call mail.send` (no recipient
# set, so it goes to the TrueNAS local administrator address) and exits non-zero.
# Success is silent (no daily "OK" noise). Set NOTIFY=0 to disable the email.
#
set -euo pipefail

DEST="/mnt/backup-and-downloads/backups/backup-apps"

# Set NOTIFY=0 to disable the failure email.
NOTIFY="${NOTIFY:-1}"

# --- Failure notification ----------------------------------------------------
# mail.send with no "to" delivers to the TrueNAS local administrator address.
HOST="$(hostname)"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

fail() {
  local msg="$1"
  echo "$msg" >>"$LOG"
  if [[ "${NOTIFY}" == "1" ]]; then
    payload="$(jq -n --arg s "app-backups FAILED on ${HOST}" \
      --rawfile t "$LOG" '{subject: $s, text: $t}')"
    midclt call mail.send "$payload" >/dev/null 2>&1 || true
  fi
  cat "$LOG" >&2
  exit 1
}

mkdir -p "$DEST" 2>>"$LOG" || fail "Could not create $DEST."

# DoTheSplit (SQLite): online .backup while the app is running.
sqlite3 "/mnt/ssd-storage/apps-data/dothesplit/data/dts.db" \
  ".backup '$DEST/dothesplit.db'" >>"$LOG" 2>&1 || fail "DoTheSplit dump failed."

# Vikunja: built-in consistent dump (database + files + config in one zip).
# `-p` is the target DIRECTORY, `-f` the filename (overwritten each run).
docker exec custom-app-vikunja-1 /app/vikunja/vikunja dump \
  -p /app/vikunja/files -f vikunja.zip >>"$LOG" 2>&1 || fail "Vikunja dump failed."
mv "/mnt/ssd-storage/apps-data/vikunja/files/vikunja.zip" "$DEST/vikunja.zip" \
  >>"$LOG" 2>&1 || fail "Vikunja dump move failed."

# Memos (SQLite): online .backup for a consistent copy while running.
sqlite3 "/mnt/ssd-storage/apps-data/memos/memos_prod.db" \
  ".backup '$DEST/memos.db'" >>"$LOG" 2>&1 || fail "Memos dump failed."

# Both .backup lines need sqlite3 on the host; if absent, run it in a small
# sqlite container mounting the same paths.
