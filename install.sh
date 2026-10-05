#!/usr/bin/env bash
# =============================================================================
# DRIVER — one-shot installer for an Ubuntu/Debian x86_64 host
#
# Run from the folder that contains this script (the cloned DRIVER folder):
#
#     bash install.sh
#
# What it does (each step is skipped if already done, so it is safe to re-run):
#   1. Checks the machine (CPU virtualization, RAM, disk, OS)
#   2. Installs VirtualBox, NFS server, git, curl            (needs sudo)
#   3. Installs Vagrant (HashiCorp repo) + vagrant-hostmanager
#   4. Allows DRIVER's 192.168.12.x VM network in VirtualBox  (needs sudo)
#   5. Installs uv, Python 3.8 and Ansible 2.9.27 in ~/driver-venv
#   6. Uses the DRIVER source in this folder (a clone that already has the
#      fixes), or downloads DRIVER 2.0.5 and applies driver-local-fixes.patch
#   7. Runs `vagrant up` (creates and provisions the 3 VMs: 30-90 minutes)
#   8. Checks that http://localhost:7000 answers
#
# Log file: ./install.log
# =============================================================================
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
LOG="$HERE/install.log"
VENV="$HOME/driver-venv"
PATCH="$HERE/driver-local-fixes.patch"
REPO_URL="https://github.com/WorldBank-Transport/DRIVER.git"
REPO_COMMIT="69188882a9e950bc337044054b33b464a868d8a0"   # release 2.0.5 (tip of master)

exec > >(tee -a "$LOG") 2>&1

c_green=$'\e[32m'; c_yellow=$'\e[33m'; c_red=$'\e[31m'; c_bold=$'\e[1m'; c_off=$'\e[0m'
step() { echo; echo "${c_bold}==> $*${c_off}"; }
ok()   { echo "${c_green}    ok:${c_off} $*"; }
warn() { echo "${c_yellow}    warning:${c_off} $*"; }
die()  { echo "${c_red}    ERROR:${c_off} $*"; echo "    (full log: $LOG)"; exit 1; }
trap 'die "command failed on line $LINENO: $BASH_COMMAND"' ERR

# out_has REGEX CMD...  -> true if CMD's output matches REGEX.
# (Avoids "cmd | grep -q" which, under pipefail, can report failure when grep
#  exits early and cmd gets SIGPIPE.)
out_has() { local re="$1" out; shift; out=$("$@" 2>&1 || true); grep -qiE -- "$re" <<<"$out"; }

# Wait while another apt/dpkg (e.g. Ubuntu's automatic updates) holds the locks.
wait_apt() {
    local i=0
    while sudo fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock >/dev/null 2>&1; do
        [ $i -eq 0 ] && echo "    waiting for another package manager (automatic updates?) to finish..."
        i=$((i+1)); [ $i -gt 180 ] && die "apt is still locked after 15 minutes - reboot and run: bash install.sh"
        sleep 5
    done
}
apt_get() { wait_apt; sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 "$@"; }

echo "DRIVER installer started $(date)"

# -----------------------------------------------------------------------------
step "1/8  Checking this machine"
# -----------------------------------------------------------------------------
[ "$(id -u)" -ne 0 ] || die "run this script as your normal user (not with sudo); it asks for sudo when needed."
[ "$(uname -m)" = "x86_64" ] || die "DRIVER's VMs need an x86_64 (Intel/AMD) machine; this is $(uname -m)."
command -v apt-get >/dev/null || die "this script supports Ubuntu/Debian (apt) only."
. /etc/os-release; ok "OS: ${PRETTY_NAME:-unknown}"

VT=$(grep -Ec '(vmx|svm)' /proc/cpuinfo || true)
[ "$VT" -gt 0 ] || die "CPU virtualization (VT-x / AMD-V) is not enabled. Turn it on in your BIOS/UEFI settings and re-run."
ok "CPU virtualization available ($(nproc) cores)"

