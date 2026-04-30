#!/usr/bin/env bash
set -u

usage() {
  cat <<'USAGE'
Usage:
  scripts/analyze-sleep-log.sh [--duration SECONDS] [--interval SECONDS] [--gap SECONDS] LOG.csv...

Examples:
  scripts/analyze-sleep-log.sh sleep-test-logs/*.csv
  scripts/analyze-sleep-log.sh --duration 600 --interval 5 sleep-test-logs/lid-closed-off.csv sleep-test-logs/keep-awake-on.csv

The analyzer flags large timestamp gaps. A large gap means the logger did not run
continuously, which usually means the Mac slept or the process was paused.
USAGE
}

duration=600
interval=5
gap=30
logs=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --duration)
      duration="${2:-}"
      shift 2
      ;;
    --interval)
      interval="${2:-}"
      shift 2
      ;;
    --gap)
      gap="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      logs+=("$1")
      shift
      ;;
  esac
done

if [ "${#logs[@]}" -eq 0 ]; then
  echo "Missing LOG.csv input" >&2
  usage >&2
  exit 2
fi

for value in "$duration" "$interval" "$gap"; do
  case "$value" in
    ''|*[!0-9]*)
      echo "--duration, --interval, and --gap must be positive integers" >&2
      exit 2
      ;;
  esac
done

for log in "${logs[@]}"; do
  if [ ! -f "$log" ]; then
    echo "== $log"
    echo "result:       file not found"
    echo
    continue
  fi

  awk -F',' -v file="$log" -v duration="$duration" -v interval="$interval" -v gap="$gap" '
  function verdict(max_gap, assertion_seen) {
    if (max_gap > gap) {
      return "NOT CONTINUOUS"
    }
    if (assertion_seen == 0) {
      return "CONTINUOUS, but Macchiato assertion was never observed"
    }
    return "CONTINUOUS"
  }

  BEGIN {
    samples = 0
    max_gap = 0
    assertion_samples = 0
    sleep_disabled_samples = 0
    running_samples = 0
    scenario = ""
    first_iso = ""
    last_iso = ""
    first_epoch = 0
    last_epoch = 0
  }

  NR == 1 {
    next
  }

  NF >= 8 {
    samples += 1
    scenario = $1
    epoch = $2 + 0
    iso = $3
    delta = $5 + 0

    if (samples == 1) {
      first_epoch = epoch
      first_iso = iso
    }

    if (delta > max_gap) {
      max_gap = delta
    }
    if ($6 == "1") {
      running_samples += 1
    }
    if ($7 == "1") {
      assertion_samples += 1
    }
    if (NF >= 9 && $8 == "1") {
      sleep_disabled_samples += 1
    }

    last_epoch = epoch
    last_iso = iso
  }

  END {
    if (samples == 0) {
      print "== " file
      print "result:       no samples"
      print ""
      exit
    }

    wall = last_epoch - first_epoch
    expected = int(duration / interval)
    expected_min = int(expected * 0.8)

    print "== " file
    print "scenario: " scenario
    print "first sample: " first_iso
    print "last sample:  " last_iso
    print "wall time:    " wall "s"
    print "samples:      " samples " (rough expected for " duration "s at " interval "s interval: " expected ")"
    print "max gap:      " max_gap "s"
    print "app samples:  " running_samples
    print "assertions:   " assertion_samples
    print "sleepDisabled:" sleep_disabled_samples
    print "result:       " verdict(max_gap, assertion_samples)

    if (wall < duration * 0.8) {
      print "note:         log is shorter than the requested test window"
    }
    if (samples < expected_min && max_gap <= gap) {
      print "note:         sample count is lower than expected; check whether the logger was stopped early"
    }
    print ""
  }
  ' "$log"
done
