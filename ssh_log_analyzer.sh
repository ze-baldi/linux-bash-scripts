#!/usr/bin/env bash
# ==============================================================================
# ssh_log_analyzer.sh — Collects and logs SSH login activity summary.
#
# Usage:
#   sudo ./ssh_log.sh              # Default: logs to /var/log/system_health/
#   LOG_DIR="/path" ./system_health_check.sh   # Unprivileged example
# Logs:
#   ${LOG_DIR}/system_health_<YYYY-MM-DD>.log
# Requirements:
#   bash 4+, GNU coreutils
#
# Author: Zach B. | License: MIT | Version: 1.0.0 | Created: 2025-11-22
# ==============================================================================

set -Eeuo pipefail
trap 'log ERROR "Failure at line $LINENO: \"$BASH_COMMAND\" (exit $?)"' ERR

# --- Configuration ---

LOG_DIR="${LOG_DIR:-/var/log/ssh_activity}"  # LOG_DIR="$HOME/cloud-tech/linux/logs/ssh_activity"
LOG_FILE="${LOG_DIR}/ssh_activity_$(date +'%F').log"
LOG_RETENTION_DAYS=30

TOTAL_ATTEMPTS=0
FAILED_ATTEMPTS=0

# --- Functions ---

timestamp() { date +"%F %T"; }

log() {
  local level="$1" msg="$2"
  printf "[%s] %-5s %s\n" "$(timestamp)" "$level" "$msg" >> "$LOG_FILE"
}

ensure_log_dir() {
  [[ -d "$LOG_DIR" ]] || mkdir -p "$LOG_DIR" || { echo "Error: unable to create $LOG_DIR" >&2; exit 1; }
  [[ -w "$LOG_DIR" ]] || { echo "Error: directory not writable: $LOG_DIR" >&2; exit 1; }
}

cleanup_old_logs() {
  find "$LOG_DIR" -type f -name "ssh_activity_*.log" -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
}

count_login_attempts() {
  local log_path="/var/log/auth.log"
  [[ -r "$log_path" ]] || { log ERROR "Cannot read $log_path - insufficient permissions or file missing."; return 1; }

  TOTAL_ATTEMPTS=$(grep -Ec "Failed password|Invalid user|Accepted password|Accepted publickey" "$log_path" || true)
  FAILED_ATTEMPTS=$(grep -Ec "Failed password|Invalid user" "$log_path" || true)
}

get_most_frequent_ips() {
  local log_path="/var/log/auth.log"
  grep -E "Failed password|Invalid user" "$log_path" 2>/dev/null \
  | awk '{for(i=1;i<=NF;i++) if ($i ~ /([0-9]{1,3}\.){3}[0-9]{1,3}/) print $i}' \
  | sort | uniq -c | sort -nr | head -3
}

# --- Main ---

main() {
  ensure_log_dir
  cleanup_old_logs

  log INFO "===== SSH Activity Check Started ====="

  count_login_attempts

  # Count Total & Failed attempts
  log INFO "--- Summary ---"
  log INFO "Total login attempts: ${TOTAL_ATTEMPTS:-0}"
  log INFO "Failed login attempts: ${FAILED_ATTEMPTS:-0}"

  # Get Top 3 most frequent failing IPs
  log INFO "--- Top Failed IPs ---"
  if output=$(get_most_frequent_ips) && [[ -n "$output" ]]; then
    while read -r count ip; do
      log INFO "IP ${ip} → ${count} failed attempts"
    done <<< "$output"
  else
    log INFO "No failed SSH attempts detected."
  fi

  log INFO "===== SSH Activity Check Completed ====="
  echo "SSH activity report logged to: $LOG_FILE"
}

main "$@"