MEM_GB=$(awk '/MemTotal/{printf "%d", $2/1024/1024}' /proc/meminfo)
if   [ "$MEM_GB" -ge 15 ]; then ok "RAM: ${MEM_GB} GB"; VM_MEM_ENV=()
elif [ "$MEM_GB" -ge 10 ]; then warn "RAM: ${MEM_GB} GB - using smaller VMs (database 1.5 GB, app 3 GB, celery 2.5 GB)"
     VM_MEM_ENV=(DRIVER_DATABASE_MEM=1536 DRIVER_APP_MEM=3072 DRIVER_CELERY_MEM=2560)
else die "only ${MEM_GB} GB RAM; DRIVER's three VMs need at least ~10 GB (16 GB recommended)."; fi

FREE_GB=$(df -Pk "$HOME" | awk 'NR==2{printf "%d", $4/1024/1024}')
[ "$FREE_GB" -ge 25 ] || die "only ${FREE_GB} GB free in your home folder; need about 30 GB."
ok "Free disk: ${FREE_GB} GB"

echo "    sudo is needed for the next steps; you may be asked for your password."
sudo -v

# -----------------------------------------------------------------------------
step "2/8  Installing VirtualBox, NFS server, git, curl"
# -----------------------------------------------------------------------------
apt_get update
apt_get install -y \
    git curl wget gnupg ca-certificates lsb-release mokutil \
    nfs-common nfs-kernel-server \
    gcc make perl "linux-headers-$(uname -r)"
sudo systemctl enable --now nfs-kernel-server >/dev/null 2>&1 || sudo systemctl enable --now nfs-server >/dev/null 2>&1 || true

# Ubuntu 22.04's VirtualBox 6.1 crashes guests ("gurumeditation") on recent
# kernels / Intel 12th-gen+ CPUs. Use Oracle's VirtualBox 7.1 instead.
VBOX_VER=$(VBoxManage --version 2>/dev/null || true)
if [[ ! "$VBOX_VER" =~ ^7\. ]]; then
    echo "    Installing Oracle VirtualBox 7.1 (found: ${VBOX_VER:-none})"
    # Stop every running VirtualBox process first: Oracle's installer refuses to
    # install while VBoxSVC is running (e.g. a crashed VM left behind).
    for vm_id in $(VBoxManage list runningvms 2>/dev/null | sed -E 's/.*\{(.*)\}.*/\1/'); do
        VBoxManage controlvm "$vm_id" poweroff >/dev/null 2>&1 || true
    done
    pkill -f VBoxHeadless 2>/dev/null || true
    pkill -x VirtualBox 2>/dev/null || true
    pkill -x VBoxSVC 2>/dev/null || true
    sleep 3
    pkill -9 -f VBoxHeadless 2>/dev/null || true
    pkill -9 -x VBoxSVC 2>/dev/null || true
    pkill -9 -x VBoxXPCOMIPCD 2>/dev/null || true
    sleep 1
    # stop and remove Ubuntu's 6.1 packages (VM settings/disks are kept)
    sudo systemctl stop virtualbox >/dev/null 2>&1 || true
    sudo modprobe -r vboxnetflt vboxnetadp vboxdrv 2>/dev/null || true
    apt_get remove -y \
        virtualbox virtualbox-qt virtualbox-dkms virtualbox-ext-pack 2>/dev/null || true
    wget -qO- https://www.virtualbox.org/download/oracle_vbox_2016.asc \
        | sudo gpg --dearmor --yes -o /usr/share/keyrings/oracle-virtualbox-2016.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle-virtualbox-2016.gpg] https://download.virtualbox.org/virtualbox/debian $(lsb_release -cs) contrib" \
        | sudo tee /etc/apt/sources.list.d/virtualbox.list >/dev/null
    apt_get update
    # postinst builds the kernel modules and (with Secure Boot) signs them with
    # Ubuntu's MOK key in /var/lib/shim-signed/mok, if that key exists.
    if pidof VBoxSVC >/dev/null 2>&1; then
        die "a VirtualBox process (VBoxSVC) is still running. Close VirtualBox / log out and back in, then run: bash install.sh"
    fi
    apt_get install -y virtualbox-7.1 \
        || apt_get install -y -f
    command -v VBoxManage >/dev/null && [ -x /sbin/vboxconfig ] \
        || die "VirtualBox 7.1 did not install. Run:  sudo apt-get install virtualbox-7.1   and send me its output."
    sudo /sbin/vboxconfig || true
    sudo usermod -aG vboxusers "$USER" || true
