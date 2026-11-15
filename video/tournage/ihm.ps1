# Filme l'IHM web du labo : tunnel SSH, code à usage unique, puis ihm.mjs.
# powershell -File video/tournage/ihm.ps1 -Actions video/tournage/ihm-essai.json -Sortie video/captures/essai-ihm
# Le jeton est lu par SSH, reste en mémoire et n'est jamais affiché ; seul le code (une minute, un seul usage) part vers Edge.
param([Parameter(Mandatory)][string]$Actions, [Parameter(Mandatory)][string]$Sortie)
$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path "$PSScriptRoot\..\..").Path
$Port = 18080   # 8080 est le port local de la fenêtre de démonstration
function PortOuvert { [bool]([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() | Where-Object { $_.Port -eq $Port }) }
if (PortOuvert) { throw "Le port local $Port est déjà pris." }
$tunnel = Start-Process ssh -WindowStyle Hidden -PassThru -ArgumentList "-F automation/ssh_config -N -L ${Port}:127.0.0.1:8080 -o ExitOnForwardFailure=yes llm-lab"
try {
    for ($i = 0; $i -lt 50 -and -not $tunnel.HasExited -and -not (PortOuvert); $i++) { Start-Sleep -Milliseconds 300 }
    if (-not (PortOuvert)) { throw 'Le tunnel SSH vers le labo ne s''ouvre pas.' }
    $jeton = & ssh -n -F automation/ssh_config -o ConnectTimeout=8 llm-lab "sed -n 's/^LAB_HUMAN_TOKEN=//p' /opt/llm-security-lab/.env" 2>$null | Select-Object -Last 1
    if ("$jeton" -notmatch '^[0-9a-f]{32,}$') { throw 'Jeton du labo illisible.' }
    $code = (Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$Port/api/handoff" -Headers @{ Authorization = "Bearer $jeton" }).code
    Remove-Variable jeton
    $env:IHM_URL = "http://127.0.0.1:$Port/#code=$code"
    & node video/tournage/ihm.mjs $Actions $Sortie
    if ($LASTEXITCODE) { throw "ihm.mjs a échoué (code $LASTEXITCODE)." }
} finally {
    Remove-Item Env:IHM_URL -ErrorAction SilentlyContinue
    if (-not $tunnel.HasExited) { Stop-Process -Id $tunnel.Id -ErrorAction SilentlyContinue }
}
