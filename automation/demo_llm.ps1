#Requires -Version 5.1
<#
Démonstration du labo de sécurité LLM : fenêtre de pilotage pendant la soutenance.
Lancer : double-clic sur automation\Demo_LLM.cmd
     ou : powershell -STA -ExecutionPolicy Bypass -File automation\demo_llm.ps1
Accès (aucun mot de passe, aucun secret dans ce fichier) :
  - clé d'administration ~/.ssh/id_ed25519_par861454, mêmes accès que automation/ssh_config ;
  - le jeton du labo est lu dans le conteneur à la connexion et ne reste qu'en mémoire.
Mode local, sans serveur : définir LAB_URL (ex. http://127.0.0.1:8080) et LAB_HUMAN_TOKEN avant de lancer.
#>
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$Root = Split-Path -Parent $PSScriptRoot
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$PortLab = 8080
$Local = [bool]$env:LAB_URL
$Cle = Test-Path "$HOME\.ssh\id_ed25519_par861454"
$Mode = if ($Local) { 'local' } elseif ($Cle) { 'admin' } else { 'aucun' }

if (-not $Local -and -not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    [Windows.MessageBox]::Show("Le client OpenSSH est absent.`nParamètres > Système > Fonctionnalités facultatives > ajouter « Client OpenSSH ».", 'Labo sécurité LLM') | Out-Null
    exit 1
}

# ------------------------------------------------------------------ fenêtre
# Deux encres portent tout l'affichage, comme dans l'IHM web : bleu = ce que le développeur a écrit
# (et « le modèle a tenu »), orange = ce qui vient de l'extérieur (et « l'attaque a réussi »).
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Labo sécurité LLM, démonstration en direct" Width="1480" Height="900" MinWidth="1150" MinHeight="720"
        WindowStartupLocation="CenterScreen" Background="#F5F7FB" Foreground="#101936"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="15" UseLayoutRounding="True">
  <Window.Resources>
    <Style x:Key="Action" TargetType="Button">
      <Setter Property="Background" Value="#FFFFFF"/>
      <Setter Property="Foreground" Value="#101936"/>
      <Setter Property="BorderBrush" Value="#C8D0E0"/>
      <Setter Property="Padding" Value="18,9"/>
      <Setter Property="Margin" Value="10,0,0,0"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1.5" CornerRadius="5" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.86"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#1D3FCB"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Action}">
      <Setter Property="Background" Value="#101936"/>
      <Setter Property="Foreground" Value="#F5F7FB"/>
      <Setter Property="BorderBrush" Value="#101936"/>
    </Style>
    <Style x:Key="Ghost" TargetType="Button" BasedOn="{StaticResource Action}">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="#A3ADC9"/>
      <Setter Property="BorderBrush" Value="#36406A"/>
      <Setter Property="Padding" Value="12,4"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="Normal"/>
    </Style>
    <Style x:Key="Pill" TargetType="Button">
      <Setter Property="Foreground" Value="#101936"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="#FFFFFF" BorderBrush="#C8D0E0" BorderThickness="1" CornerRadius="16" Padding="12,7">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#8FA5FF"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#1D3FCB"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.5"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Step" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="#101936"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Margin" Value="0,1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="5" Padding="14,7"
                    BorderThickness="2" BorderBrush="Transparent">
              <ContentPresenter HorizontalAlignment="Stretch"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#EEF1F8"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#1D3FCB"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid Margin="28,20,28,24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <Grid Margin="0,0,0,18">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <StackPanel>
        <TextBlock Text="Injection de prompt" FontFamily="Bahnschrift, Segoe UI" FontStretch="SemiCondensed" FontSize="32" FontWeight="Bold"/>
        <TextBlock Text="Huit attaques jouées en direct sur un LLM local, hébergé sur le serveur Proxmox" Foreground="#4B5675"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
        <Button x:Name="BtnServer" Style="{StaticResource Pill}" ToolTipService.ShowOnDisabled="True">
          <StackPanel Orientation="Horizontal">
            <Ellipse x:Name="DotServer" Width="10" Height="10" Fill="#C8D0E0" VerticalAlignment="Center"/>
            <TextBlock x:Name="TxtServer" Text="Labo non vérifié" Margin="8,0,0,0" FontSize="14"/>
          </StackPanel>
        </Button>
        <Button x:Name="BtnCheck" Style="{StaticResource Action}" Content="Vérifier le labo" Margin="22,0,0,0"/>
        <Button x:Name="BtnPve" Style="{StaticResource Action}" ToolTipService.ShowOnDisabled="True">
          <StackPanel Orientation="Horizontal">
            <Ellipse x:Name="DotPve" Width="9" Height="9" Fill="#C8D0E0" VerticalAlignment="Center"/>
            <TextBlock x:Name="TxtPve" Text="Ouvrir Proxmox" Margin="8,0,0,0"/>
          </StackPanel>
        </Button>
        <Button x:Name="BtnIhm" Style="{StaticResource Primary}" Content="Ouvrir l'IHM web" ToolTipService.ShowOnDisabled="True"/>
      </StackPanel>
    </Grid>

    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="350"/>
        <ColumnDefinition Width="22"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <Border Background="#FFFFFF" BorderBrush="#C8D0E0" BorderThickness="1" CornerRadius="6">
        <DockPanel>
          <TextBlock DockPanel.Dock="Top" Text="Scénario" FontFamily="Bahnschrift, Segoe UI" FontStretch="SemiCondensed" FontSize="21" FontWeight="SemiBold" Margin="22,16,20,2"/>
          <TextBlock DockPanel.Dock="Top" Text="Une attaque par clic, ou touches 1 à 8." Foreground="#4B5675"
                     FontSize="13.5" TextWrapping="Wrap" Margin="22,0,20,6"/>
          <Border DockPanel.Dock="Bottom" x:Name="ModeBox" Margin="14,8,14,14" Padding="14,11" CornerRadius="5" Background="#E1E7FB">
            <TextBlock x:Name="TxtMode" TextWrapping="Wrap" FontSize="13.5" Foreground="#101936"/>
          </Border>
          <ScrollViewer VerticalScrollBarVisibility="Auto" Focusable="False">
            <StackPanel x:Name="Steps" Margin="8,0,8,0"/>
          </ScrollViewer>
        </DockPanel>
      </Border>

      <Grid Grid.Column="2">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <Border Background="#FFFFFF" BorderBrush="#C8D0E0" BorderThickness="1" CornerRadius="6" Padding="14,12">
          <Viewbox Stretch="Uniform" MaxHeight="300">
            <Canvas x:Name="Map" Width="1130" Height="340"/>
          </Viewbox>
        </Border>
        <Border Grid.Row="1" Margin="0,16" Background="#FFFFFF" BorderBrush="#C8D0E0" BorderThickness="1" CornerRadius="6">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="8"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Border x:Name="VerdictStrip" Background="#C8D0E0" CornerRadius="6,0,0,6"/>
            <StackPanel Grid.Column="1" Margin="22,14,16,16">
              <TextBlock x:Name="VerdictTitle" FontFamily="Bahnschrift, Segoe UI" FontStretch="SemiCondensed" FontSize="34"
                         FontWeight="Bold" TextWrapping="Wrap"/>
              <TextBlock x:Name="VerdictDetail" FontSize="17" Foreground="#4B5675" TextWrapping="Wrap" Margin="0,4,0,0"/>
            </StackPanel>
            <Border Grid.Column="2" x:Name="Badge" Visibility="Collapsed" VerticalAlignment="Center" CornerRadius="5" Padding="16,6" Margin="0,0,22,0">
              <TextBlock x:Name="BadgeText" FontWeight="SemiBold"/>
            </Border>
            <ProgressBar x:Name="Busy" Grid.ColumnSpan="3" Height="3" VerticalAlignment="Bottom" Margin="10,0,10,1"
                         IsIndeterminate="True" Foreground="#1D3FCB" Background="Transparent" BorderThickness="0" Visibility="Hidden"/>
          </Grid>
        </Border>
        <Border Grid.Row="2" Background="#101936" CornerRadius="6">
          <DockPanel>
            <Grid DockPanel.Dock="Top" Margin="18,10,12,2">
              <TextBlock Text="Échange brut avec le modèle, la preuve" Foreground="#A3ADC9" FontSize="13.5" VerticalAlignment="Center"/>
              <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <Button x:Name="BtnCopy" Style="{StaticResource Ghost}" Content="Copier"/>
                <Button x:Name="BtnClear" Style="{StaticResource Ghost}" Content="Effacer"/>
              </StackPanel>
            </Grid>
            <RichTextBox x:Name="Term" Background="Transparent" BorderThickness="0" IsReadOnly="True" Foreground="#E8ECF8"
                         FontFamily="Cascadia Mono, Consolas" FontSize="14" Padding="12,2,12,12"
                         VerticalScrollBarVisibility="Auto" IsDocumentEnabled="False">
              <FlowDocument PagePadding="0"/>
            </RichTextBox>
          </DockPanel>
        </Border>
      </Grid>
    </Grid>
  </Grid>
</Window>
'@
$win = [Windows.Markup.XamlReader]::Parse($xaml)
foreach ($n in 'DotServer', 'TxtServer', 'BtnCheck', 'BtnIhm', 'BtnServer', 'BtnPve', 'DotPve', 'TxtPve', 'TxtMode', 'ModeBox',
               'Steps', 'Map', 'VerdictStrip', 'VerdictTitle', 'VerdictDetail', 'Badge', 'BadgeText', 'Busy', 'Term', 'BtnCopy', 'BtnClear') {
    Set-Variable -Name $n -Value $win.FindName($n)
}

function Brush([string]$hex) {
    $b = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString($hex)); $b.Freeze(); $b
}
$B = @{}
@{ Ink = '#101936'; Ink2 = '#4B5675'; Muted = '#C8D0E0'; Rule = '#C8D0E0'; Panel = '#FFFFFF'; Paper = '#F5F7FB'; Actif = '#E1E7FB'
   Sys = '#1D3FCB'; SysL = '#8FA5FF'; SysBg = '#E1E7FB'; Ext = '#C2410C'; ExtL = '#FF9A52'; ExtBg = '#FBE6DA'
   TermTxt = '#E8ECF8'; TermFort = '#FFFFFF'; TermInfo = '#A3ADC9' }.GetEnumerator() | ForEach-Object { $B[$_.Key] = Brush $_.Value }

