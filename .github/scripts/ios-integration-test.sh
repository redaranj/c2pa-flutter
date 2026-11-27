#!/usr/bin/env bash
# Run one integration test file on the iOS simulator in $DEVICE_ID.
#
# On hosted runners `flutter test` intermittently launches the app and then
# waits forever at "Waiting for VM Service port to be available...": the tool
# never sees the VM service announcement in the simulator log. When an
# attempt stalls there, kill it and try again; any other failure is final.
#
# Usage: ios-integration-test.sh <test file> <log file>
set -u

test_file=$1
log_file=$2
attempts=3
attempt_seconds=900
bundle_id=org.guardianproject.c2paExample

for attempt in $(seq 1 "$attempts"); do
  echo "Attempt $attempt of $attempts: $test_file"
  flutter test "$test_file" -d "$DEVICE_ID" --ignore-timeouts -v > "$log_file" 2>&1 &
  test_pid=$!
  ( sleep "$attempt_seconds"; kill "$test_pid" 2>/dev/null ) &
  watchdog_pid=$!

  if wait "$test_pid"; then
    kill "$watchdog_pid" 2>/dev/null
    grep -E '[0-9]+ tests? passed|All tests passed' "$log_file" | tail -3
    exit 0
  fi
  kill "$watchdog_pid" 2>/dev/null

  if tail -5 "$log_file" | grep -q 'Waiting for VM Service port'; then
    echo "Attempt $attempt stalled waiting for the VM service; retrying."
    xcrun simctl terminate "$DEVICE_ID" "$bundle_id" 2>/dev/null || true
    continue
  fi

  tail -150 "$log_file"
  exit 1
done

echo "Every attempt stalled waiting for the VM service."
tail -40 "$log_file"
exit 1
