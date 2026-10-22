#Requires -Version 7.0
[CmdletBinding()]
param([string]$ModelRoot = (Join-Path $PSScriptRoot 'models'))

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$appVersion = '0.16'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][System.Windows.Forms.Application]::SetHighDpiMode([System.Windows.Forms.HighDpiMode]::PerMonitorV2)
[System.Windows.Forms.Application]::EnableVisualStyles()

trap {
    $message = $_.Exception.Message
    $logDir = Join-Path $root 'codex\logs'
    try {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        Add-Content -LiteralPath (Join-Path $logDir 'controller-startup-error.log') -Value "$(Get-Date -Format o) $($_ | Out-String)"
    } catch { }
    try {
        [void][System.Windows.Forms.MessageBox]::Show(
            "KVMem Controller could not start.`r`n`r`n$message`r`n`r`nLog: $logDir",
            'KVMem Controller', 'OK', 'Error')
    } catch { }
    exit 1
}

$localizationModule = Join-Path $root 'KVMem-Localization.psm1'
if (!(Test-Path -LiteralPath $localizationModule -PathType Leaf)) { throw 'KVMem language resources are missing; re-extract the complete package.' }
Import-Module $localizationModule -Force
$languageFile = Join-Path $root 'codex\ui-language.json'
if (Test-Path -LiteralPath $languageFile -PathType Leaf) {
    try {
        $savedLanguage = (Get-Content -LiteralPath $languageFile -Raw | ConvertFrom-Json).Language
        if ($savedLanguage -in @('zh', 'en')) { Set-KVMemUiLanguage -Language $savedLanguage }
    } catch { Set-KVMemUiLanguage -Language 'zh' }
}

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
public static class KVMemModelScanner {
    public static Task<string[]> ScanAsync(string root) => Task.Run(() => Scan(root));
    public static Task<int> ReadLayerCountAsync(string path) => Task.Run(() => ReadLayerCount(path));
    private static string ReadString(BinaryReader r) {
        ulong len = r.ReadUInt64();
        if (len > 1048576) throw new InvalidDataException("GGUF metadata string is too long");
        return System.Text.Encoding.UTF8.GetString(r.ReadBytes((int)len));
    }
    private static object ReadValue(BinaryReader r, uint type, bool capture) {
        switch (type) {
            case 0: { byte v=r.ReadByte(); return capture?(object)v:null; }
            case 1: { sbyte v=r.ReadSByte(); return capture?(object)v:null; }
            case 2: { ushort v=r.ReadUInt16(); return capture?(object)v:null; }
            case 3: { short v=r.ReadInt16(); return capture?(object)v:null; }
            case 4: { uint v=r.ReadUInt32(); return capture?(object)v:null; }
            case 5: { int v=r.ReadInt32(); return capture?(object)v:null; }
            case 6: { float v=r.ReadSingle(); return capture?(object)v:null; }
            case 7: { byte v=r.ReadByte(); return capture?(object)(v!=0):null; }
            case 8: { string v=ReadString(r); return capture?v:null; }
            case 9: {
                uint elementType=r.ReadUInt32(); ulong count=r.ReadUInt64();
                if (count > 10000000) throw new InvalidDataException("GGUF metadata array is too large");
                for (ulong i=0;i<count;i++) ReadValue(r,elementType,false);
                return null;
            }
            case 10: { ulong v=r.ReadUInt64(); return capture?(object)v:null; }
            case 11: { long v=r.ReadInt64(); return capture?(object)v:null; }
            case 12: { double v=r.ReadDouble(); return capture?(object)v:null; }
            default: throw new InvalidDataException("Unknown GGUF metadata type " + type);
        }
    }
    private static int ReadLayerCount(string path) {
        using (var stream=File.OpenRead(path))
        using (var r=new BinaryReader(stream)) {
            if (r.ReadUInt32()!=0x46554747) throw new InvalidDataException("Not a GGUF file");
            uint version=r.ReadUInt32(); if(version<2 || version>3) throw new InvalidDataException("Unsupported GGUF version " + version);
            r.ReadUInt64(); ulong entries=r.ReadUInt64(); if(entries>1000000) throw new InvalidDataException("Invalid GGUF metadata count");
            string arch=null; var counts=new Dictionary<string,int>(StringComparer.Ordinal);
            for(ulong i=0;i<entries;i++) {
                string key=ReadString(r); uint type=r.ReadUInt32(); bool capture=key=="general.architecture" || key.EndsWith(".block_count",StringComparison.Ordinal);
                object value=ReadValue(r,type,capture);
                if(key=="general.architecture") arch=value as string;
                if(key.EndsWith(".block_count",StringComparison.Ordinal) && value!=null) counts[key]=Convert.ToInt32(value);
            }
            if(String.IsNullOrEmpty(arch)) throw new InvalidDataException("GGUF metadata has no general.architecture");
            int layers; if(!counts.TryGetValue(arch+".block_count",out layers) || layers<1) throw new InvalidDataException("GGUF metadata has no valid layer count for " + arch);
            return layers;
        }
    }
    private static string[] Scan(string root) {
        var files = new List<string>();
        var pending = new Stack<string>();
        pending.Push(root);
        while (pending.Count > 0) {
            var dir = pending.Pop();
            try {
                foreach (var file in Directory.GetFiles(dir, "*.gguf", SearchOption.TopDirectoryOnly)) {
                    if (!Path.GetFileNameWithoutExtension(file).Contains("mmproj", StringComparison.OrdinalIgnoreCase)) files.Add(file);
                }
            } catch { }
            try { foreach (var child in Directory.GetDirectories(dir)) pending.Push(child); } catch { }
        }
        files.Sort(StringComparer.OrdinalIgnoreCase);
        return files.ToArray();
    }
}
public static class KVMemStatusProbe {
    private static readonly HttpClient client = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };
    public static async Task<string> ProbeAsync() {
        try {
            using (var health = await client.GetAsync("http://127.0.0.1:18200/health")) {
                if (!health.IsSuccessStatusCode) return "";
            }
            using (var models = await client.GetAsync("http://127.0.0.1:18200/v1/models")) {
                if (!models.IsSuccessStatusCode) return "";
                var body = await models.Content.ReadAsStringAsync();
                using (var json = JsonDocument.Parse(body)) {
                    var data = json.RootElement.GetProperty("data");
                    if (data.GetArrayLength() == 0) return "\u0001NONE";
                    var model = data[0];
                    if (model.TryGetProperty("status", out var status) && status.TryGetProperty("value", out var value) && value.GetString() != "loaded") return "";
                    return model.TryGetProperty("id", out var id) ? id.GetString() : "\u0001NOID";
                }
            }
        } catch { return ""; }
    }
}
'@

function Show-LocalizedMessage([string]$Message, [string]$Caption = 'KVMem', [string]$Buttons = 'OK', [string]$Icon = 'Information') {
    return [Windows.Forms.MessageBox]::Show((Get-KVMemUiText $Message), (Get-KVMemUiText $Caption), $Buttons, $Icon)
}

$startScript = Join-Path $root 'Start-KVMem.ps1'
$stopScript = Join-Path $root 'Stop-KVMem.ps1'
$serverPath = [IO.Path]::GetFullPath((Join-Path $root 'runtime\bin\llama-kvmem-server.exe'))
$compatibilityModule = Join-Path $root 'KVMem-Compatibility.psm1'
if (!(Test-Path -LiteralPath $compatibilityModule -PathType Leaf)) {
    $missingModuleMessage = if ((Get-KVMemUiLanguage) -eq 'en') { "KVMem GPU compatibility checker is missing: $compatibilityModule`r`nRe-extract the complete portable package." } else { "缺少 KVMem 显卡兼容性检查模块：$compatibilityModule`r`n请重新解压完整的便携包。" }
    [void](Show-LocalizedMessage $missingModuleMessage 'KVMem 兼容性检查' 'OK' 'Error')
    exit 2
}
Import-Module $compatibilityModule -Force
$script:backendCompatibility = Get-KVMemBackendCompatibility -ServerPath $serverPath
if (!$script:backendCompatibility.Supported) {
    $compatibilityMessage = if ((Get-KVMemUiLanguage) -eq 'en') { $script:backendCompatibility.MessageEnglish } else { $script:backendCompatibility.Message }
    $compatibilityCaption = if ((Get-KVMemUiLanguage) -eq 'en') { 'No matching KVMem GGUF backend' } else { '没有匹配的 KVMem GGUF 后端' }
    [void](Show-LocalizedMessage $compatibilityMessage $compatibilityCaption 'OK' 'Error')
    exit 2
}

