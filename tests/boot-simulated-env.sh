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

[[ $# == 1 ]] || fail "Expecting just one argument, the ISO image to test"
[[ -f $1 ]] || fail "$1: Does not look like a file that can be the ISO image to test"

readonly ISO_IMAGE=$1

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
  -nographic &
printf '%d' "$!"

