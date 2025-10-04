MAKEFLAGS += -Rr

# iao: Create bootable ISO
# install: Install machine configuration persistently. Re-use configuration for iso?

SHELL := /bin/bash

SRCPATH := $(abspath $(dir $(shell readlink -e $(lastword $(MAKEFILE_LIST)))))
TMPPATH := $(abspath ./build)
TSTPATH := $(abspath ./test)

TALOS_VER := v1.11.2
TALOS_ARCH := amd64
ISO_NAME := talos-$(TALOS_VER)-$(TALOS_ARCH)-secureboot.iso
HELMVALUES := $(TMPPATH)/nextcloud-values.yaml

vpath boot-image.yaml $(SRCPATH)
vpath install-image.template.yaml $(SRCPATH)
vpath %.yaml $(SRCPATH)/templates
vpath test-% $(SRCPATH)/tests

.ONESHELL:

help:
	@cat <<-EOH
	Builds a Talos Linux ISO image that will deploy Nextcloud.
	
	Syntax:
	   make iso -f <reporoot>/Makefile control_plane_ip=<ip> \
	      admin_email=<admin email> gmail_app_pw=<GMail app pw> \
	      nextcloud_trust_domain=<host/ip> bootdisk=<disk> \
	      datadisks="<disk1> <disk2> ..."
	
	Variables:
	   control_plane_ip       Control plane IP or DNS name for generated Talos config.
	   admin_email            E-mail associated with GMAIL_APP_PW, used for notifications.
	   gmail_app_pw           Application password for the Gmail account ADMIN_EMAIL.
	   nextcloud_trust_domain Domain name or IP of the server to be deployed.
	   bootdisk               Name of boot disk for Talos install, e.g. "/dev/sda".
	   datadisks              Space separated list of additional data disks.
	
	Files created:
	   build/                  Directory with intermediate build files
	   $(ISO_NAME)             Talos Linux ISO to be written to USB stick
	   build/clusterconfig/    Generated Talos machine configuration
	   $(HELMVALUES)           Helm values generated from templates
	EOH

.PHONY: iso

iso: $(ISO_NAME)
	@cat <<-EOI

	==== Build successful ====
	
	Write ISO image to a disk. First check that the disk is the one you intended:
	
	    udevadm info <disk>
	
	Then write image to disk:
	
	    sudo dd if=./$(ISO_NAME) of=<disk> bs=4096k
	EOI

$(ISO_NAME): $(TMPPATH)/talos.id $(TMPPATH)
	curl -L -o "$@" https://factory.talos.dev/image/$$(cat $<)/$(TALOS_VER)/metal-$(TALOS_ARCH)-secureboot.iso

$(TMPPATH)/talos.id: boot-image.yaml $(TMPPATH) | tool.curl
	curl -X POST --data-binary @$< https://factory.talos.dev/schematics | jq --raw-output '.id' > $@

# Stem is the name of the command line tool
# Ensure it can be run, write error message otherwise
.PHONY: tool.%
tool.%:
	@command -v $| >/dev/null || { echo "$|: Command not installed"; exit 1; }

# Stem is the name of the environment variable.
# Ensure this environment variable has been set in the settings file.
# If not, expect the variable to exist and have a value
env.%:
	@key=$*
	val="$($*)"
	[ -n "$$val" ] || { echo "$$key: Setting missing"; exit 1; }
	[ -f values.yaml ] || echo "{}" > values.yaml
	current=$$(yq -r e ".$$key // \"\"" values.yaml)
	if [ "$$current" != "$$val" ]; then
		NEWVAL="$$val" yq -i e ".$$key = strenv(NEWVAL)" values.yaml
		echo "Updated $$key in values.yaml"
	fi

$(TMPPATH) $(TSTPATH):
		mkdir -p "$@"

.PHONY: install

install: $(TMPPATH)/install.yaml
	talosctl apply-config --insecure --nodes $(control_plane_ip) --file $<

$(TMPPATH)/install.yaml: install-image.template.yaml values.yaml $(TMPPATH)/talos.id
	talm template -f values.yaml -f $< --set-string installerImage="factory.talos.dev/installer-secureboot/$(cat $(TMPPATH)/talos.id)/:$(TALOS_VER)"

test: export admin_email = test@example.com
test: export gmail_app_pw = faksepw
test: export nextcloud_trust_domain = 127.0.0.1
test: export bootdisk = /dev/vda
test: export datadisks = /dev/vdb /dev/vdc /dev/vdd /dev/vde
test: export control_plane_ip = 127.0.0.1

test: $(TSTPATH)/test-boot.pid

.PHONY: test-install
test-install: 

$(TSTPATH)/test-boot.pid: test-boot.sh $(ISO_NAME) $(TSTPATH) | env.admin_email env.gmail_app_pw env.nextcloud_trust_domain env.bootdisk env.datadisks env.control_plane_ip
	set -euo pipefail
	ISO_PATH=$$(realpath "$(ISO_NAME)")
	cd $(@D)
	$< "$$PPID" "$@" "$${ISO_PATH}"

$(TMPPATH)/nextcloud-patch.yaml: nextcloud-patch.yaml.template | $(TMPPATH)
	envsubst < $< > $@

$(HELMVALUES): charts/nextcloud-stack/values.yaml
	envsubst < $< > $@

helm-values: $(HELMVALUES)
	@echo "Helm values written to $(HELMVALUES)"

helm-deploy: helm-values
	helm dependency update charts/nextcloud-stack
	helm upgrade --install nextcloud charts/nextcloud-stack -f $(HELMVALUES)

deploy: helm-deploy