fi
command -v VBoxManage >/dev/null || die "VBoxManage (VirtualBox) is not installed."

if ! grep -q '^vboxdrv ' /proc/modules; then
    sudo modprobe vboxdrv 2>/dev/null || true
fi
if ! grep -q '^vboxdrv ' /proc/modules; then
    SB=$(mokutil --sb-state 2>/dev/null || true)
    echo
    echo "${c_red}The VirtualBox kernel module (vboxdrv) is not loaded.${c_off}"
    if grep -qi enabled <<<"$SB"; then
        # Ubuntu signs the DKMS modules with its MOK key automatically; the key
        # just has to be enrolled in the firmware once (needs a reboot).
        if [ -f /var/lib/shim-signed/mok/MOK.der ] && out_has 'already enrolled' mokutil --test-key /var/lib/shim-signed/mok/MOK.der; then
            echo "Secure Boot is ON and the signing key is already enrolled, but vboxdrv still won't load."
            echo "Rebuilding and signing the module, then trying again..."
            sudo /sbin/vboxconfig || true
            sudo modprobe vboxdrv 2>/dev/null && { echo "vboxdrv loaded - run: bash install.sh"; exit 0; }
            echo "Still failing. Please send the output of:  sudo dmesg | grep -i vbox | tail -20"
            exit 1
        fi
        cat <<'EOF2'
Secure Boot is ON, so the VirtualBox module must be signed with a key that
you enroll ONCE. You'll now be asked to pick a temporary password (8-16 chars).
Remember it: you type it again on a blue screen after rebooting.
EOF2
        if [ ! -f /var/lib/shim-signed/mok/MOK.der ]; then
            sudo update-secureboot-policy --new-key
        fi
        sudo mokutil --import /var/lib/shim-signed/mok/MOK.der
        cat <<'EOF2'

Done. Now:
  1. Reboot:   sudo reboot
  2. On the blue "Perform MOK management" screen (press a key quickly if it
     shows a countdown) choose:
       Enroll MOK -> Continue -> Yes -> type the password -> Reboot
  3. After logging in again:   cd ~/DRIVER && bash install.sh
EOF2
    else
        echo "Try: sudo /sbin/vboxconfig   and send the output of: sudo dmesg | grep -i vbox | tail -20"
    fi
    exit 1
fi
ok "VirtualBox $(VBoxManage --version 2>/dev/null) with vboxdrv loaded"

# Linux 6.12+ lets KVM grab the CPU's virtualization at boot, which stops
# VirtualBox from starting VMs (VERR_VMX_IN_VMX_ROOT_MODE / VERR_SVM_IN_USE).
if grep -qE '^kvm_(intel|amd) ' /proc/modules; then
    if pgrep -x qemu-system-x86_64 >/dev/null 2>&1 || pgrep -f 'qemu-system' >/dev/null 2>&1; then
        warn "KVM is in use by another VM (qemu). Stop it, then run: sudo modprobe -r kvm_intel kvm_amd kvm"
    else
        warn "Unloading the KVM kernel modules so VirtualBox can run (until next reboot)."
        sudo modprobe -r kvm_intel 2>/dev/null || true
        sudo modprobe -r kvm_amd 2>/dev/null || true
        sudo modprobe -r kvm 2>/dev/null || true
    fi
fi

# -----------------------------------------------------------------------------
step "3/8  Installing Vagrant and the vagrant-hostmanager plugin"
# -----------------------------------------------------------------------------
if ! command -v vagrant >/dev/null; then
    CODENAME=$(lsb_release -cs)
    # HashiCorp has no repo for some non-LTS/derivative codenames; fall back to the LTS one.
    if ! curl -fsSI "https://apt.releases.hashicorp.com/dists/${CODENAME}/Release" >/dev/null; then
        CODENAME=noble
    fi
    wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${CODENAME} main" \
        | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
    apt_get update
    apt_get install -y vagrant
