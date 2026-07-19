#!/usr/bin/env bash
#
# Application-consistent dumps into the restic-backed directory.
# Run daily, BEFORE the restic -> S3 job. Dumps are overwritten each run;
# restic snapshots provide the history.
# Verify container names/DB paths with `docker ps`.
#
# The SQLite dumps run through a pinned alpine/sqlite container, not the host
# `sqlite3`, a reader must be >= the writer. Keep SQLITE_IMG at or above the
# newest version the apps report (check the file header: `od -An -tu4 -j96 -N4
# --endian=big <db>`).
#
# On any failure it emails a report via `midclt call mail.send` (no recipient
# set, so it goes to the TrueNAS local administrator address) and exits non-zero.
# Success is silent (no daily "OK" noise). Set NOTIFY=0 to disable the email.
#
set -euo pipefail

DEST="/mnt/backup-and-downloads/backups/backup-apps"

# Pinned sqlite for the .backup calls. Bump when the apps outgrow it.
SQLITE_IMG="alpine/sqlite:3.53.2"

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

# Online .backup of a live SQLite DB via the pinned sqlite container.
# The DB's directory is mounted read-write (the .backup API needs it for
# WAL-mode databases; it reads pages under a shared lock and never mutates the
# data). $DEST is mounted separately for the output.
#   $1 = host path to the .db file   $2 = output filename in $DEST
sqlite_backup() {
  local db="$1" out="$2" dir base
  dir="$(dirname "$db")"
  base="$(basename "$db")"
  docker run --rm \
    -v "$dir":/db \
    -v "$DEST":/out \
    "$SQLITE_IMG" \
    "/db/$base" ".backup '/out/$out'" >>"$LOG" 2>&1
}

mkdir -p "$DEST" 2>>"$LOG" || fail "Could not create $DEST."

# DoTheSplit (SQLite): online .backup while the app is running.
sqlite_backup "/mnt/ssd-storage/apps-data/dothesplit/data/dts.db" "dothesplit.db" \
  || fail "DoTheSplit dump failed."

# Vikunja: built-in consistent dump (database + files + config in one zip).
# `-p` is the target DIRECTORY, `-f` the filename (overwritten each run).
docker exec custom-app-vikunja-1 /app/vikunja/vikunja dump \
  -p /app/vikunja/files -f vikunja.zip >>"$LOG" 2>&1 || fail "Vikunja dump failed."
mv "/mnt/ssd-storage/apps-data/vikunja/files/vikunja.zip" "$DEST/vikunja.zip" \
  >>"$LOG" 2>&1 || fail "Vikunja dump move failed."

# Memos (SQLite): online .backup for a consistent copy while running.
sqlite_backup "/mnt/ssd-storage/apps-data/memos/memos_prod.db" "memos.db" \
  || fail "Memos dump failed."
