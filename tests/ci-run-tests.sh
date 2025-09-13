#!/usr/bin/env bash
set -euo pipefail

# Script intended for CI pipelines.
# Expects ISO image as only parameter.
# Will boot this image and check that NextCloud status responds.

SCRIPT_DIR=$(realpath "$(dirname "$0")")

fail() {
    printf 'ERROR: %s: Aborting\n' "$*"
    exit 1
}

[[ $# == 1 ]] || fail "Expecting just one argument, the ISO image to test"
[[ -f $1 ]] || fail "$1: Does not look like a file that can be the ISO image to test"

readonly ISO_IMAGE=$1

vm_pid=$("$SCRIPT_DIR"/boot-simulated-env.sh "$ISO_IMAGE") || fail "$ISO_IMAGE: Failed to boot ISO image"

# Wait for Nextcloud
for _ in {1..60}; do
  if curl -k --silent --fail https://localhost:8080/status.php >/dev/null; then
    echo "Nextcloud responded successfully"
    kill "$vm_pid" || true
    wait "$vm_pid" || true
    exit 0
  fi
  sleep 10
done

echo "Nextcloud failed to respond"
kill "$vm_pid" || true
wait "$vm_pid" || true
exit 1
