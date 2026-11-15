$ErrorActionPreference = 'Stop'
$labKey = Join-Path $env:USERPROFILE '.ssh\id_ed25519_llm_security_lab'
$labRoot = Split-Path -Parent $PSScriptRoot
$labLogs = Join-Path $labRoot 'logs'
New-Item -ItemType Directory -Path $labLogs -Force | Out-Null
$labLog = Join-Path $labLogs ('host-admin-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
$labRemoteScript = @'
#!/bin/sh
set -eu
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
section() { printf '\n--- %s ---\n' "$1"; }
[ "$(id -u)" = 0 ] || { printf '%s\n' 'Root privileges required.' >&2; exit 1; }
section identity
date -u
hostname
pveversion
section administrative_rights
sudo -l -U administrateur
section load_and_memory
uptime
free -h
vmstat 1 3
section guests
qm list
pct list
pvesh get /cluster/resources --type vm --output-format json
section next_free_vmid
pvesh get /cluster/nextid
section storage
pvesm status
awk '/^[^ \t]/ || /^[ \t]+(path|content|nodes|disable|shared|vgname|thinpool|pool)[ \t]/' /etc/pve/storage.cfg
df -hT
section guest_allocations
for config in /etc/pve/qemu-server/*.conf /etc/pve/lxc/*.conf; do
    [ -f "$config" ] || continue
    printf '\n%s\n' "$config"
    grep -E '^(name|hostname|memory|balloon|cores|sockets|cpu|cpulimit|cpuunits|onboot|ostype|rootfs|mp[0-9]+|scsi[0-9]+|virtio[0-9]+|sata[0-9]+|ide[0-9]+|net[0-9]+|unused[0-9]+):' "$config" || true
    sha256sum "$config"
done
section network_state
ip -brief address
ip route show
ip -4 neighbor show
sysctl net.ipv4.ip_forward
iptables -S
iptables -t nat -S
if command -v nft >/dev/null 2>&1; then nft list tables; fi
if command -v pve-firewall >/dev/null 2>&1; then pve-firewall status || true; fi
section configuration_fingerprints
sha256sum /etc/network/interfaces /etc/pve/storage.cfg
section complete
printf '%s\n' 'LLM_LAB_ADMIN_INVENTORY_COMPLETE'
'@
$labRemoteScript = $labRemoteScript.Replace("`r", '')
$labPayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($labRemoteScript))
$labCommand = "printf '%s' '$labPayload' | base64 -d | sudo /bin/sh"
Write-Host 'Read-only inventory. Enter your sudo password only in this terminal when prompted.'
& ssh -t -i $labKey -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=12 administrateur@163.172.105.87 $labCommand | Tee-Object -FilePath $labLog
if ($LASTEXITCODE -ne 0) { throw "Administrative inventory failed. Partial log: $labLog" }
if (-not (Select-String -LiteralPath $labLog -SimpleMatch 'LLM_LAB_ADMIN_INVENTORY_COMPLETE' -Quiet)) {
    throw "Inventory completion marker missing. Inspect: $labLog"
}
Write-Host "Inventory saved to $labLog"