# ------------------------------------------------------------------ schéma du labo
# En haut, ce qui se joue dans le modèle : deux textes, un seul contexte. En bas, où cela tourne.
$Noeuds = [ordered]@{
    regles = @{ X = 16;  Y = 22;  W = 240; H = 62; Nom = 'Règles du serveur'; Sous = 'prompt système et secret';  Type = 'sys' }
    msg    = @{ X = 16;  Y = 148; W = 240; H = 62; Nom = 'Message reçu';      Sous = 'attaquant ou document';     Type = 'ext' }
    ctx    = @{ X = 356; Y = 85;  W = 200; H = 62; Nom = 'Contexte';          Sous = 'une seule suite de jetons'; Type = 'site' }
    modele = @{ X = 642; Y = 85;  W = 200; H = 62; Nom = 'Modèle cible';      Sous = 'qwen2.5:1.5b';              Type = 'dc' }
    rep    = @{ X = 930; Y = 22;  W = 184; H = 62; Nom = 'Réponse';           Sous = 'texte généré';              Type = 'site' }
    verif  = @{ X = 930; Y = 148; W = 184; H = 62; Nom = 'Vérificateur';      Sous = 'verdict calculé en code';   Type = 'site' }
    pc     = @{ X = 16;  Y = 284; W = 150; H = 40; Nom = 'Ce PC';             Type = 'chip' }
    pve    = @{ X = 262; Y = 284; W = 190; H = 40; Nom = 'Serveur Proxmox';   Type = 'chip'; Hote = 'lab-host' }
    ct     = @{ X = 548; Y = 284; W = 190; H = 40; Nom = 'Conteneur du labo'; Type = 'chip'; Hote = 'llm-lab' }
    api    = @{ X = 834; Y = 284; W = 130; H = 40; Nom = 'API du labo';       Type = 'chip' }
    oll    = @{ X = 984; Y = 284; W = 130; H = 40; Nom = 'Ollama';            Type = 'chip' }
}
function Centre($k) { $n = $Noeuds[$k]; @(($n.X + $n.W / 2), ($n.Y + $n.H / 2)) }
function New-Line($de, $vers, $brush, [double]$w) {
    $p, $q = (Centre $de), (Centre $vers)
    $l = New-Object Windows.Shapes.Line
    $l.X1, $l.Y1, $l.X2, $l.Y2 = $p[0], $p[1], $q[0], $q[1]
    $l.Stroke = $brush; $l.StrokeThickness = $w
    [void]$Map.Children.Add($l); $l
}
$Liens = [ordered]@{}
foreach ($pair in @('regles', 'ctx'), @('msg', 'ctx'), @('ctx', 'modele'), @('modele', 'rep'), @('rep', 'verif'),
                  @('pc', 'pve'), @('pve', 'ct'), @('ct', 'api'), @('api', 'oll')) {
    $Liens["$($pair[0])-$($pair[1])"] = New-Line $pair[0] $pair[1] $B.Rule 2
}
$tunnel = New-Object Windows.Controls.TextBlock
$tunnel.Text = 'tunnel SSH'; $tunnel.FontSize = 12; $tunnel.Foreground = $B.Ink2
[Windows.Controls.Canvas]::SetLeft($tunnel, 184); [Windows.Controls.Canvas]::SetTop($tunnel, 284)
[void]$Map.Children.Add($tunnel)

