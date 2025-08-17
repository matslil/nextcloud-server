MAKEFLAGS += -Rr

SRCPATH := $(abspath $(dir $(shell readlink -e $(lastword $(MAKEFILE_LIST)))))
TMPPATH := $(abspath ./build)

.SUFFIX:

.ONESHELL:

vpath ucore-autoinstall.template.bu $(SRCPATH)
vpath ucore-autoinstall.bu 
vpath core-ssh-key $(TMPPATH)
vpath core-login-pwd $(TMPPATH)
vpath ucore-autoinstall.ign $(TMPPATH)

ucore-minimal-auto.iso: $(TMPPATH)/ucore-autoinstall.ign $(TMPPATH)/fcos-live.iso | prerequisites
	test -f "$@" && rm "$@"
	coreos-installer iso customize \
		--live-ignition $(TMPPATH)/ucore-autoinstall.ign \
		--dest-ignition $(TMPPATH)/ucore-autoinstall.ign \
		--dest-karg-append "coreos.inst.install_dev=/dev/std" \
		--dest-karg-append "coreos.inst.image_url=ostree-unverified-registry:ghcr.io/ublue-os/ucore-minimal:latest" \
		--dest-karg-append "coreos.inst.ignition_url=file:///ucore-autoinstall.ign" \
		-o ucore-minimal-auto.iso \
		$(TMPPATH)/fcos-live.iso

$(TMPPATH)/ucore-autoinstall.ign: $(TMPPATH)/ucore-autoinstall.bu | prerequisites
	butane --strict --output=$@ $<

$(TMPPATH)/ucore-autoinstall.bu: ucore-autoinstall.template.bu $(TMPPATH)/core-ssh-key $(TMPPATH)/core-login-pwd $(TMPPATH)/postgresql-pwd $(TMPPATH)/redis-pwd $(TMPPATH)/nextcloud-admin-pwd | prerequisites
	jinja2 -D CORE_USER_SSH_PUB="$$(cat $(TMPPATH)/core-ssh-key.pub)" -D CORE_USER_PW_HASH="$$(cat $(TMPPATH)/core-login-pwd | mkpasswd --method=SHA-512 --stdin)" -D ADMIN_EMAIL="$(ADMIN_EMAIL)" -D GMAIL_APP_PW="$(GMAIL_APP_PW)" -D CERT_FILE_PUB="$(CERT_FILE_PUB)" -D NEXTCLOUD_ADMIN_PW="$$(cat $(TMPPATH)/nextcloud-admin-pwd)" -D NEXTCLOUD_TRUSTED_DOMAIN="$(NEXTCLOUD_TRUSTED_DOMAIN)" -D POSTGRESQL_PW="$$(cat $(TMPPATH)/postgresql-pwd)" -D REDIS_PW="$$(cat $(TMPPATH)/redis-pwd)" --outfile "$@" "$<"

$(TMPPATH)/core-login-pwd $(TMPPATH)/postgresql-pwd $(TMPPATH)/redis-pwd $(TMPPATH)/nextcloud-admin-pwd:
	join_by () { local IFS="$$1"; shift; echo "$$*"; }
	join_by '-' $$(shuf -n4 /usr/share/dict/words) > $@

$(TMPPATH)/core-ssh-key: | prerequisites
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