if ($ModelRoot -eq (Join-Path $root 'models') -and !(Test-Path -LiteralPath $ModelRoot -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $ModelRoot | Out-Null
}

$logsPath = Join-Path $root 'codex\logs'
$script:models = @()
$script:scanTask = $null
$script:statusTask = $null
$script:layerTask = $null
$script:layerPath = ''
$script:modelLayerCount = 0
$script:autoGpuState = 'idle'
$script:operationProcess = $null
$script:operationErrorFile = $null
$script:logWindow = $null
$script:noMatchNotified = $false
$script:suppressModelSelection = $false
$script:statusText = '状态：正在检查服务…'
$script:statusKind = 'idle'
$script:statusHoldUntil = [datetime]::MinValue
$script:nextProbeAt = [datetime]::MinValue
$script:lastAppliedLanguage = $null

# ---------------------------------------------------------------------------
# Theme
# ---------------------------------------------------------------------------
$script:Ui = @{
    Bg         = [Drawing.Color]::FromArgb(244, 246, 251)
    Card       = [Drawing.Color]::White
    Border     = [Drawing.Color]::FromArgb(226, 232, 240)
    Text       = [Drawing.Color]::FromArgb(30, 41, 59)
    Muted      = [Drawing.Color]::FromArgb(100, 116, 139)
    Accent     = [Drawing.Color]::FromArgb(37, 99, 235)
    AccentDark = [Drawing.Color]::FromArgb(29, 78, 216)
    AccentSoft = [Drawing.Color]::FromArgb(239, 246, 255)
    Header     = [Drawing.Color]::FromArgb(30, 64, 175)
    HeaderInk  = [Drawing.Color]::FromArgb(191, 219, 254)
    Success    = [Drawing.Color]::FromArgb(5, 150, 105)
    SuccessSoft= [Drawing.Color]::FromArgb(236, 253, 245)
    Warning    = [Drawing.Color]::FromArgb(180, 83, 9)
    WarningSoft= [Drawing.Color]::FromArgb(255, 251, 235)
    Danger     = [Drawing.Color]::FromArgb(220, 38, 38)
    DangerSoft = [Drawing.Color]::FromArgb(254, 242, 242)
}
$script:FontBody = [Drawing.Font]::new('Microsoft YaHei UI', 9.5)
$script:FontSmall = [Drawing.Font]::new('Microsoft YaHei UI', 8.5)
$script:FontBold = [Drawing.Font]::new('Microsoft YaHei UI', 11, [Drawing.FontStyle]::Bold)
$script:FontTitle = [Drawing.Font]::new('Microsoft YaHei UI', 19, [Drawing.FontStyle]::Bold)
$script:FontSubtitle = [Drawing.Font]::new('Microsoft YaHei UI', 9)
$script:FontStatus = [Drawing.Font]::new('Microsoft YaHei UI', 10)
$script:FontTab = [Drawing.Font]::new('Microsoft YaHei UI', 9.5)
$script:FontTabSelected = [Drawing.Font]::new('Microsoft YaHei UI', 9.5, [Drawing.FontStyle]::Bold)
$script:FontMono = [Drawing.Font]::new('Consolas', 9.5)

# Pixel sizes are authored at 96 DPI and scaled to the current monitor DPI, so the
# layout stays proportional on 125-200% displays without relying on WinForms autoscale.
function Px([double]$Value) { return [int][Math]::Round($Value * $script:Scale) }
function Pxf([double]$Value) { return [single]($Value * $script:Scale) }

function Enable-DoubleBuffer([Windows.Forms.Control]$Control) {
    $property = [Windows.Forms.Control].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic')
    if ($property) { $property.SetValue($Control, $true) }
}

function New-RoundedPath([Drawing.RectangleF]$Rect, [single]$Radius) {
    $path = [Drawing.Drawing2D.GraphicsPath]::new()
    $diameter = $Radius * 2
    $path.AddArc($Rect.X, $Rect.Y, $diameter, $diameter, 180, 90)
    $path.AddArc($Rect.Right - $diameter, $Rect.Y, $diameter, $diameter, 270, 90)
    $path.AddArc($Rect.Right - $diameter, $Rect.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($Rect.X, $Rect.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-CardPanel([int]$Pad = 16, [int]$Radius = 12, $Fill = $null, $Border = $null) {
    $panel = [Windows.Forms.Panel]::new()
    $panel.BackColor = $script:Ui.Bg
    $panel.Padding = [Windows.Forms.Padding]::new((Px $Pad))
    $panel.Margin = [Windows.Forms.Padding]::new(0, 0, 0, (Px 10))
    $panel.Tag = [pscustomobject]@{
        Radius = (Pxf $Radius)
        Fill   = if ($null -ne $Fill) { $Fill } else { $script:Ui.Card }
        Border = if ($null -ne $Border) { $Border } else { $script:Ui.Border }
    }
    Enable-DoubleBuffer $panel
    $panel.add_Paint({
            param($sender, $e)
            $info = $sender.Tag
            if (!$info) { return }
            $g = $e.Graphics
            $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $rect = [Drawing.RectangleF]::new(0.5, 0.5, $sender.Width - 1, $sender.Height - 1)
            $path = New-RoundedPath $rect ([single]$info.Radius)
            $brush = [Drawing.SolidBrush]::new($info.Fill)
            $pen = [Drawing.Pen]::new($info.Border, 1)
            $g.FillPath($brush, $path)
            $g.DrawPath($pen, $path)
            $brush.Dispose()
            $pen.Dispose()
            $path.Dispose()
        })
    $panel.add_Resize({ param($s, $e) $s.Invalidate() })
    return $panel
}

function New-UiLabel([string]$Text, $Color = $null, $Font = $null) {
    $label = [Windows.Forms.Label]::new()
    $label.Text = $Text
    $label.AutoSize = $true
    $label.UseMnemonic = $false
    $label.ForeColor = if ($null -ne $Color) { $Color } else { $script:Ui.Text }
    $label.BackColor = [Drawing.Color]::Transparent
    $label.Font = if ($null -ne $Font) { $Font } else { $script:FontBody }
    $label.Margin = [Windows.Forms.Padding]::new((Px 4), (Px 3), (Px 12), (Px 3))
    return $label
}

function New-UiButton([string]$Text, [string]$Kind = 'secondary', [int]$MinWidth = 0) {
    $button = [Windows.Forms.Button]::new()
    $button.Text = $Text
    $button.AutoSize = $true
    $button.AutoSizeMode = 'GrowAndShrink'
    $width = if ($MinWidth -gt 0) { $MinWidth } else { 108 }
    $button.MinimumSize = [Drawing.Size]::new((Px $width), (Px 32))
    $button.Padding = [Windows.Forms.Padding]::new((Px 12), 0, (Px 12), 0)
    $button.Margin = [Windows.Forms.Padding]::new(0, 0, (Px 8), 0)
    $button.Font = $script:FontBody
    $button.FlatStyle = 'Flat'
    $button.UseVisualStyleBackColor = $false
    $button.Cursor = 'Hand'

    switch ($Kind) {
        'primary' {
            $button.BackColor = $script:Ui.Accent
            $button.ForeColor = [Drawing.Color]::White
            $button.FlatAppearance.BorderColor = $script:Ui.Accent
            $button.FlatAppearance.MouseOverBackColor = $script:Ui.AccentDark
            $button.FlatAppearance.MouseDownBackColor = $script:Ui.AccentDark
        }
        'header' {
            $button.BackColor = [Drawing.Color]::White
            $button.ForeColor = $script:Ui.Header
            $button.FlatAppearance.BorderColor = [Drawing.Color]::White
            $button.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(219, 234, 254)
            $button.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(191, 219, 254)
        }
        'ghost' {
            $button.BackColor = $script:Ui.Card
            $button.ForeColor = $script:Ui.Accent
            $button.FlatAppearance.BorderSize = 0
            $button.FlatAppearance.MouseOverBackColor = $script:Ui.AccentSoft
            $button.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(219, 234, 254)
        }
        default {
            $button.BackColor = $script:Ui.Card
            $button.ForeColor = $script:Ui.Text
            $button.FlatAppearance.BorderColor = $script:Ui.Border
            $button.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(241, 245, 251)
            $button.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(226, 232, 240)
        }
    }
    return $button
}

function New-UiText([string]$Text = '', [bool]$ReadOnly = $false) {
    $box = [Windows.Forms.TextBox]::new()
    $box.Text = $Text
    $box.ReadOnly = $ReadOnly
    $box.BorderStyle = 'FixedSingle'
    $box.Font = $script:FontBody
    $box.BackColor = if ($ReadOnly) { [Drawing.Color]::FromArgb(248, 250, 252) } else { [Drawing.Color]::White }
    $box.ForeColor = if ($ReadOnly) { $script:Ui.Muted } else { $script:Ui.Text }
    $box.Margin = [Windows.Forms.Padding]::new((Px 4), (Px 3), (Px 4), (Px 3))
    return $box
}

# ---------------------------------------------------------------------------
# Form and layout
# ---------------------------------------------------------------------------
$form = [Windows.Forms.Form]::new()
$form.Text = 'KVMem 本地模型控制台'
$form.StartPosition = 'CenterScreen'
$form.ShowInTaskbar = $true
$form.AutoScaleMode = 'None'
$form.Font = $script:FontBody
$form.BackColor = $script:Ui.Bg
[void]$form.Handle
$script:Scale = [Math]::Round($form.DeviceDpi / 96.0, 2)
if ($script:Scale -lt 1) { $script:Scale = 1.0 }
$form.MinimumSize = [Drawing.Size]::new((Px 940), (Px 600))
$area = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.StartPosition = 'Manual'
$form.Size = [Drawing.Size]::new(
    [Math]::Min((Px 1180), $area.Width - (Px 24)),
    [Math]::Min((Px 1020), $area.Height - (Px 12)))
$form.MaximizeBox = $true
$form.KeyPreview = $true
$iconPath = Join-Path $root 'assets\kvmem.ico'
if (Test-Path -LiteralPath $iconPath -PathType Leaf) {
    try { $form.Icon = [Drawing.Icon]::new($iconPath) } catch { }
}
$tips = [Windows.Forms.ToolTip]::new()
$tips.AutoPopDelay = 20000
$tips.InitialDelay = 500
$tips.ReshowDelay = 100

$layout = [Windows.Forms.TableLayoutPanel]::new()
$layout.Dock = 'Fill'
$layout.Padding = [Windows.Forms.Padding]::new((Px 18), (Px 14), (Px 18), (Px 10))
$layout.ColumnCount = 1
$layout.RowCount = 8
[void]$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 100))
[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, (Px 84)))
[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, (Px 48)))
[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))
[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, 100))
[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))
[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))
[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, (Px 120)))
[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))
$form.Controls.Add($layout)