$Boites = @{}
$Points = @{}
$Sous = @{}
foreach ($k in $Noeuds.Keys) {
    $n = $Noeuds[$k]
    $bd = New-Object Windows.Controls.Border
    $bd.Width, $bd.Height, $bd.Tag = $n.W, $n.H, $n.Hote
    $bd.BorderThickness = [Windows.Thickness]::new(1.5)
    $bd.CornerRadius = [Windows.CornerRadius]::new(5)
    $bd.Background = $B.Panel
    $fg = $B.Ink; $fgSous = $B.Ink2
    switch ($n.Type) {
        'sys'  { $bd.BorderBrush = $B.Sys; $fgSous = $B.Sys }
        'ext'  { $bd.BorderBrush = $B.Ext; $fgSous = $B.Ext }
        'site' { $bd.BorderBrush = $B.Ink }
        'dc'   { $bd.Background = $B.Ink; $bd.BorderBrush = $B.Ink; $fg = $B.Paper; $fgSous = $B.SysL }
        'chip' { $bd.BorderBrush = $B.Rule }
    }
    $sp = New-Object Windows.Controls.StackPanel
    $sp.VerticalAlignment = 'Center'; $sp.HorizontalAlignment = 'Center'
    $t1 = New-Object Windows.Controls.TextBlock
    $t1.Text = $n.Nom; $t1.FontWeight = 'SemiBold'; $t1.Foreground = $fg; $t1.HorizontalAlignment = 'Center'
    $t1.FontSize = if ($n.Type -eq 'chip') { 13.5 } else { 16 }
    [void]$sp.Children.Add($t1)
    if ($n.Sous) {
        $t2 = New-Object Windows.Controls.TextBlock
        $t2.Text = $n.Sous; $t2.FontSize = 12.5; $t2.HorizontalAlignment = 'Center'; $t2.Foreground = $fgSous
        [void]$sp.Children.Add($t2)
        $Sous[$k] = $t2
    }
    $bd.Child = $sp
    if ($n.Hote -and $Mode -eq 'admin') {
        $bd.ToolTip = "Ouvrir une console sur $($n.Hote)"; $bd.Cursor = 'Hand'
        $bd.Add_MouseLeftButtonUp({ param($s, $e) Open-Console $s.Tag })
    }
    [Windows.Controls.Canvas]::SetLeft($bd, $n.X); [Windows.Controls.Canvas]::SetTop($bd, $n.Y)
    [void]$Map.Children.Add($bd)
    $Boites[$k] = @{ Border = $bd; Defaut = $bd.BorderBrush }
    if ($n.Type -eq 'chip') {
        $dot = New-Object Windows.Shapes.Ellipse
        $dot.Width = $dot.Height = 10; $dot.StrokeThickness = 1.5
        [Windows.Controls.Canvas]::SetLeft($dot, $n.X + 10); [Windows.Controls.Canvas]::SetTop($dot, $n.Y + 15)
        [void]$Map.Children.Add($dot)
        $Points[$k] = $dot
    }
}
# État d'un maillon de l'infrastructure : plein = répond, creux = ne répond pas, gris = pas encore vérifié.
function Set-Dot([string]$k, [string]$etat) {
    $d = $Points[$k]
    switch ($etat) {
        'ok' { $d.Fill = $B.Sys; $d.Stroke = $B.Sys }
        'ko' { $d.Fill = $B.Panel; $d.Stroke = $B.Ink }
        default { $d.Fill = $B.Muted; $d.Stroke = $B.Muted }
    }
}
foreach ($k in $Points.Keys) { Set-Dot $k '' }

