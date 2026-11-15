$ErrorActionPreference = 'Stop'
$labRoot = Split-Path -Parent $PSScriptRoot
$labKey = Join-Path $env:USERPROFILE '.ssh\id_ed25519_llm_security_lab'
$labRemote = '/home/administrateur/llm-security-lab-deploy'
Push-Location $labRoot
try {
    & node scripts/build-deploy.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Bundle preparation failed.' }
    & ssh -i $labKey -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes administrateur@163.172.105.87 "mkdir -p $labRemote"
    if ($LASTEXITCODE -ne 0) { throw 'SSH connection failed.' }
    & scp -i $labKey -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes artifacts/deploy/provision.sh artifacts/deploy/host-before.sha256 artifacts/deploy/image.sha256 artifacts/deploy/guest-cloud-config.yaml "administrateur@163.172.105.87:$labRemote/"
    if ($LASTEXITCODE -ne 0) { throw 'Bundle upload failed.' }
    & ssh -i $labKey -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes administrateur@163.172.105.87 "cd $labRemote && (sha256sum -c image.sha256 2>/dev/null || (curl -4 -fL --retry 2 -o noble-server-cloudimg-amd64.img https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img && sha256sum -c image.sha256))"
    if ($LASTEXITCODE -ne 0) { throw 'Ubuntu image download or checksum verification failed.' }
    New-Item -ItemType Directory -Path (Join-Path $labRoot 'logs') -Force | Out-Null
    $labLog = Join-Path $labRoot ('logs\deployment-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
    Write-Host 'Enter your sudo password only in this terminal. Creates VM 101, 8 GiB RAM, 4 vCPU (limit 3), 48 GiB disk.'
    & ssh -t -i $labKey -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes administrateur@163.172.105.87 "sudo /bin/bash $labRemote/provision.sh" | Tee-Object -FilePath $labLog
    $labResult = $LASTEXITCODE
    & scp -i $labKey -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes "administrateur@163.172.105.87:$labRemote/guest-host-key.json" artifacts/deploy/guest-host-key.json
    if ($labResult -ne 0) { throw "Deployment needs inspection. Log: $labLog" }
    Write-Host 'VM and services ready. Let Codex complete the verification and Hermes runs.'
} finally { Pop-Location }
