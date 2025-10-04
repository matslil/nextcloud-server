#!/usr/bin/env bash
set -euo pipefail

# Boot built ISO image into a simulated environment
# This script can be used directly for interactive use cases,
# but is also used by CI based testing.

# The script will print PID of the running instance if successfull.

# The script expects the built ISO image as parameter

fail() {
    printf 'ERROR: %s: Aborting\n' "$*"
    exit 1
}

[[ $# == 3 ]] || fail "Wrong number of arguments: <PID of caller> <PID FILE> <ISO IMAGE>"

CALLER_PID=$1
readonly CALLER_PID

PIDFILE=$2
readonly PIDFILE

ISO_IMAGE=$3
readonly ISO_IMAGE

[[ -f $ISO_IMAGE ]] || fail "$ISO_IMAGE: Does not look like a file that can be the ISO image to test"
realpath "$PIDFILE" &>  /dev/null || fail "$(dirname "$PIDFILE"): Not a valid path"

# Create root and data disks
qemu-img create -f qcow2 disk0.qcow2 1G
for i in 1 2 3 4; do
    qemu-img create -f qcow2 "disk${i}.qcow2" 20M
done

# Start the VM
qemu-system-x86_64 \
  -m 4096 \
  -boot once=d \
  -drive file="$ISO_IMAGE",media=cdrom \
  -drive file=disk0.qcow2,if=virtio \
  -drive file=disk1.qcow2,if=virtio \
  -drive file=disk2.qcow2,if=virtio \
  -drive file=disk3.qcow2,if=virtio \
  -drive file=disk4.qcow2,if=virtio \
  -netdev user,id=net0,hostfwd=tcp::8080-:443 \
  -device virtio-net-pci,netdev=net0 \
  -daemonize \
  -pidfile "$PIDFILE"

# Terminate VM when caller PID dies
(
    while kill -0 "$CALLER_PID" 2>/dev/null; do
        sleep 1
    done
    if [ -f "$PIDFILE" ]; then
        echo "make has exited, killing QEMU..."
        kill "$(cat "$PIDFILE")" 2>/dev/null || true
        rm -f "$PIDFILE"
    fi
) &