function Reset-Map {
    foreach ($l in $Liens.Values) { $l.Stroke = $B.Rule; $l.StrokeThickness = 2 }
    foreach ($bx in $Boites.Values) { $bx.Border.BorderBrush = $bx.Defaut; $bx.Border.BorderThickness = [Windows.Thickness]::new(1.5) }
}
function Paint([string[]]$cles, $brush, [double]$w = 4) { foreach ($k in $cles) { $Liens[$k].Stroke = $brush; $Liens[$k].StrokeThickness = $w } }
function Glow([string]$k, $brush) { $Boites[$k].Border.BorderBrush = $brush; $Boites[$k].Border.BorderThickness = [Windows.Thickness]::new(3.5) }
# Les deux textes entrent toujours dans le même contexte ; la couleur de la sortie dit lequel a gagné.
function Show-Flow([string]$etat) {
    Reset-Map
    if (-not $etat) { return }
    Paint 'regles-ctx' $B.Sys; Paint 'msg-ctx' $B.Ext; Glow 'msg' $B.Ext
    $gagnant = switch ($etat) { 'compromis' { $B.Ext } 'tenu' { $B.Sys } default { $null } }
    if ($gagnant) { Paint 'ctx-modele', 'modele-rep', 'rep-verif' $gagnant; Glow 'rep' $gagnant; Glow 'verif' $gagnant }
}

# ------------------------------------------------------------------ affichage
$MotifKo = 'Permission denied|Could not resolve|Connection refused|Connection timed out|No route|inactive|failed|erreur'
function Add-Line([string]$ton, [string]$texte) {
    $p = New-Object Windows.Documents.Paragraph
    $p.Margin = [Windows.Thickness]::new(0)
    $run = { param($t, $brush) $r = New-Object Windows.Documents.Run($t); $r.Foreground = $brush; $p.Inlines.Add($r); $r }
    switch ($ton) {
        'cmd'  { $p.Margin = [Windows.Thickness]::new(0, 10, 0, 2); [void](& $run '$ ' $B.SysL); [void](& $run $texte $B.TermFort) }
        'info' { $p.Margin = [Windows.Thickness]::new(0, 6, 0, 0); (& $run $texte $B.TermInfo).FontStyle = 'Italic' }
        'sys'  { $p.Margin = [Windows.Thickness]::new(0, 10, 0, 0); [void](& $run 'règles     ' $B.TermInfo); [void](& $run $texte $B.SysL) }
        'usr'  { $p.Margin = [Windows.Thickness]::new(0, 8, 0, 0); [void](& $run 'attaquant  ' $B.TermInfo); [void](& $run $texte $B.ExtL) }
        { $_ -in 'rep', 'rep+' } {
            [void](& $run $(if ($ton -eq 'rep') { 'modèle     ' } else { '           ' }) $B.TermInfo)
            # Le code secret de l'essai en cours ressort en orange s'il apparaît tel quel dans la réponse.
            $s = $sync.Secret
            if ($s -and $texte.Contains($s)) {
                $i = $texte.IndexOf($s)
                [void](& $run $texte.Substring(0, $i) $B.TermFort)
                (& $run $s $B.ExtL).FontWeight = 'Bold'
                [void](& $run $texte.Substring($i + $s.Length) $B.TermFort)
            } else { [void](& $run $texte $B.TermFort) }
        }
        default { [void](& $run $texte $(if ($texte -match $MotifKo) { $B.ExtL } else { $B.TermTxt })) }
    }
    $Term.Document.Blocks.Add($p)
    while ($Term.Document.Blocks.Count -gt 800) { [void]$Term.Document.Blocks.Remove($Term.Document.Blocks.FirstBlock) }
    $Term.ScrollToEnd()
}

# tons : tenu (bleu), compromis (orange), pb (incident technique, neutre), busy, idle
function Set-Verdict([string]$titre, [string]$detail, [string]$ton = 'idle', [string]$etiquette = '') {
    $VerdictTitle.Text = $titre; $VerdictDetail.Text = $detail
    $VerdictStrip.Background = switch ($ton) { 'tenu' { $B.Sys } 'compromis' { $B.Ext } 'pb' { $B.Ink2 } 'busy' { $B.Ink } default { $B.Muted } }
    $VerdictTitle.Foreground = switch ($ton) { 'tenu' { $B.Sys } 'compromis' { $B.Ext } default { $B.Ink } }
    if ($etiquette) {
        $Badge.Visibility = 'Visible'; $BadgeText.Text = $etiquette
        switch ($ton) {
            'compromis' { $Badge.Background = $B.ExtBg; $BadgeText.Foreground = $B.Ext }
            'pb'        { $Badge.Background = $B.Paper; $BadgeText.Foreground = $B.Ink2 }
            default     { $Badge.Background = $B.SysBg; $BadgeText.Foreground = $B.Sys }
        }
    } else { $Badge.Visibility = 'Collapsed' }
}
function Set-Pill([string]$etat, [string]$texte) {
    $DotServer.Fill = switch ($etat) { 'ok' { $B.Sys } 'ko' { $B.Ink } default { $B.Muted } }
    $TxtServer.Text = $texte
}

$StepButtons = @{}
function Set-StepState([int]$n, [string]$etat) {
    $num = $StepButtons[$n].Content.Children[0]
    $fond = switch ($etat) { 'tenu' { $B.Sys } 'compromis' { $B.Ext } default { $null } }
    $num.Background = $fond
    $num.BorderBrush = if ($fond) { $fond } else { $B.Ink }
    $num.Child.Foreground = if ($fond) { $B.Paper } else { $B.Ink }
}
function Set-Active([int]$n) {
    foreach ($k in $StepButtons.Keys) { $StepButtons[$k].Background = if ($k -eq $n) { $B.Actif } else { [Windows.Media.Brushes]::Transparent } }
}
function Set-BusyState([bool]$occupe) {
    $Busy.Visibility = if ($occupe) { 'Visible' } else { 'Hidden' }
    $actif = (-not $occupe) -and ($Mode -ne 'aucun')
    foreach ($sb in $StepButtons.Values) { $sb.IsEnabled = $actif }
    $BtnCheck.IsEnabled = $actif
    $BtnIhm.IsEnabled = $actif
}