# Header ---------------------------------------------------------------------
$header = [Windows.Forms.Panel]::new()
$header.Dock = 'Fill'
$header.BackColor = $script:Ui.Header
$header.Margin = [Windows.Forms.Padding]::new(0, 0, 0, 12)
Enable-DoubleBuffer $header
$header.add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $glow = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(26, 255, 255, 255))
        $g.FillEllipse($glow, $sender.Width - (Px 220), -(Px 90), (Px 300), (Px 300))
        $g.FillEllipse($glow, $sender.Width - (Px 120), (Px 40), (Px 160), (Px 160))
        $glow.Dispose()
    })
$header.add_Resize({
        param($sender, $e)
        $rect = [Drawing.RectangleF]::new(0, 0, $sender.Width, $sender.Height)
        $path = New-RoundedPath $rect (Pxf 14)
        $old = $sender.Region
        $sender.Region = [Drawing.Region]::new($path)
        if ($old) { $old.Dispose() }
        $path.Dispose()
        $sender.Invalidate()
    })
$layout.Controls.Add($header, 0, 0)

$headerGrid = [Windows.Forms.TableLayoutPanel]::new()
$headerGrid.Dock = 'Fill'
$headerGrid.BackColor = $script:Ui.Header
$headerGrid.ColumnCount = 2
$headerGrid.RowCount = 1
$headerGrid.Padding = [Windows.Forms.Padding]::new((Px 24), (Px 10), (Px 20), (Px 8))
[void]$headerGrid.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 100))
[void]$headerGrid.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::AutoSize))
$header.Controls.Add($headerGrid)

$headerText = [Windows.Forms.TableLayoutPanel]::new()
$headerText.Dock = 'Fill'
$headerText.BackColor = $script:Ui.Header
$headerText.ColumnCount = 1
$headerText.RowCount = 2
[void]$headerText.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))
[void]$headerText.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))
$headerGrid.Controls.Add($headerText, 0, 0)
$title = New-UiLabel 'KVMem 模型控制台' ([Drawing.Color]::White) $script:FontTitle
$title.Margin = [Windows.Forms.Padding]::new(0, 0, 0, 2)
$headerText.Controls.Add($title, 0, 0)
$subtitle = New-UiLabel '本地 GGUF 推理 · 上下文缓存管理' $script:Ui.HeaderInk $script:FontSubtitle
$subtitle.Margin = [Windows.Forms.Padding]::new(2, 0, 0, 0)
$headerText.Controls.Add($subtitle, 0, 1)

$headerActions = [Windows.Forms.FlowLayoutPanel]::new()
$headerActions.Dock = 'Fill'
$headerActions.AutoSize = $true
$headerActions.FlowDirection = 'RightToLeft'
$headerActions.WrapContents = $false
$headerActions.BackColor = $script:Ui.Header
$headerActions.Margin = [Windows.Forms.Padding]::new(0)
$headerActions.Padding = [Windows.Forms.Padding]::new(0, 8, 0, 0)
$headerGrid.Controls.Add($headerActions, 1, 0)
$languageButton = New-UiButton 'English' 'header' 104
$languageButton.Margin = [Windows.Forms.Padding]::new(8, 0, 0, 0)
$headerActions.Controls.Add($languageButton)
$versionLabel = New-UiLabel "v$appVersion" ([Drawing.Color]::FromArgb(191, 219, 254)) $script:FontSmall
$versionLabel.BackColor = [Drawing.Color]::FromArgb(30, 58, 138)
$versionLabel.Padding = [Windows.Forms.Padding]::new(9, 4, 9, 4)
$versionLabel.Margin = [Windows.Forms.Padding]::new(0, 6, 0, 0)
$headerActions.Controls.Add($versionLabel)

# Status ---------------------------------------------------------------------
$statusCard = New-CardPanel 14 12
$statusCard.Dock = 'Fill'
$statusCard.Margin = [Windows.Forms.Padding]::new(0, 0, 0, (Px 10))
$statusCard.Padding = [Windows.Forms.Padding]::new((Px 14), (Px 6), (Px 14), (Px 8))
$layout.Controls.Add($statusCard, 0, 1)
$statusHost = [Windows.Forms.TableLayoutPanel]::new()
$statusHost.Dock = 'Fill'
$statusHost.ColumnCount = 1
$statusHost.RowCount = 2
$statusHost.BackColor = $script:Ui.Card
$statusHost.Margin = [Windows.Forms.Padding]::new(0)
[void]$statusHost.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 100))
[void]$statusHost.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, 100))
[void]$statusHost.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, (Px 4)))
$statusCard.Controls.Add($statusHost)
$status = [Windows.Forms.Label]::new()
$status.Dock = 'Fill'
$status.AutoSize = $false
$status.AutoEllipsis = $true
$status.UseMnemonic = $false
$status.TextAlign = 'MiddleLeft'
$status.Font = $script:FontStatus
$status.BackColor = $script:Ui.Card
$status.Margin = [Windows.Forms.Padding]::new(0)
$statusHost.Controls.Add($status, 0, 0)
$progress = [Windows.Forms.ProgressBar]::new()
$progress.Dock = 'Fill'
$progress.Style = 'Marquee'
$progress.MarqueeAnimationSpeed = 30
$progress.Visible = $false
$progress.Margin = [Windows.Forms.Padding]::new(0)
$statusHost.Controls.Add($progress, 0, 1)

# Model selection card -------------------------------------------------------
$modelCard = New-CardPanel 12 12
$modelCard.Dock = 'Fill'
$modelCard.AutoSize = $true
$modelCard.AutoSizeMode = 'GrowAndShrink'
$layout.Controls.Add($modelCard, 0, 2)

$modelTable = [Windows.Forms.TableLayoutPanel]::new()
$modelTable.Dock = 'Top'
$modelTable.AutoSize = $true
$modelTable.AutoSizeMode = 'GrowAndShrink'
$modelTable.BackColor = $script:Ui.Card
$modelTable.ColumnCount = 3
$modelTable.RowCount = 0
[void]$modelTable.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute, (Px 132)))
[void]$modelTable.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 100))
[void]$modelTable.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::AutoSize))
$modelCard.Controls.Add($modelTable)

$modelTable.RowCount = 1
[void]$modelTable.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))
$cardTitle = New-UiLabel '模型与目录' $script:Ui.Text $script:FontBold
$cardTitle.Margin = [Windows.Forms.Padding]::new(4, 0, 10, 0)
$cardSubtitle = New-UiLabel '选择要扫描的模型目录，或直接浏览单个 GGUF 文件。' $script:Ui.Muted $script:FontSmall
$cardSubtitle.Margin = [Windows.Forms.Padding]::new(0, 4, 4, 0)
$titleFlow = [Windows.Forms.FlowLayoutPanel]::new()
$titleFlow.AutoSize = $true
$titleFlow.WrapContents = $false
$titleFlow.BackColor = $script:Ui.Card
$titleFlow.Margin = [Windows.Forms.Padding]::new(0, 0, 0, 8)
$titleFlow.Controls.Add($cardTitle)
$titleFlow.Controls.Add($cardSubtitle)
$modelTable.Controls.Add($titleFlow, 0, 0)
$modelTable.SetColumnSpan($titleFlow, 3)

function Add-ModelRow([string]$Label, $InputControl, $Buttons) {
    $row = $modelTable.RowCount
    $modelTable.RowCount++
    [void]$modelTable.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))
    $modelTable.Controls.Add((New-UiLabel $Label), 0, $row)
    if ($InputControl -is [Windows.Forms.TextBox] -or $InputControl -is [Windows.Forms.ComboBox]) {
        $InputControl.Dock = 'Fill'
    }
    $modelTable.Controls.Add($InputControl, 1, $row)
    if ($Buttons) {
        $modelTable.Controls.Add($Buttons, 2, $row)
    } else {
        $modelTable.SetColumnSpan($InputControl, 2)
    }
}

$rootBox = New-UiText $ModelRoot
$rootBox.Margin = [Windows.Forms.Padding]::new(4, 2, 10, 2)
$folderButton = New-UiButton '选择目录…' 'secondary' 112
$folderButton.Margin = [Windows.Forms.Padding]::new(0, 2, 0, 2)
Add-ModelRow '模型目录' $rootBox $folderButton

$filterBox = New-UiText
$filterBox.PlaceholderText = '按文件名筛选本地 GGUF…'
$filterBox.Margin = [Windows.Forms.Padding]::new(4, 2, 10, 2)
$scanButton = New-UiButton '刷新列表' 'secondary' 112
$scanButton.Margin = [Windows.Forms.Padding]::new(0, 2, 0, 2)
Add-ModelRow '筛选模型' $filterBox $scanButton

$modelBox = [Windows.Forms.ComboBox]::new()
$modelBox.DropDownStyle = 'DropDownList'
$modelBox.DisplayMember = 'Label'
$modelBox.ValueMember = 'Path'
$modelBox.FlatStyle = 'Standard'
$modelBox.Font = $script:FontBody
$modelBox.Dock = 'Fill'
$modelBox.Margin = [Windows.Forms.Padding]::new(4, 2, 10, 2)
$modelBox.DropDownWidth = (Px 900)
$fileButton = New-UiButton '浏览 GGUF…' 'secondary' 112
$fileButton.Margin = [Windows.Forms.Padding]::new(0, 2, 0, 2)
Add-ModelRow 'GGUF 模型' $modelBox $fileButton

$modelPath = New-UiText '' $true
$modelPath.Margin = [Windows.Forms.Padding]::new(4, 2, 10, 2)
Add-ModelRow '所选文件' $modelPath $null

$mmPath = New-UiText '' $true
$mmPath.Margin = [Windows.Forms.Padding]::new(4, 2, 10, 2)
$mmButtons = [Windows.Forms.FlowLayoutPanel]::new()
$mmButtons.AutoSize = $true
$mmButtons.WrapContents = $false
$mmButtons.BackColor = $script:Ui.Card
$mmButtons.Margin = [Windows.Forms.Padding]::new(0)
$mmButton = New-UiButton '选择 mmproj…' 'secondary' 112
$mmButton.Margin = [Windows.Forms.Padding]::new(0, 2, 8, 2)
$mmClearButton = New-UiButton '清除' 'secondary' 72
$mmClearButton.Margin = [Windows.Forms.Padding]::new(0, 2, 0, 2)
$mmButtons.Controls.Add($mmButton)
$mmButtons.Controls.Add($mmClearButton)
Add-ModelRow '视觉投影（可选）' $mmPath $mmButtons

