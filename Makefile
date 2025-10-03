MAKEFLAGS += -Rr

# iao: Create bootable ISO
# install: Install machine configuration persistently. Re-use configuration for iso?

SHELL := /bin/bash

SRCPATH := $(abspath $(dir $(shell readlink -e $(lastword $(MAKEFILE_LIST)))))
TMPPATH := $(abspath ./build)

TALOS_VER := v1.11.2
TALOS_ARCH := amd64
ISO_NAME := talos-$(TALOS_VER)-$(TALOS_ARCH)-secureboot.iso
HELMVALUES := $(TMPPATH)/nextcloud-values.yaml

vpath boot-image.yaml $(SRCPATH)
vpath *.yaml $(SRCPATH)/templates

.ONESHELL:

.PHONY: help iso prerequisites test helm-values helm-deploy deploy

help:
	@cat <<-EOH
	Builds a Talos Linux ISO image that will deploy Nextcloud.
	
	Syntax:
	   make iso -f <reporoot>/Makefile CONTROL_PLANE_IP=<ip> \
	      ADMIN_EMAIL=<admin email> GMAIL_APP_PW=<GMail app pw> \
	      NEXTCLOUD_TRUST_DOMAIN=<host/ip> BOOTDISK=<disk> \
	      DATADISKS="<disk1> <disk2> ..."
	
	Variables:
	   CONTROL_PLANE_IP       Control plane IP or DNS name for generated Talos config.
	   ADMIN_EMAIL            E-mail associated with GMAIL_APP_PW, used for notifications.
	   GMAIL_APP_PW           Application password for the Gmail account ADMIN_EMAIL.
	   NEXTCLOUD_TRUST_DOMAIN Domain name or IP of the server to be deployed.
	   BOOTDISK               Name of boot disk for Talos install, e.g. "/dev/sda".
	   DATADISKS              Space separated list of additional data disks.
	
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

prerequisites: $(TMPPATH)

# Stem is the name of the command line tool
# Ensure it can be run, write error message otherwise
.PHONY: tool.%
tool.%:
	@command -v $| >/dev/null || { echo "$|: Command not installed"; exit 1; }

# Stem is the name of the environment variable.
# Ensure this environment variable has been set in the settings file.
# If not, expect the variable to exist and have a value
env.%:
	@current_value=$$(yq -r e '.$| // ""' settings.yml)
	if [[ $$current_value != "$($|)" ]]; then
		yq -e -i '.$$| = "$($|)"' settings.yml
	fi
	[[ -n $$current_value ]] || [[ -n $($|) ]] || { echo "$|: Setting missing"; exit 1; }"

$(TMPPATH):
		mkdir -p "$@"

.PHONY: install

install: $(TMPPATH)/controlplane.yaml | prerequisites
	talosctl -n $(CONTROL_PLANE_IP) apply-config --insecure -f $<

$(TMPPATH)/controlplane.yaml talosconfig: $(TMPPATH)/install.yaml | prerequisites
	talosctl gen config nextcloud https://$(CONTROL_PLANE_IP):6443 \
	        --config-patch @$< \
	        --output $(@D)

$(TMPPATH)/install.yaml: install.template.yaml
	jinja2 --outfile $@ -D CONTROL_PLANE_IP="$(CONTROL_PLANE_IP)" -D BOOTDISK="$(BOOTDISK)" -D DATADISKS="$(DATADISKS)" $<

test: export ADMIN_EMAIL = test@example.com
test: export GMAIL_APP_PW = faksepw
test: export NEXTCLOUD_TRUST_DOMAIN = 127.0.0.1
test: export BOOTDISK = /dev/vda
test: export DATADISKS = /dev/vdb /dev/vdc /dev/vdd /dev/vde
test: export CONTROL_PLANE_IP=127.0.0.1
test: $(ISO_NAME)
	$(SRCDIR)/tests/ci-run-tests.sh "$<"

$(TMPPATH)/nextcloud-patch.yaml: nextcloud-patch.yaml.template | $(TMPPATH)
	envsubst < $< > $@

$(HELMVALUES): charts/nextcloud-stack/values.yaml | prerequisites
	envsubst < $< > $@

helm-values: $(HELMVALUES)
	@echo "Helm values written to $(HELMVALUES)"

helm-deploy: helm-values
	helm dependency update charts/nextcloud-stack
	helm upgrade --install nextcloud charts/nextcloud-stack -f $(HELMVALUES)

deploy: helm-deploy

