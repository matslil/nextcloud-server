MAKEFLAGS += -Rr

SHELL := /bin/bash

SRCPATH := $(abspath $(dir $(shell readlink -e $(lastword $(MAKEFILE_LIST)))))
TMPPATH := $(abspath ./build)

TALOS_VER := v1.5.5
TALOS_ARCH := amd64
ISO_NAME := nextcloud-talos.iso

.ONESHELL:

.PHONY: help iso prerequisites test

help:
	@cat <<-EOH
	Builds a Talos Linux ISO image that will deploy Nextcloud.
	
	Syntax:
	   make iso -f <reporoot>/Makefile CONTROL_PLANE_IP=<ip>
	
	Variables:
	   CONTROL_PLANE_IP  Control plane IP or DNS name for generated Talos config.
	
	Files created:
	   build/                  Directory with intermediate build files
	   $(ISO_NAME)             Talos Linux ISO to be written to USB stick
	   build/clusterconfig/    Generated Talos machine configuration
	EOH

iso: $(ISO_NAME)
	@cat <<-EOI

	==== Build successful ====
	
	Write ISO image to a disk. First check that the disk is the one you intended:
	
	    udevadm info <disk>
	
	Then write image to disk:
	
	    sudo dd if=./$(ISO_NAME) of=<disk> bs=4096k
	EOI

$(ISO_NAME): $(TMPPATH)/talos.iso $(TMPPATH)/clusterconfig/controlplane.yaml | prerequisites
	cp $(TMPPATH)/talos.iso $(ISO_NAME)

$(TMPPATH)/clusterconfig/controlplane.yaml: talos/nextcloud-patch.yaml | prerequisites
	talosctl gen config nextcloud https://$(CONTROL_PLANE_IP):6443 \
		--config-patch @talos/nextcloud-patch.yaml \
		--output $(TMPPATH)/clusterconfig

$(TMPPATH)/talos.iso: | prerequisites
	curl -L -o "$@" https://github.com/siderolabs/talos/releases/download/$(TALOS_VER)/talos-$(TALOS_ARCH).iso

prerequisites: $(TMPPATH)
	@check_cmds () { for cmd in "$$@"; do command -v $$cmd >/dev/null || { echo "$$cmd: Command not installed: Need the following executables: $$@"; exit 1; }; done }
	check_cmds talosctl curl
	@check_envs () { for env in "$$@"; do [[ -n "$${!env}" ]] || { echo "$$env: Variable not set"; exit 1; }; done }
	check_envs CONTROL_PLANE_IP

$(TMPPATH):
	mkdir -p "$@"

test: export CONTROL_PLANE_IP=127.0.0.1
test: $(ISO_NAME)
	@echo "No automated tests implemented for Talos ISO build."

