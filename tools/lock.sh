#!/bin/bash
# Cross-agent mutex for shared resources (the single Roblox Studio, the main checkout's git index).
#   tools/lock.sh acquire studio <owner> [maxWaitSeconds]   -> waits (polling) until it owns the lock
#   tools/lock.sh release studio <owner>
#   tools/lock.sh status  studio
# A lock older than STALE seconds (default 45 min for studio, 5 min for git) is considered abandoned and broken.
# Exit code 0 = acquired/released, 2 = timed out waiting (call acquire again), 1 = usage error.
set -u
ACTION=${1:-}
NAME=${2:-}
OWNER=${3:-anon}
MAXWAIT=${4:-540}
[ -z "$ACTION" ] || [ -z "$NAME" ] && { echo "usage: lock.sh acquire|release|status <name> <owner> [maxWait]"; exit 1; }
DIR="/tmp/partydash-locks/$NAME.lock"
mkdir -p /tmp/partydash-locks
case "$NAME" in
	studio) STALE=${STALE:-2700} ;;
	*) STALE=${STALE:-300} ;;
esac
now() { date +%s; }
case "$ACTION" in
	acquire)
		start=$(now)
		while true; do
			if mkdir "$DIR" 2>/dev/null; then
				echo "$OWNER $(now)" > "$DIR/owner"
				echo "acquired $NAME by $OWNER"
				exit 0
			fi
			read -r holder since < "$DIR/owner" 2>/dev/null || { holder="?"; since=$(now); }
			if [ "$holder" = "$OWNER" ]; then
				echo "already held by $OWNER"
				exit 0
			fi
			age=$(( $(now) - ${since:-$(now)} ))
			if [ "$age" -gt "$STALE" ]; then
				echo "breaking stale $NAME lock held by $holder for ${age}s"
				rm -rf "$DIR"
				continue
			fi
			if [ $(( $(now) - start )) -ge "$MAXWAIT" ]; then
				echo "still waiting: $NAME held by $holder for ${age}s (call acquire again)"
				exit 2
			fi
			sleep 5
		done
		;;
	release)
		read -r holder since < "$DIR/owner" 2>/dev/null || holder=""
		if [ "$holder" = "$OWNER" ] || [ -z "$holder" ]; then
			rm -rf "$DIR"
			echo "released $NAME"
		else
			echo "not releasing: $NAME is held by $holder, not $OWNER"
		fi
		exit 0
		;;
	status)
		if [ -d "$DIR" ]; then cat "$DIR/owner"; else echo "free"; fi
		;;
	*) echo "unknown action $ACTION"; exit 1 ;;
esac
