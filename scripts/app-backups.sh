#!/bin/sh
# Application-consistent dumps into the restic-backed directory.
# Run daily, BEFORE the restic -> S3 job. Dumps are overwritten each run;
# restic snapshots provide the history.
# Verify container names/DB paths with `docker ps`.
set -eu

DEST="/mnt/backup-and-downloads/backups/backup-apps"
mkdir -p "$DEST"

# DoTheSplit (SQLite): online .backup while the app is running.
sqlite3 "/mnt/ssd-storage/apps-data/dothesplit/data/dts.db" \
  ".backup '$DEST/dothesplit.db'"

# Vikunja: built-in consistent dump (database + files + config in one zip).
# `-p` is the target DIRECTORY, `-f` the filename (overwritten each run).
docker exec custom-app-vikunja-1 /app/vikunja/vikunja dump -p /app/vikunja/files -f vikunja.zip
mv "/mnt/ssd-storage/apps-data/vikunja/files/vikunja.zip" "$DEST/vikunja.zip"

# Memos (SQLite): online .backup for a consistent copy while running.
sqlite3 "/mnt/ssd-storage/apps-data/memos/memos_prod.db" \
  ".backup '$DEST/memos.db'"

# Both .backup lines need sqlite3 on the host; if absent, run it in a small
# sqlite container mounting the same paths.
