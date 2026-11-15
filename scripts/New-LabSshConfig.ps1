$ErrorActionPreference = 'Stop'
$labRoot = Split-Path -Parent $PSScriptRoot
$labBuild = Join-Path $labRoot 'artifacts\deploy'
$labKey = Join-Path $env:USERPROFILE '.ssh\id_ed25519_llm_security_lab'
$labKeyResult = Join-Path $labBuild 'guest-host-key.json'
if (-not (Test-Path -LiteralPath $labKeyResult)) {
    & scp -i $labKey -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes administrateur@163.172.105.87:/home/administrateur/llm-security-lab-deploy/guest-host-key.json $labKeyResult
    if ($LASTEXITCODE -ne 0) { throw 'Verified VM host key is not available yet. Finish VM provisioning first.' }
}
$labResult = Get-Content -LiteralPath $labKeyResult -Raw | ConvertFrom-Json
if ($labResult.exitcode -ne 0 -or -not $labResult.'out-data') { throw 'Invalid guest-agent response for host key.' }
$labPublic = $labResult.'out-data'.Trim()
if ($labPublic -notmatch '^ssh-ed25519 [A-Za-z0-9+/]+={0,2}( [^\r\n]*)?$') { throw 'Unexpected VM PUBLIC host key format.' }
$labKnown = (Join-Path $labBuild 'known_hosts').Replace('\','/')
$labIdentity = $labKey.Replace('\','/')
$labConfig = Join-Path $labBuild 'ssh_config'
$labUtf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($labKnown, "llm-security-lab-101 $labPublic`n", $labUtf8)
$labConfigText = @"
Host llm-security-lab-vm
    HostName 10.10.10.40
    User labadmin
    IdentityFile "$labIdentity"
    IdentitiesOnly yes
    BatchMode yes
    StrictHostKeyChecking yes
    HostKeyAlias llm-security-lab-101
    UserKnownHostsFile "$labKnown"
    ProxyCommand C:/Windows/System32/OpenSSH/ssh.exe -i "$labIdentity" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -W %h:%p administrateur@163.172.105.87
    ServerAliveInterval 30
    ServerAliveCountMax 3
"@
[IO.File]::WriteAllText($labConfig, $labConfigText + "`n", $labUtf8)
Write-Output $labConfig