# Tabs -----------------------------------------------------------------------
$tabsCard = New-CardPanel 10 12
$tabsCard.Dock = 'Fill'
$tabsCard.Margin = [Windows.Forms.Padding]::new(0, 0, 0, 12)
$layout.Controls.Add($tabsCard, 0, 3)
$tabs = [Windows.Forms.TabControl]::new()
$tabs.Dock = 'Fill'
$tabs.DrawMode = 'OwnerDrawFixed'
$tabs.SizeMode = 'Fixed'
$tabs.ItemSize = [Drawing.Size]::new((Px 176), (Px 38))
$tabs.Font = $script:FontTab
$tabs.BackColor = $script:Ui.Card
$tabsCard.Controls.Add($tabs)

$tabs.add_DrawItem({
        param($sender, $e)
        $g = $e.Graphics
        $selected = ($e.Index -eq $sender.SelectedIndex)
        $fill = if ($selected) { $script:Ui.Card } else { [Drawing.Color]::FromArgb(241, 245, 249) }
        $brush = [Drawing.SolidBrush]::new($fill)
        $g.FillRectangle($brush, $e.Bounds)
        $brush.Dispose()
        $fore = if ($selected) { $script:Ui.Accent } else { $script:Ui.Muted }
        $font = if ($selected) { $script:FontTabSelected } else { $script:FontTab }
        $format = [Drawing.StringFormat]::new()
        $format.LineAlignment = 'Center'
        $format.Alignment = 'Near'
        $format.FormatFlags = [Drawing.StringFormatFlags]::NoWrap
        $format.Trimming = [Drawing.StringTrimming]::EllipsisCharacter
        $textRect = [Drawing.RectangleF]::new([single]($e.Bounds.X + (Px 16)), [single]$e.Bounds.Y, [single]($e.Bounds.Width - (Px 22)), [single]$e.Bounds.Height)
        $textBrush = [Drawing.SolidBrush]::new($fore)
        $g.DrawString([string]$sender.TabPages[$e.Index].Text, $font, $textBrush, $textRect, $format)
        if ($selected) {
            $accent = [Drawing.SolidBrush]::new($script:Ui.Accent)
            $g.FillRectangle($accent, $e.Bounds.X + (Px 10), $e.Bounds.Bottom - (Px 3), $e.Bounds.Width - (Px 20), (Px 3))
            $accent.Dispose()
        }
        $textBrush.Dispose()
        $format.Dispose()
    })

function New-ParameterPage([string]$Title, [string]$Description) {
    $page = [Windows.Forms.TabPage]::new($Title)
    $page.Padding = [Windows.Forms.Padding]::new((Px 16), (Px 12), (Px 16), (Px 12))
    $page.AutoScroll = $true
    $page.UseVisualStyleBackColor = $false
    $page.BackColor = $script:Ui.Card
    $table = [Windows.Forms.TableLayoutPanel]::new()
    $table.Dock = 'Top'
    $table.AutoSize = $true
    $table.AutoSizeMode = 'GrowAndShrink'
    $table.BackColor = $script:Ui.Card
    $table.ColumnCount = 4
    $table.RowCount = 1
    [void]$table.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute, (Px 250)))
    [void]$table.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 50))
    [void]$table.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute, (Px 250)))
    [void]$table.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 50))
    [void]$table.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))
    $descriptionLabel = New-UiLabel $Description $script:Ui.Muted $script:FontBody
    $descriptionLabel.MaximumSize = [Drawing.Size]::new((Px 1000), 0)
    $descriptionLabel.Margin = [Windows.Forms.Padding]::new((Px 4), 0, (Px 4), (Px 8))
    $table.Controls.Add($descriptionLabel, 0, 0)
    $table.SetColumnSpan($descriptionLabel, 4)
    $table.Tag = [pscustomobject]@{ NextSlot = 0 }
    $page.Controls.Add($table)
    [void]$tabs.TabPages.Add($page)
    return $table
}

function Add-Parameter($Table, [string]$Label, $Control, [string]$Help = '') {
    $state = $Table.Tag
    $slot = $state.NextSlot % 2
    $row = 1 + [math]::Floor($state.NextSlot / 2)
    if ($row -ge $Table.RowCount) {
        $Table.RowCount = $row + 1
        [void]$Table.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))
    }
    $labelColumn = $slot * 2
    $controlColumn = $labelColumn + 1
    $Table.Controls.Add((New-UiLabel $Label), $labelColumn, $row)
    $Control.Anchor = 'Left'
    $Control.Margin = [Windows.Forms.Padding]::new((Px 4), (Px 2), (Px 16), (Px 2))
    $Table.Controls.Add($Control, $controlColumn, $row)
    $state.NextSlot++
    if ($Help) { $tips.SetToolTip($Control, $Help) }
}

function Add-Numeric($Table, [string]$Text, [decimal]$Min, [decimal]$Max, [decimal]$Value, [int]$Decimals = 0, [decimal]$Step = 1) {
    $control = [Windows.Forms.NumericUpDown]::new()
    $control.Minimum = $Min
    $control.Maximum = $Max
    $control.DecimalPlaces = $Decimals
    $control.Value = $Value
    $control.Increment = $Step
    $control.ThousandsSeparator = $true
    $control.Width = (Px 190)
    $control.BorderStyle = 'FixedSingle'
    $control.Font = $script:FontBody
    $control.TextAlign = 'Right'
    Add-Parameter $Table $Text $control
    return $control
}

function Add-Choice($Table, [string]$Text, [string[]]$Items, [string]$Selected) {
    $control = [Windows.Forms.ComboBox]::new()
    $control.DropDownStyle = 'DropDownList'
    $control.FlatStyle = 'Standard'
    $control.Font = $script:FontBody
    $control.Width = (Px 190)
    [void]$control.Items.AddRange($Items)
    $control.SelectedItem = $Selected
    Add-Parameter $Table $Text $control
    return $control
}

$loadTable = New-ParameterPage '加载与显存' 'GPU 自动层数读取所选 GGUF；模型过大时可取消自动，手动降低层数。'
$gpuLayerControl = Add-Numeric $loadTable 'GPU 卸载层数' 0 512 0
$autoGpuCheck = [Windows.Forms.CheckBox]::new()
$autoGpuCheck.Text = '自动（选择模型后读取最大层数）'
$autoGpuCheck.AutoSize = $true
$autoGpuCheck.Checked = $true
$autoGpuCheck.Font = $script:FontBody
$autoGpuCheck.ForeColor = $script:Ui.Text
$autoGpuCheck.BackColor = $script:Ui.Card
$autoGpuCheck.Margin = [Windows.Forms.Padding]::new(4, 8, 10, 8)
Add-Parameter $loadTable '自动 GPU 层数' $autoGpuCheck
$gpuLayerControl.Enabled = $false
$flashControl = Add-Choice $loadTable 'Flash Attention' @('on', 'off', 'auto') 'on'
$loadModeControl = Add-Choice $loadTable '模型加载方式' @('auto', 'mmap', 'mlock', 'mmap+mlock', 'none', 'dio') 'auto'
$threadsControl = Add-Numeric $loadTable 'CPU 线程（0 = 自动）' 0 256 0
$threadsBatchControl = Add-Numeric $loadTable '批处理线程（0 = 跟随 CPU 线程）' 0 256 0
$batchControl = Add-Numeric $loadTable '逻辑批大小（batch）' 1 2048 256
$ubatchControl = Add-Numeric $loadTable '物理批大小（ubatch）' 1 2048 128

$kvTable = New-ParameterPage '上下文与 KV 缓存' '这些参数在下次启动或切换模型时生效。更大的上下文与缓存可能增加内存占用。'
$contextControl = Add-Numeric $kvTable '上下文长度（tokens）' 1024 262144 32768 0 1024
$kvTypeControl = Add-Choice $kvTable 'KV 缓存精度' @('f16', 'f32', 'q8_0', 'q5_0', 'q4_0') 'q5_0'
$budgetControl = Add-Numeric $kvTable 'KVMem GPU 缓存预算（tokens）' 0 262144 8192 0 128
$reserveControl = Add-Numeric $kvTable '生成预留（tokens）' 0 65536 2048 0 128
$cpuArenaControl = Add-Numeric $kvTable 'KVMem CPU 缓存（GiB）' 0 256 1

$samplingTable = New-ParameterPage '生成与采样' '这里设置服务默认值；客户端请求中的采样参数会覆盖对应的服务默认值。'
$maxTokensControl = Add-Numeric $samplingTable '最大生成长度（tokens，-1 = 不限）' -1 65536 2048 0 128
$temperatureControl = Add-Numeric $samplingTable '温度（Temperature）' 0 2 0.7 2 0.05
$topPControl = Add-Numeric $samplingTable 'Top-P' 0 1 0.8 2 0.05
$topKControl = Add-Numeric $samplingTable 'Top-K' 0 1000 20
$minPControl = Add-Numeric $samplingTable 'Min-P' 0 1 0 2 0.01
$repeatControl = Add-Numeric $samplingTable '重复惩罚' 0.1 3 1 2 0.05
$presenceControl = Add-Numeric $samplingTable '存在惩罚（Presence penalty）' -2 2 0 2 0.05
$frequencyControl = Add-Numeric $samplingTable '频率惩罚（Frequency penalty）' -2 2 0 2 0.05
$seedControl = Add-Numeric $samplingTable '随机种子（-1 = 随机）' -1 4294967295 -1
$thinkingControl = Add-Choice $samplingTable '思考模式' @('禁用思考', '模型默认') '禁用思考'

