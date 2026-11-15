#Requires -Version 5.1
<#
Autoriser un camarade sur le labo (à lancer par le responsable du serveur, qui a la clé d'administration).
  powershell -ExecutionPolicy Bypass -File automation\autoriser-collegue.ps1 -Cle "ssh-ed25519 AAAA... llm-lab-nom"
ou, si le camarade t'a envoyé un fichier .pub :
  powershell -ExecutionPolicy Bypass -File automation\autoriser-collegue.ps1 -Fichier chemin\vers\cle.pub
Option : -Retirer pour révoquer l'accès de cette clé.

Ce que ça fait, sans toucher aux autres accès ni demander sudo :
  - sur l'hôte Proxmox : autorise la clé UNIQUEMENT pour le saut vers le conteneur du labo
    (commande forcée + permitopen) — donc pas de shell, pas de sudo, pas d'accès aux autres labos ;
  - dans le conteneur du labo : autorise la clé en root (niveau normal de fonctionnement du labo).
#>
param(
    [string]$Cle,
    [string]$Fichier,
    [switch]$Retirer
)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
Set-Location (Resolve-Path "$PSScriptRoot\..").Path

if ($Fichier) { $Cle = Get-Content -LiteralPath $Fichier -Raw }
$Cle = ($Cle -replace '\s+', ' ').Trim()
if ($Cle -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-\S+) [A-Za-z0-9+/]+={0,2}( .*)?$') {
    throw "Ceci n'est pas une clé publique SSH valide. Attendu : « ssh-ed25519 AAAA... nom »."
}
$parts = $Cle -split ' '
$type = $parts[0]; $corps = $parts[1]
$etiquette = if ($parts.Count -ge 3) { ($parts[2..($parts.Count - 1)] -join ' ') } else { 'camarade' }
# On repère une clé par son matériel (le corps base64), indépendamment du commentaire. grep -F : texte littéral.
$marqueur = $corps.Substring(0, [Math]::Min(40, $corps.Length))

# Accès limité au seul saut vers le conteneur : commande forcée (pas de shell) + permitopen (ce seul hôte:port).
$ligneHote = 'command="echo ''Acces limite au labo LLM''; exit 1",no-pty,no-agent-forwarding,no-x11-forwarding,no-user-rc,permitopen="10.30.0.10:22" ' + $Cle

function MajCles($alias, $ligne, $libelle) {
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($ligne))
    $ajout = if ($Retirer) { '' } else { "; echo $b64 | base64 -d >> ~/.ssh/ak.tmp" }
    $remote = "umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; " +
              "grep -vF '$marqueur' ~/.ssh/authorized_keys > ~/.ssh/ak.tmp 2>/dev/null || true$ajout; " +
              "mv ~/.ssh/ak.tmp ~/.ssh/authorized_keys"
    # PowerShell 5.1 traite la sortie d'erreur d'un .exe natif comme une erreur bloquante : on la neutralise ici.
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $sortie = (& ssh -F automation/ssh_config -o ConnectTimeout=12 $alias $remote 2>&1 | Out-String).Trim()
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($code) { throw "Échec sur $libelle (code $code) : $sortie" }
    Write-Host "  $libelle : OK"
}

$action = if ($Retirer) { 'Révocation' } else { 'Autorisation' }
Write-Host "$action de « $etiquette » ($type)…"
MajCles 'lab-host' $ligneHote 'hote (saut limite vers le conteneur)'
MajCles 'llm-lab'  $Cle      'conteneur du labo (root)'
Write-Host ''
if ($Retirer) { Write-Host "Accès retiré pour « $etiquette »." }
else { Write-Host "« $etiquette » peut maintenant lancer automation\Connexion_LLM.cmd. Accès limité au labo, sans droits sur le serveur." }