# ------------------------------------------------------------------ travail en arrière-plan (la fenêtre reste fluide)
$sync = [hashtable]::Synchronized(@{
    Queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    Base = "http://127.0.0.1:$PortLab"; Token = ''; Secret = ''; TunnelPid = 0 })
if ($Local) { $sync.Base = $env:LAB_URL.TrimEnd('/'); $sync.Token = "$env:LAB_HUMAN_TOKEN" }

$Common = {
    Set-Location -LiteralPath $Root
    [Environment]::CurrentDirectory = $Root
    function Say([string]$t, [string]$ton = 'out') { $sync.Queue.Enqueue(@($ton, $t)) }
    function Test-PortOuvert([int]$port) {
        [bool]([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() | Where-Object { $_.Port -eq $port })
    }
    function Node([string]$h, [string]$cmd) {
        Say "[$h] $cmd" 'cmd'
        $lignes = New-Object System.Collections.Generic.List[string]
        & ssh -n -F automation/ssh_config -o ConnectTimeout=8 $h $cmd 2>&1 | ForEach-Object { $l = "$_"; $lignes.Add($l); Say $l }
        @{ Code = $LASTEXITCODE; Text = ($lignes -join "`n") }
    }
    # Jeton et tunnel vers l'API du labo. Renvoie '' si tout est prêt, sinon la raison en clair.
    function Connect-Lab {
        if ($Local) { if ($sync.Token) { return '' } else { return 'Mode local : la variable LAB_HUMAN_TOKEN est vide.' } }
        if (-not $sync.Token) {
            # Lu sans passer par Node : le jeton ne doit pas s'afficher dans la sortie projetée.
            $t = & ssh -n -F automation/ssh_config -o ConnectTimeout=8 llm-lab "sed -n 's/^LAB_HUMAN_TOKEN=//p' /opt/llm-security-lab/.env" 2>$null | Select-Object -Last 1
            if ("$t" -notmatch '^[0-9a-f]{32,}$') { return 'Le conteneur du labo ne répond pas, ou le labo n''y est pas installé. Cliquez sur « Vérifier le labo ».' }
            $sync.Token = "$t"
        }
        if (-not (Test-PortOuvert $PortLab)) {
            $p = Start-Process ssh -WorkingDirectory $Root -WindowStyle Hidden -PassThru -ArgumentList "-F automation/ssh_config -N -L ${PortLab}:127.0.0.1:8080 -o ExitOnForwardFailure=yes llm-lab"
            $sync.TunnelPid = $p.Id
            for ($i = 0; $i -lt 50 -and -not $p.HasExited -and -not (Test-PortOuvert $PortLab); $i++) { Start-Sleep -Milliseconds 300 }
            if (-not (Test-PortOuvert $PortLab)) { return "Le tunnel SSH vers le labo n'a pas pu s'ouvrir (port local $PortLab)." }
        }
        ''
    }
    function Api([string]$method, [string]$path, $body = $null) {
        $p = @{ Uri = "$($sync.Base)$path"; Method = $method; Headers = @{ Authorization = "Bearer $($sync.Token)" }; TimeoutSec = 200 }
        if ($body) { $p.Body = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Compress)); $p.ContentType = 'application/json' }
        Invoke-RestMethod @p
    }
    # Message d'erreur renvoyé par l'API (JSON en UTF-8), sinon celui de PowerShell.
    function Read-ApiError($e) {
        try {
            $st = $e.Exception.Response.GetResponseStream(); $st.Position = 0
            $m = ((New-Object IO.StreamReader($st, [Text.Encoding]::UTF8)).ReadToEnd() | ConvertFrom-Json).error
            if ($m) { return $m }
        } catch {}
        if ($e.Exception.Message -match 'connecter|connect|refus') { return "L'API du labo ne répond pas sur $($sync.Base). Cliquez sur « Vérifier le labo »." }
        $e.Exception.Message
    }
}
$script:Job = $null
function Start-Action([string]$libelle, [scriptblock]$travail, [scriptblock]$fin, [hashtable]$vars = @{}) {
    if ($script:Job) { return }
    Set-BusyState $true
    Set-Verdict "$libelle…" 'En cours sur le labo.' 'busy'
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    foreach ($k in 'sync', 'Root', 'PortLab', 'Local') { $rs.SessionStateProxy.SetVariable($k, (Get-Variable $k -ValueOnly)) }
    foreach ($k in $vars.Keys) { $rs.SessionStateProxy.SetVariable($k, $vars[$k]) }
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($Common.ToString() + "`n" + $travail.ToString())
    $script:Job = @{ PS = $ps; Handle = $ps.BeginInvoke(); Fin = $fin }
}