# API hint -------------------------------------------------------------------
$hintText = if ((Get-KVMemUiLanguage) -eq 'en') { "Client API: http://127.0.0.1:18200/v1    Model: kvmem-current`r`nGPU backend: $($script:backendCompatibility.SummaryEnglish)" } else { "客户端 API：http://127.0.0.1:18200/v1    模型：kvmem-current`r`nGPU 后端：$($script:backendCompatibility.Summary)" }
$hintCard = New-CardPanel 14 10 $script:Ui.AccentSoft ([Drawing.Color]::FromArgb(191, 219, 254))
$hintCard.Dock = 'Fill'
$hintCard.AutoSize = $true
$hintCard.AutoSizeMode = 'GrowAndShrink'
$hintCard.Margin = [Windows.Forms.Padding]::new(0, 0, 0, 12)
$layout.Controls.Add($hintCard, 0, 4)
$hint = New-UiLabel ("ⓘ  " + $hintText) ([Drawing.Color]::FromArgb(30, 64, 175)) $script:FontBody
$hint.BackColor = $script:Ui.AccentSoft
$hint.MaximumSize = [Drawing.Size]::new((Px 900), 0)
$hint.Margin = [Windows.Forms.Padding]::new(2, 2, 2, 2)
$hintCard.Controls.Add($hint)

# Actions --------------------------------------------------------------------
$actions = [Windows.Forms.FlowLayoutPanel]::new()
$actions.AutoSize = $true
$actions.Dock = 'Fill'
$actions.WrapContents = $true
$actions.BackColor = $script:Ui.Bg
$actions.Margin = [Windows.Forms.Padding]::new(0, 0, 0, 10)
$layout.Controls.Add($actions, 0, 5)
$action = New-UiButton '启动 / 切换模型' 'primary' 180
$action.Margin = [Windows.Forms.Padding]::new(0, 0, 10, 8)
$stopButton = New-UiButton '停止 KVMem' 'secondary' 130
$stopButton.Margin = [Windows.Forms.Padding]::new(0, 0, 10, 8)
$webButton = New-UiButton '打开 KVMem 页面' 'secondary' 160
$webButton.Margin = [Windows.Forms.Padding]::new(0, 0, 10, 8)
$logsButton = New-UiButton '查看运行日志' 'secondary' 140
$logsButton.Margin = [Windows.Forms.Padding]::new(0, 0, 10, 8)
$copyButton = New-UiButton '复制客户端地址' 'secondary' 140
$copyButton.Margin = [Windows.Forms.Padding]::new(0, 0, 10, 8)
foreach ($button in @($action, $stopButton, $webButton, $logsButton, $copyButton)) { $actions.Controls.Add($button) }

# Activity log ---------------------------------------------------------------
$feedbackCard = New-CardPanel 12 12
$feedbackCard.Dock = 'Fill'
$feedbackCard.Margin = [Windows.Forms.Padding]::new(0, 0, 0, 10)
$layout.Controls.Add($feedbackCard, 0, 6)
$feedbackGrid = [Windows.Forms.TableLayoutPanel]::new()
$feedbackGrid.Dock = 'Fill'
$feedbackGrid.BackColor = $script:Ui.Card
$feedbackGrid.ColumnCount = 1
$feedbackGrid.RowCount = 2
[void]$feedbackGrid.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))
[void]$feedbackGrid.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, 100))
$feedbackCard.Controls.Add($feedbackGrid)
$feedbackHeader = [Windows.Forms.TableLayoutPanel]::new()
$feedbackHeader.Dock = 'Fill'
$feedbackHeader.AutoSize = $true
$feedbackHeader.BackColor = $script:Ui.Card
$feedbackHeader.ColumnCount = 2
$feedbackHeader.RowCount = 1
[void]$feedbackHeader.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 100))
[void]$feedbackHeader.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::AutoSize))
$feedbackHeader.Margin = [Windows.Forms.Padding]::new(0, 0, 0, 6)
$feedbackGrid.Controls.Add($feedbackHeader, 0, 0)
$feedbackTitle = New-UiLabel '运行记录' $script:Ui.Text $script:FontBold
$feedbackTitle.Margin = [Windows.Forms.Padding]::new(2, 0, 0, 0)
$feedbackHeader.Controls.Add($feedbackTitle, 0, 0)
$clearLogButton = New-UiButton '清空记录' 'ghost' 84
$clearLogButton.MinimumSize = [Drawing.Size]::new((Px 84), (Px 28))
$clearLogButton.Margin = [Windows.Forms.Padding]::new(0)
$feedbackHeader.Controls.Add($clearLogButton, 1, 0)
$feedback = [Windows.Forms.RichTextBox]::new()
$feedback.Dock = 'Fill'
$feedback.ReadOnly = $true
$feedback.BorderStyle = 'None'
$feedback.BackColor = [Drawing.Color]::FromArgb(15, 23, 42)
$feedback.ForeColor = [Drawing.Color]::FromArgb(220, 230, 245)
$feedback.Font = $script:FontMono
$feedback.DetectUrls = $false
$feedback.HideSelection = $false
$feedback.WordWrap = $false
$feedback.ScrollBars = 'Both'
$feedback.Margin = [Windows.Forms.Padding]::new(0)
$feedbackGrid.Controls.Add($feedback, 0, 1)

# Footer ---------------------------------------------------------------------
$foot = New-UiLabel '提示：长文件路径可选中后复制；参数支持鼠标滚轮，页签内容不足时可向下滚动。' $script:Ui.Muted $script:FontSmall
$foot.Margin = [Windows.Forms.Padding]::new(2, 0, 2, 0)
$layout.Controls.Add($foot, 0, 7)

# ---------------------------------------------------------------------------
# UI state helpers
# ---------------------------------------------------------------------------
function Render-Status {
    $palettes = @{
        idle  = @{ Fore = $script:Ui.Muted; Fill = [Drawing.Color]::FromArgb(248, 250, 252); Border = $script:Ui.Border }
        busy  = @{ Fore = $script:Ui.Warning; Fill = $script:Ui.WarningSoft; Border = [Drawing.Color]::FromArgb(253, 230, 138) }
        warn  = @{ Fore = $script:Ui.Warning; Fill = $script:Ui.WarningSoft; Border = [Drawing.Color]::FromArgb(253, 230, 138) }
        ok    = @{ Fore = $script:Ui.Success; Fill = $script:Ui.SuccessSoft; Border = [Drawing.Color]::FromArgb(167, 243, 208) }
        error = @{ Fore = $script:Ui.Danger; Fill = $script:Ui.DangerSoft; Border = [Drawing.Color]::FromArgb(254, 202, 202) }
    }
    $palette = $palettes[$script:statusKind]
    if (!$palette) { $palette = $palettes['idle'] }
    $statusCard.Tag.Fill = $palette.Fill
    $statusCard.Tag.Border = $palette.Border
    $statusCard.Invalidate()
    $status.BackColor = $palette.Fill
    $statusHost.BackColor = $palette.Fill
    $status.ForeColor = $palette.Fore
    $status.Text = '●  ' + (Get-KVMemUiText $script:statusText)
    $progress.Visible = ($script:statusKind -eq 'busy')
}

function Set-UiStatus([string]$Text, [string]$Kind = 'idle', [int]$HoldSeconds = 0) {
    $script:statusText = $Text
    $script:statusKind = $Kind
    if ($HoldSeconds -gt 0) {
        $script:statusHoldUntil = (Get-Date).AddSeconds($HoldSeconds)
    } else {
        $script:statusHoldUntil = [datetime]::MinValue
    }
    Render-Status
}

function Render-AutoGpuText {
    $text = switch ($script:autoGpuState) {
        'reading' { '自动（正在读取模型最大层数…）' }
        'error' { '自动（无法读取层数；可手动设置）' }
        'done' { "自动（模型最大 $($script:modelLayerCount) 层）" }
        default { '自动（选择模型后读取最大层数）' }
    }
    $autoGpuCheck.Text = Get-KVMemUiText $text
}

function Write-UiFeedback([string]$Message) {
    $Message = Get-KVMemUiText $Message
    if ($feedback.TextLength -gt 200000) {
        $feedback.Select(0, 50000)
        $feedback.SelectedText = ''
    }
    $feedback.SelectionStart = $feedback.TextLength
    $feedback.SelectionLength = 0
    $feedback.SelectionColor = [Drawing.Color]::FromArgb(125, 140, 165)
    $feedback.AppendText("[$(Get-Date -Format HH:mm:ss)] ")
    $feedback.SelectionColor = [Drawing.Color]::FromArgb(220, 230, 245)
    $feedback.AppendText("$Message`r`n")
    $feedback.SelectionStart = $feedback.TextLength
    $feedback.ScrollToCaret()
}

function Update-LayoutWidths {
    $width = [Math]::Max(420, $form.ClientSize.Width - 110)
    $hint.MaximumSize = [Drawing.Size]::new($width, 0)
    $foot.MaximumSize = [Drawing.Size]::new($width, 0)
}

