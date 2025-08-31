MAKEFLAGS += -Rr

KEYBOARD ?= $(shell localectl status | awk -F: '/Layout/ {print $2}' | xargs)

SRCPATH := $(abspath $(dir $(shell readlink -e $(lastword $(MAKEFILE_LIST)))))
TMPPATH := $(abspath ./build)

FCOS_VER := 1.5.0

.SUFFIX:

.ONESHELL:

vpath %.template.bu $(SRCPATH)

# check_envs ADMIN_EMAIL NEXTCLOUD_TRUSTED_DOMAIN GMAIL_APP_PW BOOTDISK DATADISKS
.PHONY: help
help:
	@cat <<-EOF
	Builds an ISO image that will deploy NexusCloud to machine booting it.
	 
	Syntax:
	   make iso -f <reporoot>/Makefile ADMIN_EMAIL=<admin email> GMAIL_APP_PW=<GMail app pw> NEXTCLOUD_TRUST_DOMAIN=<host/ip> BOOTDISK=<disk> DATADISKS="<disk1> <disk2> ..."
	 
	Variables:
	   ADMIN_EMAIL   E-mail associated with GMAIL_APP_PW, where notifications will be sent
	   GMAIL_APP_PW  Application password given to the GMail account ADMIN_EMAIL
	   NEXTCLOUD_TRUST_DOMAIN  Domain name or IP address of the server to be deployed.
	   BOOTDISK      Name of boot disk, i.e. disk with root filesystem, e.g. "/dev/nvme0n1" for first NVME disk.
	   DATADISKS     Name of disks for data storage, separated by space, e.g. "/dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1" for four NVME disks starting with the second. Used to build a RAID-6 ZFS data storage.
	 
	Files created:
	   BUILD         Directory with intermediate build files, only useful to speed up builds
	   ucore-minimal-auto.iso  ISO image to be written to USB stick.
	   core-login-pwd          Password for logging in into "core" admin account.
	   core-ssh-key            SSH private key for logging in into "core" admin account.
	   core-ssh-key.pub        SSH public key associated with core-ssh-key
	   zfs-dataset-key         Key used by ZFS when encrypting datasets. All datasets use the same key.
	EOF

.PHONY: iso
iso: ucore-minimal-auto.iso
	@cat <<-EOF
	 
	==== Build successfull ====
	 
	Write ISO image to a disk. First check that the disk is the one you intended:
	 
	    udevadm info <disk>
	 
	Then write image to disk:
	 
	    sudo dd if=./ucore-minimal-auto.iso of=<disk> bs=4096k
	EOF

ucore-minimal-auto.iso: $(TMPPATH)/setup-server.ign $(TMPPATH)/setup-installer.ign $(TMPPATH)/fcos-live.iso $(MAKEFILE_LIST) | prerequisites
	test -f "$@" && rm "$@"
	coreos-installer iso customize \
		--live-ignition $(TMPPATH)/setup-installer.ign \
		--dest-ignition $(TMPPATH)/setup-server.ign \
		--live-karg-append "coreos.inst.install_dev=$(BOOTDISK)" \
		--live-karg-append "systemd.debug-shell" \
		--live-karg-append "rd.kbd.keymap=$(KEYBOARD)" \
		--dest-karg-append "rd.kbd.keymap=$(KEYBOARD)" \
		--live-karg-append "pci=realloc" \
		--dest-karg-append "pci=realloc" \
		-o ucore-minimal-auto.iso \
		$(TMPPATH)/fcos-live.iso

$(TMPPATH)/%.ign: $(TMPPATH)/%.bu $(MAKEFILE_LIST) | prerequisites
	butane --strict --output=$@ $<
	ignition-validate "$@"

$(TMPPATH)/setup-server.bu: setup-server.template.bu core-ssh-key core-login-pwd zfs-dataset-key $(TMPPATH)/postgresql-pwd $(TMPPATH)/redis-pwd $(TMPPATH)/nextcloud-admin-pwd $(MAKEFILE_LIST) | prerequisites
	jinja2 \
	--strict \
	-D FCOS_VER="$(FCOS_VER)" \
	-D CORE_USER_SSH_PUB="$$(cat core-ssh-key.pub)" \
	-D CORE_USER_PW_HASH="$$(cat core-login-pwd | mkpasswd --method=SHA-512 --stdin)" \
	-D ADMIN_EMAIL="$(ADMIN_EMAIL)" \
	-D GMAIL_APP_PW="$(GMAIL_APP_PW)" \
	-D NEXTCLOUD_ADMIN_PW="$$(cat $(TMPPATH)/nextcloud-admin-pwd)" \
	-D NEXTCLOUD_TRUSTED_DOMAIN="$(NEXTCLOUD_TRUSTED_DOMAIN)" \
	-D POSTGRESQL_PW="$$(cat $(TMPPATH)/postgresql-pwd)" \
	-D REDIS_PW="$$(cat $(TMPPATH)/redis-pwd)" \
	-D DATADISKS="$(DATADISKS)" \
	-D ZFS_DATASET_KEY_B64="$$(base64 -w0 zfs-dataset-key)" \
	--outfile "$@" "$<"

$(TMPPATH)/setup-installer.bu: setup-installer.template.bu core-ssh-key core-login-pwd $(MAKEFILE_LIST) | prerequisites
	jinja2 \
	--strict \
	-D FCOS_VER="$(FCOS_VER)" \
	-D CORE_USER_SSH_PUB="$$(cat core-ssh-key.pub)" \
	-D CORE_USER_PW_HASH="$$(cat core-login-pwd | mkpasswd --method=SHA-512 --stdin)" \
	--outfile "$@" "$<"

core-login-pwd $(TMPPATH)/postgresql-pwd $(TMPPATH)/redis-pwd $(TMPPATH)/nextcloud-admin-pwd: $(MAKEFILE_LIST)
	join_by () { local IFS="$$1"; shift; echo "$$*"; }
	join_by '-' $$(shuf -n4 /usr/share/dict/words) > $@

core-ssh-key core-ssh-key.pub: $(MAKEFILE_LIST) | prerequisites
	test -f "$@" && rm "$@"
	ssh-keygen -q -t ed25519 -f "$@" -N "" -C "NextCloud core user key"

zfs-dataset-key: $(MAKEFILE_LIST)
	dd if=/dev/urandom of="$@" bs=32 count=1

$(TMPPATH)/fcos-live.iso: | prerequisites
	ISO_URL=$$(curl -s "https://builds.coreos.fedoraproject.org/streams/stable.json" | jq -r '.architectures.x86_64.artifacts.metal.formats.iso.disk.location')
	curl -L -o "$@" "$${ISO_URL}"

prerequisites: $(TMPPATH)
	@check_cmds () { for cmd in "$$@"; do command -v $$cmd >/dev/null || { echo "$$cmd: Command not installed: Need the following executables: "$$@""; exit 1; }; done }
	check_cmds butane coreos-installer jq ssh-keygen curl base64 ignition-validate
	check_envs () { for env in "$$@"; do [[ -n "$${!env}" ]] || { echo "$$env: Variable not set"; exit 1; }; done }
	check_envs ADMIN_EMAIL NEXTCLOUD_TRUSTED_DOMAIN GMAIL_APP_PW BOOTDISK DATADISKS

$(TMPPATH):
	mkdir -p "$(TMPPATH)"

