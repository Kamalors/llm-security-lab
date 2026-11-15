$ErrorActionPreference = 'Stop'
$labKey = Join-Path $env:USERPROFILE '.ssh\id_ed25519_llm_security_lab'
$labPublicKey = (Get-Content -LiteralPath ($labKey + '.pub') -Raw).Trim()
if ($labPublicKey -notmatch '^ssh-ed25519 [A-Za-z0-9+/]+={0,2} codex-llm-security-lab$') {
    throw 'Unexpected public key format; no remote changes made.'
}

$labRemoteScript = @'
set -eu
umask 077
if [ -L "$HOME/.ssh" ] || [ -L "$HOME/.ssh/authorized_keys" ]; then
    printf '%s\n' 'SSH path is a symlink; manual inspection required.' >&2
    exit 1
fi
mkdir -p "$HOME/.ssh"
touch "$HOME/.ssh/authorized_keys"
key='__PUBLIC_KEY__'
if ! grep -qxF -- "$key" "$HOME/.ssh/authorized_keys"; then
    printf '\n%s\n' "$key" >> "$HOME/.ssh/authorized_keys"
fi
chmod 700 "$HOME/.ssh"
chmod 600 "$HOME/.ssh/authorized_keys"
printf '%s\n' 'Dedicated public key installed; existing keys preserved.'
'@
$labRemoteScript = $labRemoteScript.Replace('__PUBLIC_KEY__', $labPublicKey).Replace("`r", '')
$labPayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($labRemoteScript))
$labCommand = "printf '%s' '$labPayload' | base64 -d | sh"
Write-Host 'Enter the SSH password only at the terminal prompt. Never paste it into chat.'
& ssh -o StrictHostKeyChecking=yes -o ConnectTimeout=12 -o NumberOfPasswordPrompts=1 administrateur@163.172.105.87 $labCommand
if ($LASTEXITCODE -ne 0) { throw 'SSH bootstrap failed; key-based access has not been verified.' }

& ssh -i $labKey -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=12 administrateur@163.172.105.87 'hostname; id'
if ($LASTEXITCODE -ne 0) { throw 'Public key installation finished, but key-based login verification failed.' }
Write-Host 'Dedicated key-based SSH login verified.'