fi
ok "$(vagrant --version)"
if ! out_has vagrant-hostmanager vagrant plugin list; then
    # gems.hashicorp.com is often unreachable (timeouts, IPv6 issues); the plugin
    # itself lives on rubygems.org, so fall back to that source only.
    vagrant plugin install vagrant-hostmanager \
    || vagrant plugin install vagrant-hostmanager --plugin-clean-sources --plugin-source https://rubygems.org/ \
    || { curl -fsSL -o /tmp/vagrant-hostmanager-1.8.10.gem https://rubygems.org/downloads/vagrant-hostmanager-1.8.10.gem \
         && vagrant plugin install /tmp/vagrant-hostmanager-1.8.10.gem --plugin-clean-sources --plugin-source https://rubygems.org/; } \
    || die "could not install the vagrant-hostmanager plugin (network problem reaching rubygems.org?)"
fi
ok "vagrant-hostmanager plugin installed"

# -----------------------------------------------------------------------------
step "4/8  Allowing DRIVER's 192.168.12.x network in VirtualBox"
# -----------------------------------------------------------------------------
sudo mkdir -p /etc/vbox
if ! grep -qs '192\.168\.12\.0/24' /etc/vbox/networks.conf; then
    echo "* 192.168.12.0/24 192.168.56.0/21" | sudo tee -a /etc/vbox/networks.conf >/dev/null
fi
ok "/etc/vbox/networks.conf: $(tr '\n' ' ' < /etc/vbox/networks.conf)"

if command -v ufw >/dev/null && out_has 'Status: active' sudo ufw status; then
    sudo ufw allow from 192.168.12.0/24 comment 'DRIVER VMs (NFS)' >/dev/null
    ok "ufw firewall: allowed NFS traffic from the DRIVER VMs"
fi

# -----------------------------------------------------------------------------
step "5/8  Installing uv, Python 3.8 and Ansible 2.9.27 (in $VENV)"
# -----------------------------------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"
if ! command -v uv >/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi
ok "$(uv --version)"
if [ ! -x "$VENV/bin/ansible-playbook" ] || ! out_has '^ansible 2\.9\.27' "$VENV/bin/ansible" --version; then
    uv venv --python 3.8 "$VENV"
    VIRTUAL_ENV="$VENV" uv pip install --python "$VENV/bin/python" "ansible==2.9.27"
fi
# shellcheck disable=SC1091
. "$VENV/bin/activate"
export PYTHONWARNINGS="ignore"
ok "$(ansible --version 2>/dev/null | head -1)"

# -----------------------------------------------------------------------------
step "6/8  Checking the DRIVER source (with compatibility fixes)"
# -----------------------------------------------------------------------------
if [ -d "$HERE/deployment/ansible/roles/driver.compat" ] && [ -f "$HERE/Vagrantfile" ]; then
    # Cloned from a repository/branch that already contains the fixes
    ok "DRIVER source with the compatibility fixes is already here"
else
    # Fresh folder: download the original DRIVER 2.0.5 and apply the patch
    [ -f "$PATCH" ] || die "missing $PATCH. Either clone the repository that contains the fixes, or put driver-local-fixes.patch next to install.sh"
    if [ ! -d "$HERE/.git" ]; then
        git init -q "$HERE"
        git -C "$HERE" remote add origin "$REPO_URL"
    fi
    if ! git -C "$HERE" cat-file -e "${REPO_COMMIT}^{commit}" 2>/dev/null; then
        git -C "$HERE" fetch --tags origin master
    fi
    if git -C "$HERE" rev-parse -q --verify refs/heads/local-install-fixes >/dev/null; then
        ok "source already set up (branch local-install-fixes)"
        [ "$(git -C "$HERE" rev-parse --abbrev-ref HEAD)" = "local-install-fixes" ] || git -C "$HERE" checkout -q local-install-fixes
    else
        git -C "$HERE" checkout -q -b local-install-fixes "$REPO_COMMIT"
        git -C "$HERE" -c user.name="DRIVER installer" -c user.email="installer@localhost" am -q --keep-cr "$PATCH" \
            || { git -C "$HERE" am --abort 2>/dev/null || true; die "could not apply driver-local-fixes.patch"; }
        ok "fixes applied as commit: $(git -C "$HERE" log -1 --format='%h %s')"
    fi
fi
# keep local config edits out of git, as the project README recommends
git -C "$HERE" update-index --assume-unchanged deployment/ansible/group_vars/development || true
# empty keystore = skip Android JAR signing (add a real one later, see README)
[ -e "$HERE/gradle/data/driver.keystore" ] || touch "$HERE/gradle/data/driver.keystore"
ok "source ready in $HERE"

# -----------------------------------------------------------------------------
step "7/8  Creating and provisioning the VMs (vagrant up) - this takes a while"
# -----------------------------------------------------------------------------
echo "    Vagrant will ask for your sudo password to set up the NFS shared folders."
echo "    Progress is remembered: if something fails, fix it and run  bash install.sh  again."
mkdir -p .vagrant logs
# A VM that crashed ("gurumeditation"/"aborted" before provisioning) is rebuilt.
for vm in database app celery; do
    state=$(vagrant status "$vm" --machine-readable 2>/dev/null | awk -F, '$3=="state"{print $4}' || true)
    if [ "$state" = "gurumeditation" ] || { [ "$state" = "aborted" ] && [ ! -f ".vagrant/driver-provisioned-$vm" ]; }; then
        warn "$vm VM is in state '$state' - saving its log to logs/ and recreating it"
        log=$(find "$HOME/VirtualBox VMs" -path "*DRIVER_${vm}_*" -name VBox.log 2>/dev/null | head -1 || true)
        [ -n "$log" ] && cp "$log" "logs/VBox-$vm-$(date +%H%M%S).log" || true
        vagrant destroy -f "$vm" || true
        rm -f ".vagrant/driver-provisioned-$vm"
    fi
done
env "${VM_MEM_ENV[@]}" vagrant up --no-provision || {
    vagrant status || true
    die "vagrant up (creating/starting the VMs) failed - see the messages above."
}
# Provision in order (database first). A marker file records each success so a
# re-run continues with the VM that failed instead of starting over.
for vm in database app celery; do
    marker=".vagrant/driver-provisioned-$vm"
    if [ -f "$marker" ]; then ok "$vm VM already provisioned"; continue; fi
    echo; echo "${c_bold}    --- provisioning the $vm VM ---${c_off}"
    if vagrant provision "$vm"; then
        date > "$marker"; ok "$vm VM provisioned"
    else
        die "provisioning the $vm VM failed - see the Ansible output above. Fix the cause and run: bash install.sh"
    fi
done

# -----------------------------------------------------------------------------
step "8/8  Checking that DRIVER answers on http://localhost:7000"
# -----------------------------------------------------------------------------
for _ in $(seq 1 30); do
    code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:7000/ || true)
    [ "$code" = "200" ] && break
    sleep 10
done
if [ "${code:-000}" = "200" ]; then
    ok "web app is up"
else
    warn "http://localhost:7000 answered '${code:-nothing}'. The containers may still be starting; try again in a few minutes."
fi

trap - ERR
cat <<EOF

${c_green}${c_bold}DRIVER is installed.${c_off}

  Web app:        http://localhost:7000/
  Schema editor:  http://localhost:7000/editor/
  Login:          admin / admin

  Everyday commands (run in $HERE after:  source ~/driver-venv/bin/activate):
    vagrant halt      stop the VMs          vagrant up       start them again
    vagrant status    show VM state         vagrant ssh app  log into a VM

  Next steps (geographies, sample data, costs): see DRIVER-INSTALL-NOTES.md
EOF