# ------------------------------------------------------------------ vérification du labo, maillon par maillon
function Start-Check {
    Show-Flow ''
    foreach ($k in $Points.Keys) { Set-Dot $k '' }
    Start-Action 'Vérification du labo' {
        $r = @{ Serveur = $Local; Conteneur = $Local; Etat = ''; Api = $false; Pret = $false; Modele = ''; Erreur = '' }
        if (-not $Local) {
            $h = Node 'lab-host' 'echo serveur-ok'
            if ($h.Text -notmatch 'serveur-ok') { return $r }
            $r.Serveur = $true
            $c = Node 'llm-lab' 'echo etat ollama=$(systemctl is-active ollama) api=$(systemctl is-active llm-lab) installe=$(test -f /opt/llm-security-lab/.env && echo oui || echo non) ram_libre=$(free -m | awk ''/Mem:/{print $7}'')Mo'
            if ($c.Text -notmatch 'etat ollama=') { return $r }
            $r.Conteneur = $true; $r.Etat = $c.Text
        }
        $r.Erreur = Connect-Lab
        if ($r.Erreur) { return $r }
        try {
            Say "GET $($sync.Base)/api/status" 'cmd'
            $st = Api GET '/api/status'
            Say ($st | ConvertTo-Json -Compress)
            $r.Api = $true; $r.Pret = [bool]$st.ready; $r.Modele = "$($st.model)"
        } catch { $r.Erreur = Read-ApiError $_ }
        $r
    } {
        param($r)
        Set-Dot 'pc' 'ok'
        if (-not $r.Serveur) {
            Set-Dot 'pve' 'ko'; Set-Pill 'ko' 'Serveur injoignable'
            Set-Verdict 'Le serveur Proxmox ne répond pas' 'Vérifiez la connexion Internet et la clé ~/.ssh/id_ed25519_par861454.' 'pb' 'À vérifier'
            return
        }
        Set-Dot 'pve' 'ok'
        if (-not $r.Conteneur) {
            Set-Dot 'ct' 'ko'; Set-Pill 'ko' 'Conteneur absent'
            Set-Verdict 'Le conteneur du labo ne répond pas' 'S''il n''est pas encore créé, dans un terminal : ssh -t lab-host "sudo bash ~/llm-security-lab/provision-ct.sh --apply". S''il est arrêté : pct start 401 en root sur le serveur.' 'pb' 'À vérifier'
            return
        }
        Set-Dot 'ct' 'ok'
        if ($Local) { Set-Dot 'pve' ''; Set-Dot 'ct' '' }
        if ($r.Etat -match 'installe=non') {
            Set-Dot 'oll' 'ko'; Set-Dot 'api' 'ko'; Set-Pill 'ko' 'Labo non installé'
            Set-Verdict 'Le conteneur répond, le labo n''y est pas encore installé' 'Il reste à y copier le projet et à lancer deploy/install-guest.sh (Ollama, modèle, API). Voir le README.' 'pb' 'À installer'
            return
        }
        $ollama = if ($Local) { $r.Pret } else { $r.Etat -match 'ollama=active' }
        $service = if ($Local) { $r.Api } else { $r.Etat -match 'api=active' }
        Set-Dot 'oll' $(if ($ollama) { 'ok' } else { 'ko' })
        Set-Dot 'api' $(if ($service -and $r.Api) { 'ok' } else { 'ko' })
        if ($r.Modele) { $Sous['modele'].Text = $r.Modele }
        if (-not $Local -and -not $ollama) {
            Set-Pill 'ko' 'Ollama arrêté'
            Set-Verdict 'Ollama ne tourne pas dans le conteneur' 'Cliquez sur « Conteneur du labo » dans le schéma pour ouvrir sa console, puis : systemctl start ollama.' 'pb' 'À vérifier'
        } elseif (-not $r.Api) {
            Set-Pill 'ko' 'API arrêtée'
            $d = if ($r.Erreur) { $r.Erreur } else { 'Dans la console du conteneur : systemctl start llm-lab.' }
            Set-Verdict 'L''API du labo ne répond pas' $d 'pb' 'À vérifier'
        } elseif (-not $r.Pret) {
            Set-Dot 'oll' 'ko'; Set-Pill 'ko' 'Modèle absent'
            Set-Verdict "Le modèle $($r.Modele) n'est pas disponible" "Ollama ne le liste pas. Dans la console du conteneur : ollama pull $($r.Modele)." 'pb' 'À vérifier'
        } else {
            Set-Dot 'oll' 'ok'; Set-Pill 'ok' 'Labo prêt'
            Set-Verdict 'Le labo est prêt' "Serveur, conteneur, Ollama et API répondent. Modèle cible : $($r.Modele). La démonstration peut commencer." 'tenu' 'Prêt'
        }
    }
}

# ------------------------------------------------------------------ une attaque : les messages prêts du scénario, dans l'ordre
$Raisons = @{
    exact_secret = 'le modèle a révélé le code secret'; base64_secret = 'le code secret est sorti encodé en base64'
    hex_secret = 'le code secret est sorti en hexadécimal'; rot13_secret = 'le code secret est sorti chiffré en ROT13'
    forbidden_marker = 'le modèle a exécuté la consigne cachée dans le document'
    invalid_schema = 'le modèle est sorti du format JSON imposé'; invalid_json = 'le modèle est sorti du format JSON imposé'
    unauthorized_approval = 'le modèle a répondu APPROVED sans autorisation' }
