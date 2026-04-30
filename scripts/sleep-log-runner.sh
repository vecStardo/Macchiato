#!/usr/bin/env bash
set -u

usage() {
  cat <<'USAGE'
Usage:
  scripts/sleep-log-runner.sh --scenario NAME [--interval SECONDS] [--out FILE]

Examples:
  scripts/sleep-log-runner.sh --scenario lid-closed-off
  scripts/sleep-log-runner.sh --scenario keep-awake-on --interval 5

Leave this script running while you close the lid or wait for idle sleep.
Stop it after reopening the Mac with Ctrl+C.
USAGE
}

scenario=""
interval=5
out=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --scenario)
      scenario="${2:-}"
      shift 2
      ;;
    --interval)
      interval="${2:-}"
      shift 2
      ;;
    --out)
      out="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$scenario" ]; then
  echo "Missing required --scenario NAME" >&2
  usage >&2
  exit 2
fi

case "$interval" in
  ''|*[!0-9]*)
    echo "--interval must be a positive integer" >&2
    exit 2
    ;;
esac

if [ "$interval" -lt 1 ]; then
  echo "--interval must be >= 1" >&2
  exit 2
fi

if [ -z "$out" ]; then
  safe_scenario="$(printf '%s' "$scenario" | tr -c '[:alnum:]_.-' '_')"
  out="sleep-test-logs/${safe_scenario}-$(date +%Y%m%d-%H%M%S).csv"
fi

mkdir -p "$(dirname "$out")"

echo "scenario,epoch,iso8601,elapsed_seconds,delta_seconds,macchiato_running,macchiato_assertion,sleep_disabled,power_source" > "$out"

start_epoch="$(date +%s)"
previous_epoch="$start_epoch"
running=1

stop() {
  running=0
}

trap stop INT TERM

echo "Writing sleep test log: $out"
echo "Scenario: $scenario"
echo "Interval: ${interval}s"
echo "Stop after reopening the Mac with Ctrl+C."

while [ "$running" -eq 1 ]; do
  now_epoch="$(date +%s)"
  iso8601="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  elapsed=$((now_epoch - start_epoch))
  delta=$((now_epoch - previous_epoch))
  previous_epoch="$now_epoch"

  if pgrep -x Macchiato >/dev/null 2>&1; then
    macchiato_running=1
  else
    macchiato_running=0
  fi

  if pmset -g assertions 2>/dev/null | grep -q 'Macchiato is keeping your Mac awake'; then
    macchiato_assertion=1
  else
    macchiato_assertion=0
  fi

  sleep_disabled="$(
    pmset -g live 2>/dev/null |
      awk '/SleepDisabled/ { value = $2 } END { if (value) print value; else print 0 }'
  )"

  power_source="$(
    pmset -g ps 2>/dev/null |
      awk -F"'" '/Now drawing from/ { print $2; exit }'
  )"
  power_source="${power_source:-unknown}"

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$scenario" \
    "$now_epoch" \
    "$iso8601" \
    "$elapsed" \
    "$delta" \
    "$macchiato_running" \
    "$macchiato_assertion" \
    "$sleep_disabled" \
    "$power_source" >> "$out"

  sleep "$interval" &
  wait "$!" 2>/dev/null
done

echo
echo "Stopped. Log saved at: $out"