function Update-UiLanguage([Windows.Forms.Control]$RootControl) {
    $language = Get-KVMemUiLanguage
    $languageChanged = $script:lastAppliedLanguage -ne $language
    $pending = [Collections.Generic.Stack[Windows.Forms.Control]]::new()
    $pending.Push($RootControl)
    while ($pending.Count) {
        $control = $pending.Pop()
        if ($control -ne $languageButton -and !($control -is [Windows.Forms.TextBox])) {
            $newText = Get-KVMemUiText $control.Text
            if ($newText -cne $control.Text) { $control.Text = $newText }
            $tip = $tips.GetToolTip($control)
            if ($tip) {
                $newTip = Get-KVMemUiText $tip
                if ($newTip -cne $tip) { $tips.SetToolTip($control, $newTip) }
            }
        }
        if ($control -is [Windows.Forms.TextBox] -and $control.PlaceholderText) {
            $newPlaceholder = Get-KVMemUiText $control.PlaceholderText
            if ($newPlaceholder -cne $control.PlaceholderText) { $control.PlaceholderText = $newPlaceholder }
        }
        if ($languageChanged -and $control -is [Windows.Forms.ComboBox] -and $control -ne $modelBox -and !$control.DisplayMember) {
            $selected = $control.SelectedIndex
            $items = @()
            foreach ($item in $control.Items) { $items += Get-KVMemUiText ([string]$item) }
            $control.BeginUpdate()
            $control.Items.Clear()
            [void]$control.Items.AddRange([object[]]$items)
            if ($selected -ge 0 -and $selected -lt $control.Items.Count) { $control.SelectedIndex = $selected }
            $control.EndUpdate()
        }
        foreach ($child in $control.Controls) { $pending.Push($child) }
        if ($control -is [Windows.Forms.TabControl]) {
            foreach ($page in $control.TabPages) { $pending.Push($page) }
        }
    }
}

function Update-TabSizes {
    if (!$tabs.TabPages.Count) { return }
    $graphics = $tabs.CreateGraphics()
    $maxWidth = 0
    foreach ($page in $tabs.TabPages) {
        $size = $graphics.MeasureString([string]$page.Text, $script:FontTabSelected)
        if ($size.Width -gt $maxWidth) { $maxWidth = $size.Width }
    }
    $graphics.Dispose()
    $width = [int][Math]::Ceiling($maxWidth) + (Px 34)
    $width = [Math]::Max($width, (Px 130))
    $available = [Math]::Max((Px 130), [int](($tabs.ClientSize.Width - (Px 12)) / [Math]::Max(1, $tabs.TabPages.Count)))
    $width = [Math]::Min($width, $available)
    $tabs.ItemSize = [Drawing.Size]::new($width, (Px 36))
    $tabs.Invalidate()
}

function Apply-UiLanguage {
    $language = Get-KVMemUiLanguage
    Update-UiLanguage $form
    if ($script:logWindow -and !$script:logWindow.IsDisposed) { Update-UiLanguage $script:logWindow }
    $formText = Get-KVMemUiText $form.Text
    if ($formText -cne $form.Text) { $form.Text = $formText }
    $hintText = if ($language -eq 'en') {
        "Client API: http://127.0.0.1:18200/v1    Model: kvmem-current`r`nGPU backend: $($script:backendCompatibility.SummaryEnglish)"
    } else {
        "客户端 API：http://127.0.0.1:18200/v1    模型：kvmem-current`r`nGPU 后端：$($script:backendCompatibility.Summary)"
    }
    $hint.Text = 'ⓘ  ' + $hintText
    $languageButton.Text = if ($language -eq 'en') { '中文' } else { 'English' }
    Update-TabSizes
    Render-AutoGpuText
    Render-Status
    $script:lastAppliedLanguage = $language
}

function Invoke-UiAction([scriptblock]$Work, [switch]$Quiet) {
    try { & $Work }
    catch {
        $message = $_.Exception.Message
        Write-UiFeedback "操作失败：$message"
        New-Item -ItemType Directory -Force -Path $logsPath | Out-Null
        Add-Content -LiteralPath (Join-Path $logsPath 'controller-errors.log') -Value "$(Get-Date -Format o) $($_ | Out-String)"
        if (!$Quiet) { [void](Show-LocalizedMessage $message 'KVMem 操作失败' 'OK' 'Error') }
    }
}

# ---------------------------------------------------------------------------
# Runtime log viewer
# ---------------------------------------------------------------------------
function Show-ControllerLogs {
    if ($script:logWindow -and !$script:logWindow.IsDisposed) {
        $script:logWindow.WindowState = 'Normal'
        $script:logWindow.Activate()
        return
    }
    New-Item -ItemType Directory -Force -Path $logsPath | Out-Null
    $window = [Windows.Forms.Form]::new()
    $window.Text = Get-KVMemUiText 'KVMem 运行日志'
    $window.Size = [Drawing.Size]::new((Px 1000), (Px 660))
    $window.MinimumSize = [Drawing.Size]::new((Px 720), (Px 440))
    $window.StartPosition = 'CenterParent'
    $window.Font = $script:FontBody
    $window.BackColor = $script:Ui.Bg
    $window.Padding = [Windows.Forms.Padding]::new(14)
    if ($form.Icon) { $window.Icon = $form.Icon }
    $container = [Windows.Forms.TableLayoutPanel]::new()
    $container.Dock = 'Fill'
    $container.ColumnCount = 1
    $container.RowCount = 2
    $container.BackColor = $script:Ui.Bg
    [void]$container.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))
    [void]$container.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, 100))
    $window.Controls.Add($container)
    $toolbar = [Windows.Forms.FlowLayoutPanel]::new()
    $toolbar.AutoSize = $true
    $toolbar.Dock = 'Fill'
    $toolbar.WrapContents = $false
    $toolbar.BackColor = $script:Ui.Bg
    $toolbar.Margin = [Windows.Forms.Padding]::new(0, 0, 0, 8)
    $refreshLogs = New-UiButton (Get-KVMemUiText '刷新日志列表') 'secondary' 120
    $refreshLogs.Margin = [Windows.Forms.Padding]::new(0, 0, 10, 0)
    $toolbar.Controls.Add($refreshLogs)
    $logInfo = New-UiLabel (Get-KVMemUiText '选择左侧文件查看末尾 500 行；后台仍可继续写入日志。') $script:Ui.Muted $script:FontBody
    $logInfo.Margin = [Windows.Forms.Padding]::new(0, 7, 0, 0)
    $toolbar.Controls.Add($logInfo)
    $container.Controls.Add($toolbar, 0, 0)
    $split = [Windows.Forms.SplitContainer]::new()
    $split.Dock = 'Fill'
    $split.BackColor = $script:Ui.Border
    $split.SplitterWidth = (Px 6)
    $split.Margin = [Windows.Forms.Padding]::new(0)
    $container.Controls.Add($split, 0, 1)
    $list = [Windows.Forms.ListBox]::new()
    $list.Dock = 'Fill'
    $list.BorderStyle = 'FixedSingle'
    $list.BackColor = $script:Ui.Card
    $list.ForeColor = $script:Ui.Text
    $list.Font = $script:FontBody
    $list.IntegralHeight = $false
    $list.DisplayMember = 'Name'
    $list.HorizontalScrollbar = $true
    $list.HorizontalExtent = (Px 430)
    $viewer = [Windows.Forms.RichTextBox]::new()
    $viewer.Dock = 'Fill'
    $viewer.ReadOnly = $true
    $viewer.BorderStyle = 'None'
    $viewer.BackColor = [Drawing.Color]::FromArgb(15, 23, 42)
    $viewer.ForeColor = [Drawing.Color]::FromArgb(220, 230, 245)
    $viewer.Font = $script:FontMono
    $viewer.WordWrap = $false
    $viewer.ScrollBars = 'Both'
    $viewer.DetectUrls = $false
    $split.Panel1.Controls.Add($list)
    $split.Panel2.Controls.Add($viewer)
    $list.Tag = $viewer
    $refreshLogs.Tag = $list
    $list.add_SelectedIndexChanged({
            param($sender, $eventArgs)
            if (!$sender.SelectedItem) { return }
            try {
                $text = (Get-Content -LiteralPath $sender.SelectedItem.FullName -Tail 500 -ErrorAction Stop) -join "`r`n"
                if ([string]::IsNullOrWhiteSpace($text)) { $text = Get-KVMemUiText '日志文件为空。' }
                $sender.Tag.Text = $text
            } catch {
                $sender.Tag.Text = Get-KVMemUiText '日志文件读取失败'
            }
            $sender.Tag.SelectionStart = $sender.Tag.TextLength
            $sender.Tag.ScrollToCaret()
        })
    $refreshLogs.add_Click({
            param($sender, $eventArgs)
            Invoke-UiAction {
                $target = $sender.Tag
                $target.BeginUpdate()
                $target.Items.Clear()
                foreach ($file in @(Get-ChildItem -LiteralPath $logsPath -Filter '*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 80)) {
                    [void]$target.Items.Add($file)
                }
                $target.EndUpdate()
                if ($target.Items.Count) {
                    $target.SelectedIndex = 0
                } else {
                    $target.Tag.Text = Get-KVMemUiText '暂无日志；启动模型后会产生运行日志。'
                }
            }
        })
    $script:logWindow = $window
    $window.add_FormClosed({ $script:logWindow = $null })
    $window.Show($form)
    # Splitter limits can only be applied once the window has a real size.
    try {
        $split.Panel1MinSize = (Px 200)
        $split.Panel2MinSize = (Px 260)
        $desired = (Px 330)
        $max = $split.Width - $split.Panel2MinSize - $split.SplitterWidth
        if ($max -gt $split.Panel1MinSize) { $split.SplitterDistance = [Math]::Min($desired, $max) }
    } catch { }
    $refreshLogs.PerformClick()
    Write-UiFeedback '已打开运行日志窗口。可选择 stdout、stderr 或控制器错误日志。'
}