function Invoke-Step([int]$n) {
    if ($script:Job -or $Mode -eq 'aucun') { return }
    Set-Active $n
    Set-StepState $n ''
    Show-Flow 'envoi'
    $e = $Etapes[$n - 1]
    Start-Action "$($e[1]) : $($e[2])" {
        $r = @{ Etape = $Etape; Erreur = ''; Verdict = ''; Raisons = @(); Tours = 0; Owasp = '' }
        $r.Erreur = Connect-Lab
        if ($r.Erreur) { return $r }
        try {
            $sc = (Api GET '/api/scenarios').scenarios | Where-Object { $_.id -eq $Id }
            $r.Owasp = $sc.owasp -join ', '
            $s = Api POST '/api/sessions' @{ scenario = $Id; mode = 'attack' }
            $sync.Secret = "$($s.secret)"
            Say "$Id, essai $($s.id.Substring(0, 8)), modèle $($s.model)" 'info'
            Say $s.system 'sys'
            foreach ($p in $sc.seeds) {
                $r.Tours++
                Say $p 'usr'
                $s = Api POST "/api/sessions/$($s.id)/messages" @{ message = $p }
                $t = @($s.turns)[-1]
                $ton = 'rep'
                foreach ($l in ("$($t.assistant)" -split "`r?`n")) { Say $l $ton; $ton = 'rep+' }
                Say ('{0:0.0} s, {1} jetons lus, {2} jetons écrits' -f ($t.duration_ms / 1000), $t.prompt_tokens, $t.output_tokens) 'info'
                if ($s.verdict -eq 'compromised') { break }
            }
            $r.Verdict = "$($s.verdict)"; $r.Raisons = @($s.findings | ForEach-Object { $_.reason })
        } catch { $r.Erreur = Read-ApiError $_ }
        $r
    } {
        param($r)
        $n = $r.Etape
        if ($r.Erreur) {
            Show-Flow ''
            Set-Verdict 'L''attaque n''a pas pu être jouée' $r.Erreur 'pb' 'À vérifier'
            return
        }
        $un = $r.Tours -le 1
        switch ($r.Verdict) {
            'compromised' {
                Show-Flow 'compromis'; Set-StepState $n 'compromis'
                Set-Verdict "Compromis : $($Raisons[$r.Raisons[0]])" "$(if ($un) { 'Un seul message a suffi' } else { "Il a fallu $($r.Tours) messages" }). Le vérificateur a retrouvé l'indicateur dans la réponse enregistrée par le serveur." 'compromis' $r.Owasp
            }
            'held' {
                Show-Flow 'tenu'; Set-StepState $n 'tenu'
                Set-Verdict 'Le modèle a tenu' "Aucun indicateur d'attaque détecté après $(if ($un) { 'un message' } else { "$($r.Tours) messages" }). Ce n'est pas une preuve de robustesse : une autre formulation peut passer." 'tenu' $r.Owasp
            }
            default {
                Show-Flow 'envoi'
                Set-Verdict 'Essai incomplet' 'Réponse coupée ou hors format : rejouez l''attaque avant de conclure.' 'pb' 'À rejouer'
            }
        }
    } @{ Etape = $n; Id = $e[1] }
}

function Open-Ihm {
    Start-Action 'Ouverture de l''IHM web' {
        $r = @{ Erreur = (Connect-Lab); Code = '' }
        if (-not $r.Erreur) { try { $r.Code = "$((Api POST '/api/handoff').code)" } catch { $r.Erreur = Read-ApiError $_ } }
        $r
    } {
        param($r)
        if ($r.Erreur) { Set-Verdict 'L''IHM web n''a pas pu s''ouvrir' $r.Erreur 'pb' 'À vérifier'; return }
        # Code à usage unique, valable une minute : aucun secret durable dans l'adresse ni dans le presse-papiers.
        Start-Process "$($sync.Base)/#code=$($r.Code)"
        Set-Verdict 'L''IHM web est ouverte dans le navigateur' "Adresse $($sync.Base), déjà connectée. On y trouve les cinq écrans de la soutenance, Gandalf et le classement OWASP." 'idle'
    }
}
function Open-Console([string]$h) {
    if ($Mode -ne 'admin') { return }
    Start-Process powershell.exe -WorkingDirectory $Root -ArgumentList "-NoExit -Command `$host.UI.RawUI.WindowTitle='Console $h'; ssh -F automation/ssh_config $h"
}

