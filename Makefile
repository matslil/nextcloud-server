MAKEFLAGS += -Rr

.SUFFIX:

.ONESHELL:

ucore-minimal-auto.iso: ucore-autoinstall.ign fcos-live.iso | prerequisites
	coreos-installer iso customize --live-ignition ucore-autoinstall.ign --dest-ignition ucore-autoinstall.ign \
		--dest-karg-append "coreos.inst.install_dev=/dev/std" \
		--dest-karg-append "coreos.inst.image_url=ostree-unverified-registry:ghcr.io/ublue-os/ucore-minimal:latest" \
		--dest-karg-append "coreos.inst.ignition_url=file:///ucore-autoinstall.ign" \
		-o ucore-minimal-auto.iso \
		fcos-live.iso

%.ign: %.bu | prerequisites
	cp $< $<.backup
	butane --strict --output=$@ $<

%.bu: %.template core-ssh-key core-login-pwd | prerequisites
	set -x
	jinja2 -D CORE_SSH_KEY="$$(cat core-ssh-key.pub)" -D CORE_PW_HASH="$$(cat core-login-pwd | mkpasswd --method=SHA-512 --stdin)" --outfile "$@" "$<"

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