# ---------------------------------------------------------------------------
# Controller operations
# ---------------------------------------------------------------------------
function Update-Status {
    $now = Get-Date
    if ($script:statusTask -and $script:statusTask.IsCompleted) {
        try { $id = [string]$script:statusTask.GetAwaiter().GetResult() } catch { $id = '' }
        $script:statusTask = $null
        if ($script:operationProcess -and !$script:operationProcess.HasExited) { return }
        if ($now -lt $script:statusHoldUntil) { return }
        if ($id -eq "`u{1}NONE") {
            Set-UiStatus '状态：服务运行中（无已加载模型）' 'warn'
        } elseif ($id -eq "`u{1}NOID") {
            Set-UiStatus '状态：服务运行中（未返回模型 ID）' 'warn'
        } elseif ($id) {
            Set-UiStatus "状态：运行中 · 模型：$id" 'ok'
        } else {
            Set-UiStatus '状态：未就绪（服务未启动或正在加载模型）' 'idle'
        }
    }
    if (!$script:statusTask -and $now -ge $script:nextProbeAt) {
        $script:statusTask = [KVMemStatusProbe]::ProbeAsync()
        $script:nextProbeAt = $now.AddSeconds(2)
    }
}

function Quote-PsLiteral([string]$Value) { "'" + $Value.Replace("'", "''") + "'" }

function Start-ControllerOperation([string]$Body, [string]$Label, [string]$Kind = 'start') {
    if ($script:operationProcess -and !$script:operationProcess.HasExited) {
        [void](Show-LocalizedMessage '已有启动或停止操作正在执行。' 'KVMem' 'OK' 'Information')
        return
    }
    New-Item -ItemType Directory -Force -Path $logsPath | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $taskFile = Join-Path $logsPath "controller-operation-$stamp.ps1"
    $outFile = Join-Path $logsPath "controller-operation-$stamp.stdout.log"
    $errFile = Join-Path $logsPath "controller-operation-$stamp.stderr.log"
    [IO.File]::WriteAllText($taskFile, "`$ErrorActionPreference='Stop'`r`n$Body`r`n", [Text.UTF8Encoding]::new($true))
    $pwsh = Join-Path $root '.tools\pwsh\pwsh.exe'
    if (!(Test-Path -LiteralPath $pwsh)) { $pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source }
    $process = Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ("`"$taskFile`"")) -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput $outFile -RedirectStandardError $errFile -PassThru
    $script:operationProcess = $process
    $script:operationLabel = $Label
    $script:operationKind = $Kind
    $script:operationErrorFile = $errFile
    $action.Enabled = $false
    $stopButton.Enabled = $false
    Set-UiStatus "状态：$Label …" 'busy' 4
    Write-UiFeedback "$Label；详情记录在 $outFile"
}

function Update-Operation {
    if (!$script:operationProcess -or !$script:operationProcess.HasExited) { return }
    $exit = $script:operationProcess.ExitCode
    $script:operationProcess.Dispose()
    $script:operationProcess = $null
    $action.Enabled = $true
    $stopButton.Enabled = $true
    if ($exit -eq 0) {
        if ($script:operationKind -eq 'stop') {
            Set-UiStatus '状态：KVMem 已停止' 'idle' 4
            Write-UiFeedback 'KVMem 已停止。'
        } else {
            Set-UiStatus '状态：操作命令已完成，等待服务就绪' 'busy' 4
            Write-UiFeedback '命令已完成。模型加载可能需要一段时间，服务就绪后状态会显示运行中。'
        }
    } else {
        Set-UiStatus "状态：操作失败（退出码 $exit）" 'error' 10
        $detail = if ($script:operationErrorFile -and (Test-Path -LiteralPath $script:operationErrorFile)) { Get-Content -LiteralPath $script:operationErrorFile -Raw } else { '没有错误输出' }
        Write-UiFeedback "操作失败：$detail"
    }
    $script:operationErrorFile = $null
    $script:operationKind = $null
}

function Render-Models {
    $previous = $modelPath.Text
    $term = $filterBox.Text.Trim()
    $script:suppressModelSelection = $true
    try {
        $modelBox.BeginUpdate()
        $modelBox.Items.Clear()
        foreach ($m in $script:models) {
            if (!$term -or $m.Label.IndexOf($term, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                [void]$modelBox.Items.Add($m)
            }
        }
        $modelBox.EndUpdate()
        for ($i = 0; $i -lt $modelBox.Items.Count; $i++) {
            if ($modelBox.Items[$i].Path -eq $previous) { $modelBox.SelectedIndex = $i; break }
        }
        # Only auto-select when nothing was selected before. A manually browsed file that is
        # outside the scanned folder must survive a refresh.
        if ($modelBox.Items.Count -gt 0 -and $modelBox.SelectedIndex -lt 0 -and !$previous) {
            $modelBox.SelectedIndex = 0
        }
    } finally {
        $script:suppressModelSelection = $false
    }
    if ($modelBox.SelectedItem -and !$modelPath.Text -and $modelBox.SelectedItem.Path) {
        $modelPath.Text = $modelBox.SelectedItem.Path
        Start-LayerScan $modelBox.SelectedItem.Path
    }
    if ($modelBox.Items.Count -eq 0) {
        if (!$script:noMatchNotified) {
            Write-UiFeedback '没有匹配的模型。可修改筛选文字，或使用“浏览 GGUF”。'
            $script:noMatchNotified = $true
        }
    } else {
        $script:noMatchNotified = $false
    }
}

function Start-ModelScan {
    if ($script:scanTask -and !$script:scanTask.IsCompleted) {
        Write-UiFeedback '正在扫描模型，请稍候。'
        return
    }
    $scanRoot = $rootBox.Text.Trim()
    if (!(Test-Path -LiteralPath $scanRoot -PathType Container)) {
        [void](Show-LocalizedMessage "找不到目录：`n$scanRoot" 'KVMem' 'OK' 'Warning')
        return
    }
    $scanButton.Enabled = $false
    Set-UiStatus '状态：正在扫描 GGUF 模型…' 'busy' 5
    $script:scanTask = [KVMemModelScanner]::ScanAsync($scanRoot)
}

function Complete-ModelScan {
    if (!$script:scanTask -or !$script:scanTask.IsCompleted) { return }
    $scanTask = $script:scanTask
    $script:scanTask = $null
    $scanButton.Enabled = $true
    if ($scanTask.IsFaulted) {
        Set-UiStatus '状态：扫描失败' 'error' 10
        [void](Show-LocalizedMessage $scanTask.Exception.GetBaseException().Message '模型扫描失败' 'OK' 'Error')
        return
    }
    $script:models = @($scanTask.Result | ForEach-Object {
            $f = [IO.FileInfo]::new($_)
            $size = if ($f.Length -ge 1GB) { "$([math]::Round($f.Length / 1GB, 2)) GiB" }
                    elseif ($f.Length -ge 1MB) { "$([math]::Round($f.Length / 1MB, 1)) MiB" }
                    else { "$([math]::Round($f.Length / 1KB, 0)) KiB" }
            [pscustomobject]@{ Label = "$($f.BaseName) · $size"; Path = $f.FullName }
        })
    Render-Models
    if ($script:models.Count -gt 0) {
        Set-UiStatus "状态：就绪，共找到 $($script:models.Count) 个 GGUF 模型" 'idle' 3
    } else {
        Set-UiStatus '状态：就绪，未找到 GGUF 模型' 'idle' 3
    }
    Write-UiFeedback "扫描完成：找到 $($script:models.Count) 个 GGUF 模型。"
}

function Start-LayerScan([string]$Path) {
    $script:layerTask = $null
    $script:layerPath = $Path
    $script:modelLayerCount = 0
    if (!$Path) {
        $script:autoGpuState = 'idle'
        Render-AutoGpuText
        return
    }
    $script:autoGpuState = 'reading'
    Render-AutoGpuText
    $script:layerTask = [KVMemModelScanner]::ReadLayerCountAsync($Path)
}

function Complete-LayerScan {
    if (!$script:layerTask -or !$script:layerTask.IsCompleted) { return }
    $task = $script:layerTask
    $script:layerTask = $null
    if ($task.IsFaulted) {
        $script:autoGpuState = 'error'
        Render-AutoGpuText
        return
    }
    $script:modelLayerCount = [int]$task.Result
    $script:autoGpuState = 'done'
    Render-AutoGpuText
    if ($autoGpuCheck.Checked) {
        $gpuLayerControl.Value = [math]::Min([decimal]$script:modelLayerCount, $gpuLayerControl.Maximum)
    }
}

# ---------------------------------------------------------------------------
# Event wiring
# ---------------------------------------------------------------------------
$filterTimer = [Windows.Forms.Timer]::new()
$filterTimer.Interval = 180
$filterTimer.add_Tick({ $filterTimer.Stop(); Invoke-UiAction -Quiet { Render-Models } })
$filterBox.add_TextChanged({ $filterTimer.Stop(); $filterTimer.Start() })
$modelBox.add_SelectedIndexChanged({
        if ($script:suppressModelSelection) { return }
        if ($modelBox.SelectedItem) {
            $modelPath.Text = $modelBox.SelectedItem.Path
            Start-LayerScan $modelBox.SelectedItem.Path
        }
    })
$autoGpuCheck.add_CheckedChanged({
        $gpuLayerControl.Enabled = !$autoGpuCheck.Checked
        if ($autoGpuCheck.Checked -and $script:modelLayerCount -gt 0) {
            $gpuLayerControl.Value = [math]::Min([decimal]$script:modelLayerCount, $gpuLayerControl.Maximum)
        }
    })
$scanButton.add_Click({ Invoke-UiAction { Start-ModelScan } })
$folderButton.add_Click({ Invoke-UiAction {
            $dialog = [Windows.Forms.FolderBrowserDialog]::new()
            try {
                $dialog.Description = Get-KVMemUiText '选择要扫描 GGUF 模型的目录'
                $dialog.SelectedPath = $rootBox.Text
                if ($dialog.ShowDialog($form) -eq 'OK') {
                    $rootBox.Text = $dialog.SelectedPath
                    Start-ModelScan
                }
            } finally { $dialog.Dispose() }
        } })
