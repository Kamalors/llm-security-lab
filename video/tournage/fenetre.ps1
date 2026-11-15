# Filme la fenêtre de démonstration pendant qu'on la pilote au clavier.
# powershell -File video/tournage/fenetre.ps1 -Sortie video/captures/<nom> [-Touches 'F5','1',...,'8']
# Écrit <nom>.mp4 (1920x1080, 30 i/s) et <nom>.touches.json : [{touche, t, fin}] en secondes depuis le début.
# Pilote le PC : à lancer seulement après le feu vert de l'utilisateur.
param([Parameter(Mandatory)][string]$Sortie, [string[]]$Touches = @('F5'))
$ErrorActionPreference = 'Stop'
$Touches = @($Touches | ForEach-Object { $_ -split ',' } | Where-Object { $_ })   # powershell -File passe 'F5','1' en une seule chaîne
$Racine = (Resolve-Path "$PSScriptRoot\..\..").Path
Set-Location $Racine
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class W32 {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Ri, B; }
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out R r, int s);
}
'@
[void][W32]::SetProcessDPIAware()
$ffmpeg = (& python -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())").Trim()
New-Item -ItemType Directory -Force (Split-Path $Sortie) | Out-Null
$mp4 = "$Sortie.mp4"; if (Test-Path $mp4) { throw "$mp4 existe déjà : choisir un autre nom de prise" }

# 1. La fenêtre, agrandie
Remove-Item Env:LAB_URL -ErrorAction SilentlyContinue   # sinon la fenêtre passerait en mode local
Start-Process "$Racine\automation\Demo_LLM.cmd"
$proc = $null
for ($i = 0; $i -lt 60 -and -not $proc; $i++) {
    Start-Sleep -Milliseconds 500
    $proc = Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like 'Labo s*LLM*' } | Select-Object -First 1
}
if (-not $proc) { throw 'La fenêtre de démonstration ne s''est pas ouverte en 30 s.' }
$h = $proc.MainWindowHandle
[void][W32]::ShowWindow($h, 3)
Start-Sleep -Seconds 2
[System.Windows.Forms.Cursor]::Position = New-Object Drawing.Point(1919, 1079)   # hors de la fenêtre : aucun survol
$r = New-Object W32+R
[void][W32]::DwmGetWindowAttribute($h, 9, [ref]$r, 16)   # DWMWA_EXTENDED_FRAME_BOUNDS, pixels physiques
$w = ($r.Ri - $r.L) - (($r.Ri - $r.L) % 2); $hh = ($r.B - $r.T) - (($r.B - $r.T) % 2)
$btn = [Windows.Automation.AutomationElement]::FromHandle($h).FindFirst([Windows.Automation.TreeScope]::Descendants,
    (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty, 'BtnCheck')))
if (-not $btn) { throw 'Bouton « Vérifier le labo » introuvable par UI Automation.' }

# 2. L'enregistrement : zone du bureau (le titre accentué casserait gdigrab title=), complétée en 1920x1080
$psi = New-Object Diagnostics.ProcessStartInfo $ffmpeg
$psi.Arguments = "-hide_banner -loglevel error -f gdigrab -framerate 30 -draw_mouse 0 -offset_x $($r.L) -offset_y $($r.T) " +
    "-video_size ${w}x$hh -i desktop -vf `"scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=0xF5F7FB`" " +
    "-c:v libx264 -preset ultrafast -crf 16 -pix_fmt yuv420p -r 30 `"$mp4`""
$psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.CreateNoWindow = $true
$ff = [Diagnostics.Process]::Start($psi)
$chrono = [Diagnostics.Stopwatch]::StartNew()   # ponytail: départ approché à ±0,5 s (démarrage de gdigrab), assez pour placer un badge
Start-Sleep -Seconds 3

# 3. Les touches, une à une, en attendant que la fenêtre revienne au repos
$ws = New-Object -ComObject WScript.Shell
$journal = @()
try {
    foreach ($k in $Touches) {
        [void][W32]::SetForegroundWindow($h); [void]$ws.AppActivate($proc.Id); Start-Sleep -Milliseconds 300
        $t = $chrono.Elapsed.TotalSeconds
        $ws.SendKeys($(if ($k -match '^F\d+$') { "{$k}" } else { $k }))
        for ($i = 0; $i -lt 30 -and $btn.Current.IsEnabled; $i++) { Start-Sleep -Milliseconds 100 }   # le travail démarre
        $limite = [DateTime]::Now.AddSeconds(240)
        while (-not $btn.Current.IsEnabled) {
            if ([DateTime]::Now -gt $limite) { throw "Touche $k : la fenêtre est toujours occupée après 240 s." }
            Start-Sleep -Milliseconds 200
        }
        $journal += [pscustomobject]@{ touche = $k; t = [math]::Round($t, 2); fin = [math]::Round($chrono.Elapsed.TotalSeconds, 2) }
        Write-Host ("{0} : {1:0.0} s -> {2:0.0} s" -f $k, $t, $chrono.Elapsed.TotalSeconds)
        Start-Sleep -Seconds 4   # le verdict reste à l'écran
    }
} finally {
    $ff.StandardInput.Write('q'); $ff.StandardInput.Close()
    if (-not $ff.WaitForExit(20000)) { $ff.Kill() }
    [void]$proc.CloseMainWindow()   # ferme aussi le tunnel SSH de la fenêtre
    $json = ConvertTo-Json -InputObject @($journal) -Depth 3
    [IO.File]::WriteAllText("$Racine\$Sortie.touches.json", $json, (New-Object Text.UTF8Encoding $false))
}
Write-Host "ok $mp4"
