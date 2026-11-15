param([Parameter(Mandatory=$true)][string]$Command)
$ErrorActionPreference = 'Stop'
$labConfig = & (Join-Path $PSScriptRoot 'New-LabSshConfig.ps1')
& ssh -F $labConfig llm-security-lab-vm $Command
if ($LASTEXITCODE -ne 0) { throw "VM command failed with exit code $LASTEXITCODE" }