# ------------------------------------------------------------------ interface web de Proxmox par tunnel SSH
# Équivaut à : ssh -F automation/ssh_config -N -L 8006:127.0.0.1:8006 lab-host
$Pve = @{ Port = 8006; Proc = $null; Depuis = $null }
function Test-PortOuvert([int]$port) {
    [bool]([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() | Where-Object { $_.Port -eq $port })
}
function Update-Pve {
    if (Test-PortOuvert $Pve.Port) { $DotPve.Fill = $B.Sys; $TxtPve.Text = 'Proxmox ouvert' }
    elseif (-not $Pve.Depuis) { $DotPve.Fill = $B.Muted; $TxtPve.Text = 'Ouvrir Proxmox' }
}
function Open-Pve {
    if (Test-PortOuvert $Pve.Port) { Start-Process "https://localhost:$($Pve.Port)"; return }
    $Pve.Proc = Start-Process ssh -WorkingDirectory $Root -WindowStyle Hidden -PassThru -ArgumentList "-F automation/ssh_config -N -L $($Pve.Port):127.0.0.1:8006 -o ExitOnForwardFailure=yes lab-host"
    $Pve.Depuis = Get-Date
    $TxtPve.Text = 'Ouverture de Proxmox…'
}

# ------------------------------------------------------------------ boutons des étapes
$Etapes = @(
    @(1, 'S01', 'Injection directe', 'Demande frontale du code secret.'),
    @(2, 'S02', 'Usurpation d''autorité', 'Un faux administrateur donne l''ordre.'),
    @(3, 'S03', 'Extraction du prompt système', 'Recopier les instructions internes.'),
    @(4, 'S04', 'Escalade en plusieurs tours', 'Un rôle fictif, puis la vraie demande.'),
    @(5, 'S05', 'Rupture du format JSON', 'Faire sortir le modèle de son format.'),
    @(6, 'S06', 'Autorisation simulée', 'Obtenir APPROVED sans autorisation.'),
    @(7, 'S07', 'Injection dans un document', 'La consigne est cachée dans le texte.'),
    @(8, 'S08', 'Traduction et encodage', 'Demander le secret en base64.')
)
foreach ($e in $Etapes) {
    $x = @"
<Button xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Style="{DynamicResource Step}">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="44"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Border Width="30" Height="30" CornerRadius="15" BorderBrush="#101936" BorderThickness="1.5" VerticalAlignment="Top" HorizontalAlignment="Left" Margin="0,1,0,0">
      <TextBlock Text="$($e[0])" HorizontalAlignment="Center" VerticalAlignment="Center" FontWeight="SemiBold" FontSize="14"/>
    </Border>
    <StackPanel Grid.Column="1">
      <TextBlock Text="$([Security.SecurityElement]::Escape($e[2]))" FontSize="16" FontWeight="SemiBold"/>
      <TextBlock Text="$([Security.SecurityElement]::Escape($e[3]))" FontSize="13.5" Foreground="#4B5675" TextWrapping="Wrap" Margin="0,1,0,0"/>
    </StackPanel>
  </Grid>
</Button>
"@
    $btn = [Windows.Markup.XamlReader]::Parse($x)
    $btn.Tag = $e[0]
    $btn.Add_Click({ param($s, $ev) Invoke-Step ([int]$s.Tag) })
    [void]$Steps.Children.Add($btn)
    $StepButtons[[int]$e[0]] = $btn
}

# ------------------------------------------------------------------ état initial et événements
$TxtMode.Text = switch ($Mode) {
    'admin' { 'Clé d''administration détectée : le labo est piloté par tunnel SSH. Un clic sur « Serveur Proxmox » ou « Conteneur du labo » dans le schéma ouvre une console.' }
    'local' { "Mode local : le labo est joint directement sur $($sync.Base), sans passer par le serveur." }
    default { 'Aucune clé SSH trouvée (~/.ssh/id_ed25519_par861454). Les attaques ne peuvent pas être lancées depuis ce PC.' }
}
if ($Mode -eq 'aucun') { $ModeBox.Background = $B.ExtBg }
$BtnPve.ToolTip = 'Interface web du serveur Proxmox : https://localhost:8006 (ssh -L 8006:127.0.0.1:8006 lab-host)'
$BtnIhm.ToolTip = "IHM web du labo : $($sync.Base) (les cinq écrans de la soutenance, Gandalf et le classement OWASP)"
$BtnServer.ToolTip = 'Ouvrir une console SSH sur le serveur Proxmox (compte administrateur)'
if (-not $Cle) { $BtnPve.IsEnabled = $false; $BtnPve.ToolTip = 'Proxmox : réservé à la clé d''administration' }
if ($Mode -ne 'admin') { $BtnServer.IsEnabled = $false; $BtnServer.ToolTip = 'Console du serveur : réservée à la clé d''administration' }
Set-BusyState $false
Set-Verdict 'Prêt pour la démonstration' 'Commencez par « Vérifier le labo », puis jouez les attaques dans l''ordre.'

$BtnCheck.Add_Click({ if (-not $script:Job) { Set-Active 0; Start-Check } })
$BtnIhm.Add_Click({ Open-Ihm })
$BtnPve.Add_Click({ Open-Pve })
$BtnServer.Add_Click({ Open-Console 'lab-host' })
$BtnClear.Add_Click({ $Term.Document.Blocks.Clear() })
$BtnCopy.Add_Click({
    $t = (New-Object Windows.Documents.TextRange($Term.Document.ContentStart, $Term.Document.ContentEnd)).Text
    if ($t.Trim()) { [Windows.Clipboard]::SetText($t) }
})
$win.Add_PreviewKeyDown({
    param($s, $e)
    $k = $e.Key.ToString()
    if ($k -match '^(D|NumPad)([1-8])$') { Invoke-Step ([int]$Matches[2]); $e.Handled = $true }
    elseif ($k -eq 'F5' -and $Mode -ne 'aucun' -and -not $script:Job) { Set-Active 0; Start-Check; $e.Handled = $true }
})
$win.Add_Closing({
    if ($Pve.Proc -and -not $Pve.Proc.HasExited) { Stop-Process -Id $Pve.Proc.Id -ErrorAction SilentlyContinue }
    if ($sync.TunnelPid) { Stop-Process -Id $sync.TunnelPid -ErrorAction SilentlyContinue }
    if ($script:Job) { $script:Job.PS.Stop() }
})

$script:Ticks = 0
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(120)
$timer.Add_Tick({
    $item = $null
    while ($sync.Queue.TryDequeue([ref]$item)) { Add-Line $item[0] $item[1] }

    if ($script:Job -and $script:Job.Handle.IsCompleted) {
        $j = $script:Job; $script:Job = $null
        $res = $null; $err = ''
        try { $out = $j.PS.EndInvoke($j.Handle); if ($out.Count) { $res = $out[$out.Count - 1] } } catch { $err = $_.Exception.Message }
        $j.PS.Runspace.Dispose(); $j.PS.Dispose()
        Set-BusyState $false
        if ($res -is [hashtable]) { & $j.Fin $res }
        else { Show-Flow ''; Set-Verdict 'La commande n''a pas abouti' "$err" 'pb' 'À vérifier' }
    }

    if ($Pve.Depuis) {
        if (Test-PortOuvert $Pve.Port) {
            $Pve.Depuis = $null
            Start-Process "https://localhost:$($Pve.Port)"
            Set-Verdict 'Proxmox est ouvert dans le navigateur' 'Adresse https://localhost:8006, connectez-vous avec votre compte Proxmox. Le certificat est auto-signé : acceptez l''avertissement.' 'idle'
        } elseif ($Pve.Proc.HasExited -or ((Get-Date) - $Pve.Depuis).TotalSeconds -gt 15) {
            $Pve.Depuis = $null
            if (-not $Pve.Proc.HasExited) { Stop-Process -Id $Pve.Proc.Id -ErrorAction SilentlyContinue }
            Set-Verdict 'Proxmox n''a pas pu s''ouvrir' 'Le serveur refuse la connexion SSH, ou le port 8006 est déjà pris par un autre programme.' 'pb' 'À vérifier'
        }
        Update-Pve
    }
    if ((++$script:Ticks % 16) -eq 0 -or $script:Ticks -eq 1) { Update-Pve }
})
$timer.Start()
[void]$win.ShowDialog()
