MAKEFLAGS += -Rr

.SUFFIX:

.ONESHELL:

ucore-minimal-auto.iso: ucore-autoinstall.ign fcos-live.iso | prerequisites
	rm "$@"
	coreos-installer iso customize --live-ignition ucore-autoinstall.ign --dest-ignition ucore-autoinstall.ign \
		--dest-karg-append "coreos.inst.install_dev=/dev/std" \
		--dest-karg-append "coreos.inst.image_url=ostree-unverified-registry:ghcr.io/ublue-os/ucore-minimal:latest" \
		--dest-karg-append "coreos.inst.ignition_url=file:///ucore-autoinstall.ign" \
		-o ucore-minimal-auto.iso \
		fcos-live.iso

ucore-autoinstall.ign: ucore-autoinstall.bu | prerequisites
	butane --strict --output=$@ $<

ucore-autoinstall.bu: ucore-autoinstall.template.bu core-ssh-key core-login-pwd | prerequisites
	jinja2 -D CORE_SSH_KEY="$$(cat core-ssh-key.pub)" -D CORE_PW_HASH="$$(cat core-login-pwd | mkpasswd --method=SHA-512 --stdin)" -D ADMIN_EMAIL="$(ADMIN_EMAIL)" -D GMAIL_APP_PW="$(GMAIL_APP_PW)" --outfile "$@" "$<"

core-login-pwd:
	join_by () { local IFS="$$1"; shift; echo "$$*"; }
	join_by '-' $$(shuf -n4 /usr/share/dict/words) > $@

core-ssh-key: | prerequisites
	rm "$@"
	ssh-keygen -q -t ed25519 -f "$@" -N "" -C "NextCloud core user key"

fcos-live.iso: | prerequisites
	ISO_URL=$$(curl -s "https://builds.coreos.fedoraproject.org/streams/stable.json" | jq -r '.architectures.x86_64.artifacts.metal.formats.iso.disk.location')
	curl -L -o "$@" "$${ISO_URL}"

prerequisites:
	check_cmds () { for cmd in "$$@"; do command -v $$cmd >/dev/null || { echo "$$cmd: Command not installed"; exit 1; }; done }
	check_cmds butane coreos-installer jq ssh-keygen curl
	[[ -n "$(ADMIN_EMAIL)" ]] || { echo "ADMIN_EMAIL: Variable not set"; exit 1; }
	[[ -n "$(GMAIL_APP_PW)" ]] || { echo "GMAIL_APP_PW: Variable not set"; exit 1; }

