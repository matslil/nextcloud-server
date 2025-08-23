MAKEFLAGS += -Rr

BOOTDISK := /dev/nvme0n1

DATADISKS := /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1 /dev/nvme4n1

SRCPATH := $(abspath $(dir $(shell readlink -e $(lastword $(MAKEFILE_LIST)))))
TMPPATH := $(abspath ./build)

.SUFFIX:

.ONESHELL:

vpath %.template.bu $(SRCPATH)

ucore-minimal-auto.iso: $(TMPPATH)/setup-server.ign $(TMPPATH)/setup-installer.ign $(TMPPATH)/fcos-live.iso $(MAKEFILE_LIST) | prerequisites
	test -f "$@" && rm "$@"
	coreos-installer iso customize \
		--live-ignition $(TMPPATH)/setup-installer.ign \
		--dest-ignition $(TMPPATH)/setup-server.ign \
		--live-karg-append "coreos.inst.install_dev=$(BOOTDISK)" \
		--live-karg-append "systemd.debug-shell" \
		--live-karg-append "pci=realloc" \
		--dest-karg-append "pci=realloc" \
		-o ucore-minimal-auto.iso \
		$(TMPPATH)/fcos-live.iso

$(TMPPATH)/%.ign: $(TMPPATH)/%.bu $(MAKEFILE_LIST) | prerequisites
	butane --strict --output=$@ $<

$(TMPPATH)/setup-server.bu: setup-server.template.bu $(TMPPATH)/core-ssh-key $(TMPPATH)/core-login-pwd $(TMPPATH)/postgresql-pwd $(TMPPATH)/redis-pwd $(TMPPATH)/nextcloud-admin-pwd $(MAKEFILE_LIST) | prerequisites
	jinja2 \
	-D CORE_USER_SSH_PUB="$$(cat $(TMPPATH)/core-ssh-key.pub)" \
	-D CORE_USER_PW_HASH="$$(cat $(TMPPATH)/core-login-pwd | mkpasswd --method=SHA-512 --stdin)" \
	-D ADMIN_EMAIL="$(ADMIN_EMAIL)" \
	-D GMAIL_APP_PW="$(GMAIL_APP_PW)" \
	-D CERT_FILE_PUB="$(CERT_FILE_PUB)" \
	-D NEXTCLOUD_ADMIN_PW="$$(cat $(TMPPATH)/nextcloud-admin-pwd)" \
	-D NEXTCLOUD_TRUSTED_DOMAIN="$(NEXTCLOUD_TRUSTED_DOMAIN)" \
	-D POSTGRESQL_PW="$$(cat $(TMPPATH)/postgresql-pwd)" \
	-D REDIS_PW="$$(cat $(TMPPATH)/redis-pwd)" \
	-D DATADISKS="$(DATADISKS)" \
	--outfile "$@" "$<"

$(TMPPATH)/setup-installer.bu: setup-installer.template.bu $(TMPPATH)/core-ssh-key $(TMPPATH)/core-login-pwd $(MAKEFILE_LIST) | prerequisites
	jinja2 \
	-D CORE_USER_SSH_PUB="$$(cat $(TMPPATH)/core-ssh-key.pub)" \
	-D CORE_USER_PW_HASH="$$(cat $(TMPPATH)/core-login-pwd | mkpasswd --method=SHA-512 --stdin)" \
	-D DATADISKS="$(DATADISKS)" \
	--outfile "$@" "$<"

$(TMPPATH)/core-login-pwd $(TMPPATH)/postgresql-pwd $(TMPPATH)/redis-pwd $(TMPPATH)/nextcloud-admin-pwd: $(MAKEFILE_LIST)
	join_by () { local IFS="$$1"; shift; echo "$$*"; }
	join_by '-' $$(shuf -n4 /usr/share/dict/words) > $@

$(TMPPATH)/core-ssh-key: $(MAKEFILE_LIST) | prerequisites
	test -f "$@" && rm "$@"
	ssh-keygen -q -t ed25519 -f "$@" -N "" -C "NextCloud core user key"

$(TMPPATH)/fcos-live.iso: | prerequisites
	ISO_URL=$$(curl -s "https://builds.coreos.fedoraproject.org/streams/stable.json" | jq -r '.architectures.x86_64.artifacts.metal.formats.iso.disk.location')
	curl -L -o "$@" "$${ISO_URL}"

prerequisites:
	check_cmds () { for cmd in "$$@"; do command -v $$cmd >/dev/null || { echo "$$cmd: Command not installed"; exit 1; }; done }
	check_cmds butane coreos-installer jq ssh-keygen curl
	[[ -n "$(ADMIN_EMAIL)" ]] || { echo "ADMIN_EMAIL: Variable not set"; exit 1; }
	[[ -n "$(CERT_FILE_PUB)" ]] || { echo "CERT_FILE_PUB: Variable not set"; exit 1; }
	[[ -n "$(NEXTCLOUD_TRUSTED_DOMAIN)" ]] || { echo "NEXTCLOUD_TRUSTED_DOMAIN: Variable not set"; exit 1; }
	[[ -n "$(GMAIL_APP_PW)" ]] || { echo "GMAIL_APP_PW: Variable not set"; exit1; }

	mkdir -p "$(TMPPATH)"

