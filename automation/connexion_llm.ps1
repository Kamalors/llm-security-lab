#Requires -Version 5.1
<#
Connexion d'un camarade au labo de sécurité LLM.
Lancer : double-clic sur automation\Connexion_LLM.cmd, ou
         powershell -ExecutionPolicy Bypass -File automation\connexion_llm.ps1

1er lancement : crée TA propre clé SSH (~/.ssh/id_ed25519_llm_lab) et copie ta clé PUBLIQUE
dans le presse-papiers. Envoie cette ligne au responsable du serveur, qui l'autorise avec
automation\autoriser-collegue.ps1. Ta clé privée ne quitte jamais ton PC.
Une fois ta clé autorisée, relance : la fenêtre de démonstration s'ouvre.
L'accès est limité au labo : pas de shell ni de droits d'administration sur le serveur.
#>
$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path "$PSScriptRoot\..").Path

$Cle = Join-Path $HOME '.ssh\id_ed25519_llm_lab'

function Fin($msg) { Write-Host ''; Write-Host $msg; Read-Host 'Entrée pour fermer'; exit }

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Fin 'Client OpenSSH absent : Paramètres > Système > Fonctionnalités facultatives > ajouter « Client OpenSSH ».'
}
New-Item -ItemType Directory -Force (Join-Path $HOME '.ssh') | Out-Null

if (-not (Test-Path $Cle)) {
    Write-Host 'Première utilisation : création de ta clé SSH personnelle (phrase de passe conseillée, ou Entrée pour aucune).'
    ssh-keygen -t ed25519 -f $Cle -C "llm-lab-$env:USERNAME"
}

Write-Host 'Vérification de ton accès au labo…'
# La clé d'hôte du serveur est acceptée au premier contact (accept-new dans automation/ssh_config).
$test = & ssh -F automation/ssh_config -o ConnectTimeout=10 llm-lab 'echo OK' 2>&1
if ("$test" -match 'OK') {
    Write-Host 'Accès confirmé. Ouverture de la fenêtre de démonstration.'
    & powershell -NoProfile -STA -ExecutionPolicy Bypass -File automation\demo_llm.ps1
    exit
}

# Pas encore autorisé : donner la clé publique à envoyer au responsable.
$pub = (Get-Content "$Cle.pub" -Raw).Trim()
try { Set-Clipboard $pub } catch {}
Write-Host ''
Write-Host 'Ta clé n''est pas encore autorisée sur le labo.'
Write-Host 'Ta clé PUBLIQUE a été copiée dans le presse-papiers. Envoie cette ligne au responsable du serveur :'
Write-Host ''
Write-Host "    $pub"
Write-Host ''
Write-Host 'Quand il t''aura répondu que c''est autorisé, relance ce script.'
Fin 'Rien n''a été installé sur le serveur : ta clé privée reste sur ton PC.'