$fileButton.add_Click({ Invoke-UiAction {
            $dialog = [Windows.Forms.OpenFileDialog]::new()
            try {
                $dialog.Title = Get-KVMemUiText '选择任意 GGUF 模型'
                $dialog.Filter = Get-KVMemUiText 'GGUF 模型 (*.gguf)|*.gguf|所有文件 (*.*)|*.*'
                $dialog.CheckFileExists = $true
                if ($dialog.ShowDialog($form) -eq 'OK') {
                    $modelBox.SelectedIndex = -1
                    $modelPath.Text = $dialog.FileName
                    Start-LayerScan $dialog.FileName
                }
            } finally { $dialog.Dispose() }
        } })
$mmButton.add_Click({ Invoke-UiAction {
            $dialog = [Windows.Forms.OpenFileDialog]::new()
            try {
                $dialog.Title = Get-KVMemUiText '选择视觉投影文件（可选）'
                $dialog.Filter = Get-KVMemUiText 'mmproj 文件 (*.gguf)|*.gguf|所有文件 (*.*)|*.*'
                $dialog.CheckFileExists = $true
                if ($dialog.ShowDialog($form) -eq 'OK') { $mmPath.Text = $dialog.FileName }
            } finally { $dialog.Dispose() }
        } })
$mmClearButton.add_Click({ $mmPath.Clear(); Write-UiFeedback '已清除视觉投影文件。' })
$modelPath.add_TextChanged({ $tips.SetToolTip($modelPath, $modelPath.Text) })
$mmPath.add_TextChanged({ $tips.SetToolTip($mmPath, $mmPath.Text) })

$action.add_Click({ Invoke-UiAction {
            $model = $modelPath.Text.Trim()
            if (!(Test-Path -LiteralPath $model -PathType Leaf) -or [IO.Path]::GetExtension($model) -ne '.gguf') {
                [void](Show-LocalizedMessage '请先选择一个存在的 GGUF 文件。' 'KVMem' 'OK' 'Warning')
                return
            }
            if ($autoGpuCheck.Checked -and ($script:layerPath -ne $model -or $script:modelLayerCount -lt 1)) {
                [void](Show-LocalizedMessage '正在读取该 GGUF 的层数，或元数据无法识别。请稍候，或取消自动并手动设置 GPU 层数。' 'KVMem' 'OK' 'Warning')
                return
            }
            $mm = $mmPath.Text.Trim()
            if ($mm -and !(Test-Path -LiteralPath $mm -PathType Leaf)) {
                [void](Show-LocalizedMessage "找不到 mmproj：`n$mm" 'KVMem' 'OK' 'Warning')
                return
            }
            $listener = Get-NetTCPConnection -State Listen -LocalPort 18200 -ErrorAction SilentlyContinue | Select-Object -First 1
            $body = "`$ErrorActionPreference='Stop'`r`n"
            if ($listener) {
                $owner = Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)" -ErrorAction SilentlyContinue
                if (!$owner -or ![string]::Equals($owner.ExecutablePath, $serverPath, [StringComparison]::OrdinalIgnoreCase)) {
                    [void](Show-LocalizedMessage "18200 端口由其他程序使用（PID $($listener.OwningProcess)），未做更改。" '端口冲突' 'OK' 'Warning')
                    return
                }
                if ((Show-LocalizedMessage '当前模型将停止并切换到所选模型。继续？' '切换模型' 'YesNo' 'Question') -ne 'Yes') { return }
                $body += "& $(Quote-PsLiteral $stopScript)`r`n`$until=(Get-Date).AddSeconds(30)`r`nwhile((Get-Date) -lt `$until -and (Get-NetTCPConnection -State Listen -LocalPort 18200 -ErrorAction SilentlyContinue)){Start-Sleep -Milliseconds 250}`r`nif(Get-NetTCPConnection -State Listen -LocalPort 18200 -ErrorAction SilentlyContinue){throw '旧服务未释放 18200 端口'}`r`n"
            }
            $gpuLayers = if ($autoGpuCheck.Checked) { $script:modelLayerCount } else { [int]$gpuLayerControl.Value }
            $inv = [Globalization.CultureInfo]::InvariantCulture
            $disableThinking = if ($thinkingControl.SelectedIndex -eq 0) { '$true' } else { '$false' }
            $body += "& $(Quote-PsLiteral $startScript) -Model $(Quote-PsLiteral $model) -ModelAlias 'kvmem-current' -Context $([int]$contextControl.Value) -GpuLayers $gpuLayers -KvmemBudget $([int]$budgetControl.Value) -GenerationReserve $([int]$reserveControl.Value) -CpuMemoryGiB $([int]$cpuArenaControl.Value) -BatchSize $([int]$batchControl.Value) -UBatchSize $([int]$ubatchControl.Value) -Threads $([int]$threadsControl.Value) -ThreadsBatch $([int]$threadsBatchControl.Value) -KvDtype '$($kvTypeControl.SelectedItem)' -FlashAttention '$($flashControl.SelectedItem)' -LoadMode '$($loadModeControl.SelectedItem)' -MaxTokens $([int]$maxTokensControl.Value) -Temperature $($temperatureControl.Value.ToString($inv)) -TopP $($topPControl.Value.ToString($inv)) -TopK $([int]$topKControl.Value) -MinP $($minPControl.Value.ToString($inv)) -RepeatPenalty $($repeatControl.Value.ToString($inv)) -PresencePenalty $($presenceControl.Value.ToString($inv)) -FrequencyPenalty $($frequencyControl.Value.ToString($inv)) -Seed $([long]$seedControl.Value) -DisableThinking:$disableThinking"
            if ($mm) { $body += " -Mmproj $(Quote-PsLiteral $mm)" }
            Start-ControllerOperation $body "正在加载 $([IO.Path]::GetFileName($model))"
        } })

$stopButton.add_Click({ Invoke-UiAction {
            $listener = Get-NetTCPConnection -State Listen -LocalPort 18200 -ErrorAction SilentlyContinue | Select-Object -First 1
            if (!$listener) {
                Set-UiStatus '状态：KVMem 已停止' 'idle' 4
                Write-UiFeedback 'KVMem 当前没有运行，无需停止。'
                return
            }
            $owner = Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)" -ErrorAction SilentlyContinue
            if (!$owner -or ![string]::Equals($owner.ExecutablePath, $serverPath, [StringComparison]::OrdinalIgnoreCase)) {
                [void](Show-LocalizedMessage "18200 端口属于其他程序（PID $($listener.OwningProcess)），已取消。" 'KVMem' 'OK' 'Warning')
                return
            }
            Start-ControllerOperation "& $(Quote-PsLiteral $stopScript)" '正在停止 KVMem' 'stop'
        } })

$webButton.add_Click({ Invoke-UiAction {
            if (![Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners().Where({ $_.Port -eq 18200 }).Count) {
                Write-UiFeedback '请先启动模型；模型加载完成后才能打开 KVMem 页面。'
                return
            }
            $info = [Diagnostics.ProcessStartInfo]::new('http://127.0.0.1:18200/')
            $info.UseShellExecute = $true
            [void][Diagnostics.Process]::Start($info)
        } })
$logsButton.add_Click({ Invoke-UiAction { Show-ControllerLogs } })
$copyButton.add_Click({ Invoke-UiAction {
            [Windows.Forms.Clipboard]::SetText('http://127.0.0.1:18200/v1')
            Write-UiFeedback '已复制客户端 API 地址。模型 ID：kvmem-current'
        } })
$clearLogButton.add_Click({ $feedback.Clear(); Write-UiFeedback '已清空运行记录。' })

$languageButton.add_Click({ Invoke-UiAction {
            $next = if ((Get-KVMemUiLanguage) -eq 'en') { 'zh' } else { 'en' }
            Set-KVMemUiLanguage -Language $next
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $languageFile) | Out-Null
            [IO.File]::WriteAllText($languageFile, (ConvertTo-Json @{ Language = $next } -Compress), [Text.UTF8Encoding]::new($false))
            Apply-UiLanguage
        } })

$timer = [Windows.Forms.Timer]::new()
$timer.Interval = 500
$timer.add_Tick({ Invoke-UiAction -Quiet { Update-Status; Complete-ModelScan; Complete-LayerScan; Update-Operation } })

$form.add_Resize({ Update-LayoutWidths; Update-TabSizes })
$form.add_KeyDown({
        param($sender, $e)
        if ($e.Control -and $e.KeyCode -eq [Windows.Forms.Keys]::Enter -and $action.Enabled) {
            $e.SuppressKeyPress = $true
            $action.PerformClick()
        } elseif ($e.KeyCode -eq [Windows.Forms.Keys]::F5) {
            $e.SuppressKeyPress = $true
            $scanButton.PerformClick()
        }
    })
$form.add_Shown({
        $form.WindowState = [Windows.Forms.FormWindowState]::Normal
        # Center on the monitor's working area in device pixels; some DPI/host combinations
        # place a manually sized window partly off-screen.
        $work = [Windows.Forms.Screen]::FromControl($form).WorkingArea
        $x = $work.Left + [Math]::Max(0, [int](($work.Width - $form.Width) / 2))
        $y = $work.Top + [Math]::Max(0, [int](($work.Height - $form.Height) / 2))
        $form.Location = [Drawing.Point]::new($x, $y)
        $form.Activate()
        $form.BringToFront()
        Update-LayoutWidths
        Update-TabSizes
        Start-ModelScan
        $timer.Start()
    })
$form.add_FormClosing({
        $timer.Stop()
        $filterTimer.Stop()
        $timer.Dispose()
        $filterTimer.Dispose()
        $tips.Dispose()
    })

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class KVMemConsoleWindow {
    [DllImport("kernel32.dll")] private static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() { var h = GetConsoleWindow(); if (h != IntPtr.Zero) ShowWindow(h, 0); }
}
'@
[KVMemConsoleWindow]::Hide()

Apply-UiLanguage
Render-AutoGpuText
Render-Status
[void][Windows.Forms.Application]::Run($form)
