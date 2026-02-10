#!/usr/bin/env bash
# ==============================================================================
# user_session_report — Collects and logs active user sessions summary.
#
# Usage:
#   sudo ./user_session_report.sh              # Default: logs to /var/log/user_sessions/
#   LOG_DIR="/path" ./user_session_report.sh   # Unprivileged example
# Logs:
#   ${LOG_DIR}/user_sessions_<YYYY-MM-DD>.log
# Requirements:
#   bash 4+, GNU coreutils
#
# Author: Zach B. | License: MIT | Version: 1.0.0 | Created: 2025-11-22
# ==============================================================================

set -Eeuo pipefail
trap 'log ERROR "Failure at line $LINENO: \"$BASH_COMMAND\" (exit $?)"' ERR

# --- Configuration ---

LOG_DIR="${LOG_DIR:-"/var/log/user_sessions"}"  # LOG_DIR="$HOME/cloud-tech/linux/logs/user_sessions"
LOG_FILE="${LOG_DIR}/user_sessions_$(date +'%F').log"
LOG_RETENTION_DAYS=30

IDLE_THRESHOLD_MINUTES=60   # highlight users idle >= X minutes

# --- Functions ---

timestamp() { date +"%F %T"; }

log() {
  local level="$1" msg="$2"
  printf "[%s] %-5s %s\n" "$(timestamp)" "$level" "$msg" >> "$LOG_FILE"
}

log_block() {
  local level="$1" 
  while read -r line; do
    log "$level" "$line"
  done
}

ensure_log_dir() {
  [[ -d "$LOG_DIR" ]] || mkdir -p "$LOG_DIR" || { echo "Error: unable to create $LOG_DIR" >&2; exit 1; }
  [[ -w "$LOG_DIR" ]] || { echo "Error: directory not writable: $LOG_DIR" >&2; exit 1; }
}

cleanup_old_logs() {
  find "$LOG_DIR" -type f -name "user_sessions_*.log" -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
}

get_active_sessions() {
  w -h | awk '{printf "%-10s %-8s %-10s %-8s %-20s\n", $1, $2, $3, $5, $8}'
}

summarize_sessions() {
  w -h | awk '{print $1}' | sort | uniq -c | awk '{printf "%-10s %s\n", $2, $1}'
}

flag_idle_users() {
  w -h | awk -v t="$IDLE_THRESHOLD_MINUTES" '
    {
      idle=$5
      if (idle ~ /:/) {
        split(idle,a,":"); mins=a[1]*60+a[2]
      } else if (idle ~ /[0-9]+/) {
        mins=idle
      } else {
        next
      }
      if (mins >= t) 
        printf "%-10s idle %s min\n", $1, mins
    }'
}

# --- Main ---

main() {
  ensure_log_dir
  cleanup_old_logs

  log INFO "===== User Sessions Check Started ====="

  log INFO "----- Active Sessions -----"
  get_active_sessions | log_block INFO
  log INFO "----- Sessions per User -----"
  summarize_sessions | log_block INFO
  log INFO "----- Idle Users (>${IDLE_THRESHOLD_MINUTES}m) -----"
  flag_idle_users | log_block WARN

  local total
  total=$(w -h | wc -l)
  log INFO "Total active sessions: $total"

  log INFO "===== User Sessions Check Completed ====="
  echo "User sessions report logged to: $LOG_FILE"
}

main "$@"
