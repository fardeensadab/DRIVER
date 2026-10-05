#!/usr/bin/env bash
# Start DRIVER after a reboot:  bash ~/DRIVER/start-driver.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# VirtualBox can't run VMs while the KVM kernel modules are loaded (they load at boot).
if grep -qE '^kvm_(intel|amd) ' /proc/modules; then
    echo "==> Unloading KVM so VirtualBox can run (needs sudo)"
    sudo modprobe -r kvm_intel kvm_amd kvm 2>/dev/null || true
fi

echo "==> Starting the DRIVER VMs (Vagrant may ask for your sudo password for NFS)"
vagrant up --no-provision || { echo "vagrant up failed - see above"; exit 1; }

echo "==> Waiting for http://localhost:7000 ..."
for _ in $(seq 1 36); do
    code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:7000/ || true)
    if [ "$code" = "200" ]; then
        echo "DRIVER is up:  http://localhost:7000/   (editor: http://localhost:7000/editor/, login admin / admin)"
        exit 0
    fi
    sleep 5
done
echo "Not answering yet after 3 minutes. Give it a few more minutes, or run:  vagrant reload app"
