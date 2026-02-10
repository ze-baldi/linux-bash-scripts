#!/usr/bin/env bash
# =====================================================================
# system_health_report.sh — Collects and logs CPU, memory, and disk usage metrics summary.
#
# Usage:
#   sudo ./system_health_report.sh              # Default: logs to /var/log/system_health/
#   LOG_DIR="/path" ./system_health_report.sh   # Unprivileged example
# Logs:
#   ${LOG_DIR}/system_health_<YYYY-MM-DD>.log
# Requirements:
#   bash 4+, GNU coreutils
#
# Author: Zach B. | License: MIT | Version: 1.0.0 | Created: 2025-11-22
# =====================================================================

set -Eeuo pipefail
trap 'log ERROR "Failure at line $LINENO: \"$BASH_COMMAND\" (exit $?)"' ERR

# --- Configuration ---

LOG_DIR="${LOG_DIR:-"/var/log/system_health"}" 
LOG_FILE="${LOG_DIR}/system_health_$(date +'%F').log"
LOG_RETENTION_DAYS=30

CPU_THRESHOLD=80
MEM_THRESHOLD=85
DISK_THRESHOLD=85

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
  find "$LOG_DIR" -type f -name "system_health_*.log" -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
}

get_cpu_usage() {
  # $8 = idle cpu
  LC_ALL=C top -bn1 | awk '/Cpu\(s\)/ {print int(100 - $8)}'
}

get_memory_usage() {
  free -m | awk '/^Mem:/ {used=$3; total=$2; printf "%d %d %d", used, total, (used * 100 / total)}'
}

get_disk_usage() {
  # Ignore WSL and virtual filesystems
  df -h --output=pcent,target,fstype \
    --exclude-type=tmpfs \
    --exclude-type=devtmpfs \
    --exclude-type=overlay \
    --exclude-type=fuse.snapfuse \
    --exclude-type=rootfs \
  | awk 'NR>1 && !/wsl/ {print $1, $2}'
}

# --- Main ---

main() {
  ensure_log_dir
  cleanup_old_logs

  log INFO "===== System Health Check Started ====="

  # System info
  log INFO "[System]"
  log INFO " Hostname: $(hostname)"
  log INFO " Kernel: $(uname -sr)"
  log INFO " Uptime: $(uptime -p)"

  # CPU usage
  cpu_usage=$(get_cpu_usage)
  log INFO "[CPU] ${cpu_usage}% used"
  (( cpu_usage > CPU_THRESHOLD )) && log WARN "CPU usage exceeds ${CPU_THRESHOLD}%"

  # Memory usage
  read -r used total percent < <(get_memory_usage) || true
  log INFO "[Memory] ${used}MB / ${total}MB (${percent}%) used"
  (( percent > MEM_THRESHOLD )) && log WARN "Memory usage exceeds ${MEM_THRESHOLD}%"

  # Disk usage
  log INFO "[Disk]"
  while read -r pct mount; do
    log INFO " ${mount}: ${pct} used"
    pct="${pct%%%}"
    (( pct > DISK_THRESHOLD )) && log WARN "Disk usage exceeds ${DISK_THRESHOLD}% on ${mount}"
  done < <(get_disk_usage)

  log INFO "===== System Health Check Completed ====="
  echo "System health report logged to: $LOG_FILE"
}

main "$@"
