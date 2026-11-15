$ErrorActionPreference = 'Stop'
$labConfig = & (Join-Path $PSScriptRoot 'New-LabSshConfig.ps1')
Write-Host 'Your demonstration token (displayed only in this terminal):'
& ssh -F $labConfig llm-security-lab-vm "sudo sed -n 's/^LAB_HUMAN_TOKEN=//p' /opt/llm-security-lab/.env"
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the demonstration token in the VM.' }
Write-Host 'Open http://127.0.0.1:8080 and enter the token. Keep this terminal open; Ctrl+C closes the tunnel.'
& ssh -F $labConfig -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8080:127.0.0.1:8080 llm-security-lab-vm
