$ErrorActionPreference = 'Stop'
$labKey = Join-Path $env:USERPROFILE '.ssh\id_ed25519_llm_security_lab'
$labRemoteScript = @'
#!/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
section() { printf '\n--- %s ---\n' "$1"; }
section identity
date -u
hostname
uname -srm
id
cat /etc/os-release
command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt
section privileges
if command -v sudo >/dev/null 2>&1; then
    sudo -n -l 2>&1
else
    printf '%s\n' 'sudo unavailable'
fi
section proxmox_detection
for tool in pveversion qm pvesh pvesm pct; do command -v "$tool" || true; done
ls -ld /etc/pve 2>/dev/null || true
section cpu
lscpu
section memory
free -h
section filesystems
df -hT
section block_devices
lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS
section network
ip -brief address
ip route show
ip -d link show type bridge
section gpu
if command -v lspci >/dev/null 2>&1; then lspci | grep -Ei 'VGA|3D|Display' || true; fi
section proxmox_inventory
if command -v pveversion >/dev/null 2>&1; then
    if [ "$(id -u)" = 0 ]; then
        pveversion
        qm list
        pct list
        pvesm status
        pvesh get /cluster/resources --type vm --output-format json
    elif command -v sudo >/dev/null 2>&1; then
        sudo -n pveversion
        sudo -n qm list
        sudo -n pct list
        sudo -n pvesm status
        sudo -n pvesh get /cluster/resources --type vm --output-format json
    fi
fi
section end
printf '%s\n' 'Read-only inventory finished. Review permission errors before drawing conclusions.'
'@
$labRemoteScript = $labRemoteScript.Replace("`r", '')
$labPayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($labRemoteScript))
$labCommand = "printf '%s' '$labPayload' | base64 -d | sh"
& ssh -i $labKey -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=12 administrateur@163.172.105.87 $labCommand
if ($LASTEXITCODE -ne 0) { throw 'SSH inventory did not complete.' }
