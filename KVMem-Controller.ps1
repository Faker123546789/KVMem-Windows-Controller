#Requires -Version 7.0
[CmdletBinding()]
param([string]$ModelRoot = (Join-Path $PSScriptRoot 'models'))

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$localizationModule = Join-Path $root 'KVMem-Localization.psm1'
if (!(Test-Path -LiteralPath $localizationModule -PathType Leaf)) { throw 'KVMem language resources are missing; re-extract the complete package.' }
Import-Module $localizationModule -Force
$languageFile = Join-Path $root 'codex\ui-language.json'
if (Test-Path -LiteralPath $languageFile -PathType Leaf) {
    try {
        $savedLanguage = (Get-Content -LiteralPath $languageFile -Raw | ConvertFrom-Json).Language
        if ($savedLanguage -in @('zh','en')) { Set-KVMemUiLanguage -Language $savedLanguage }
    } catch { Set-KVMemUiLanguage -Language 'zh' }
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
function Show-LocalizedMessage([string]$Message,[string]$Caption='KVMem',[string]$Buttons='OK',[string]$Icon='Information') {
    return [Windows.Forms.MessageBox]::Show((Get-KVMemUiText $Message),(Get-KVMemUiText $Caption),$Buttons,$Icon)
}
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Text.RegularExpressions;
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
                    if (data.GetArrayLength() == 0) return "(无已加载模型)";
                    var model = data[0];
                    if (model.TryGetProperty("status", out var status) && status.TryGetProperty("value", out var value) && value.GetString() != "loaded") return "";
                    return model.TryGetProperty("id", out var id) ? id.GetString() : "(模型 ID 未返回)";
                }
            }
        } catch { return ""; }
    }
}
'@
[void][System.Windows.Forms.Application]::SetHighDpiMode([System.Windows.Forms.HighDpiMode]::PerMonitorV2)
[System.Windows.Forms.Application]::EnableVisualStyles()
$startScript = Join-Path $root 'Start-KVMem.ps1'
$stopScript = Join-Path $root 'Stop-KVMem.ps1'
$serverPath = [IO.Path]::GetFullPath((Join-Path $root 'runtime\bin\llama-kvmem-server.exe'))
$compatibilityModule = Join-Path $root 'KVMem-Compatibility.psm1'
if (!(Test-Path -LiteralPath $compatibilityModule -PathType Leaf)) {
    $missingModuleMessage=if((Get-KVMemUiLanguage) -eq 'en'){"KVMem GPU compatibility checker is missing: $compatibilityModule`r`nRe-extract the complete portable package."}else{"缺少 KVMem 显卡兼容性检查模块：$compatibilityModule`r`n请重新解压完整的便携包。"}
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
$logsPath = Join-Path $root 'codex\logs'
$script:models = @()
$script:scanTask = $null
$script:statusTask = $null
$script:layerTask = $null
$script:layerPath = ''
$script:modelLayerCount = 0
$script:operationProcess = $null

$form = [Windows.Forms.Form]::new()
$form.Text = 'KVMem 本地模型控制台'
$form.StartPosition = 'CenterScreen'
$form.ShowInTaskbar = $true
$form.AutoScaleMode = 'Dpi'
$form.Font = [Drawing.Font]::new('Microsoft YaHei UI', 10)
$form.BackColor = [Drawing.Color]::FromArgb(247,248,250)
$form.MinimumSize = [Drawing.Size]::new(760,720)
$area=[Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Size=[Drawing.Size]::new([Math]::Min(1080,$area.Width),[Math]::Min(900,$area.Height))
$tips=[Windows.Forms.ToolTip]::new()
$tips.AutoPopDelay=20000

function New-UiLabel([string]$Text) {
    $c=[Windows.Forms.Label]::new();$c.Text=$Text;$c.AutoSize=$true
    $c.Anchor='Left';$c.Margin=[Windows.Forms.Padding]::new(4,7,12,7)
    $c.ForeColor=[Drawing.Color]::FromArgb(35,39,47)
    return $c
}
function New-UiButton([string]$Text) {
    $c=[Windows.Forms.Button]::new();$c.Text=$Text;$c.AutoSize=$true;$c.AutoSizeMode='GrowAndShrink'
    $c.MinimumSize=[Drawing.Size]::new(96,36);$c.Padding=[Windows.Forms.Padding]::new(9,4,9,4)
    $c.Margin=[Windows.Forms.Padding]::new(4);$c.UseVisualStyleBackColor=$true
    return $c
}
function New-UiText([string]$Text='',[bool]$ReadOnly=$false) {
    $c=[Windows.Forms.TextBox]::new();$c.Text=$Text;$c.ReadOnly=$ReadOnly;$c.Dock='Fill'
    $c.Margin=[Windows.Forms.Padding]::new(4,8,4,8)
    return $c
}
function Add-ModelRow([string]$Label,$InputControl,$Buttons) {
    $row=$modelTable.RowCount;$modelTable.RowCount++
    [void]$modelTable.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))
    $modelTable.Controls.Add((New-UiLabel $Label),0,$row)
    $modelTable.Controls.Add($InputControl,1,$row)
    if($Buttons){$modelTable.Controls.Add($Buttons,2,$row)}else{$modelTable.SetColumnSpan($InputControl,2)}
}
function New-ParameterPage([string]$Title,[string]$Description) {
    $page=[Windows.Forms.TabPage]::new($Title);$page.Padding=[Windows.Forms.Padding]::new(10)
    $page.AutoScroll=$true;$page.UseVisualStyleBackColor=$true
    $table=[Windows.Forms.TableLayoutPanel]::new();$table.Dock='Top';$table.AutoSize=$true
    $table.AutoSizeMode='GrowAndShrink';$table.ColumnCount=2;$table.RowCount=1
    [void]$table.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::AutoSize))
    [void]$table.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
    $descriptionLabel=New-UiLabel $Description;$descriptionLabel.ForeColor=[Drawing.Color]::DimGray
    $descriptionLabel.MaximumSize=[Drawing.Size]::new(620,0)
    $table.Controls.Add($descriptionLabel,0,0);$table.SetColumnSpan($descriptionLabel,2)
    $page.Controls.Add($table);[void]$tabs.TabPages.Add($page)
    return $table
}
function Add-Parameter($Table,[string]$Label,$Control,[string]$Help='') {
    $row=$Table.RowCount;$Table.RowCount++
    [void]$Table.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))
    $Table.Controls.Add((New-UiLabel $Label),0,$row)
    $Control.Dock='Fill';$Control.Margin=[Windows.Forms.Padding]::new(4,5,10,5)
    $Table.Controls.Add($Control,1,$row)
    if($Help){$tips.SetToolTip($Control,$Help)}
}
function Add-Numeric($Table,[string]$Text,[decimal]$Min,[decimal]$Max,[decimal]$Value,[int]$Decimals=0,[decimal]$Step=1) {
    $c=[Windows.Forms.NumericUpDown]::new();$c.Minimum=$Min;$c.Maximum=$Max;$c.DecimalPlaces=$Decimals
    $c.Value=$Value;$c.Increment=$Step;$c.ThousandsSeparator=$true
    Add-Parameter $Table $Text $c
    return $c
}
function Add-Choice($Table,[string]$Text,[string[]]$Items,[string]$Selected) {
    $c=[Windows.Forms.ComboBox]::new();$c.DropDownStyle='DropDownList'
    [void]$c.Items.AddRange($Items);$c.SelectedItem=$Selected
    Add-Parameter $Table $Text $c
    return $c
}
function Apply-UiLanguage {
    $language=Get-KVMemUiLanguage
    $languageChanged=$script:lastAppliedLanguage -ne $language
    $pending=[Collections.Generic.Stack[Windows.Forms.Control]]::new()
    $pending.Push($form)
    while($pending.Count){
        $control=$pending.Pop()
        if($control -ne $languageButton -and !($control -is [Windows.Forms.TextBox])){
            $newText=Get-KVMemUiText $control.Text
            if($newText -cne $control.Text){$control.Text=$newText}
            $tip=$tips.GetToolTip($control)
            if($tip){$newTip=Get-KVMemUiText $tip;if($newTip -cne $tip){$tips.SetToolTip($control,$newTip)}}
        }
        if($languageChanged -and $control -is [Windows.Forms.ComboBox] -and $control -ne $modelBox -and !$control.DisplayMember){
            $selected=$control.SelectedIndex;$items=@();foreach($item in $control.Items){$items+=Get-KVMemUiText ([string]$item)}
            $control.BeginUpdate();$control.Items.Clear();[void]$control.Items.AddRange([object[]]$items)
            if($selected -ge 0 -and $selected -lt $control.Items.Count){$control.SelectedIndex=$selected};$control.EndUpdate()
        }
        foreach($child in $control.Controls){$pending.Push($child)}
        if($control -is [Windows.Forms.TabControl]){foreach($page in $control.TabPages){$pending.Push($page)}}
    }
    $formText=Get-KVMemUiText $form.Text;if($formText -cne $form.Text){$form.Text=$formText}
    if($hint){
        $hintText=if($language -eq 'en'){"SillyTavern API: http://127.0.0.1:18200/v1    Model: kvmem-current`r`nGPU backend: $($script:backendCompatibility.SummaryEnglish)"}else{"酒馆 API：http://127.0.0.1:18200/v1    模型：kvmem-current`r`nGPU 后端：$($script:backendCompatibility.Summary)"}
        if($hint.Text -cne $hintText){$hint.Text=$hintText}
    }
    $languageButton.Text=if($language -eq 'en'){'中文'}else{'English'}
    $script:lastAppliedLanguage=$language
}
$layout=[Windows.Forms.TableLayoutPanel]::new();$layout.Dock='Fill';$layout.Padding=[Windows.Forms.Padding]::new(16)
$layout.ColumnCount=1;$layout.RowCount=8
[void]$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
foreach($i in 0..7){$type=if($i -eq 3){[Windows.Forms.SizeType]::Percent}else{[Windows.Forms.SizeType]::AutoSize};[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new($type,100))}
$form.Controls.Add($layout)
$header=[Windows.Forms.TableLayoutPanel]::new();$header.Dock='Fill';$header.ColumnCount=2;$header.RowCount=1
[void]$header.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
[void]$header.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::AutoSize))
$title=New-UiLabel 'KVMem 模型控制台';$title.Font=[Drawing.Font]::new('Microsoft YaHei UI',17,[Drawing.FontStyle]::Bold)
$header.Controls.Add($title,0,0)
$languageButton=New-UiButton 'English';$header.Controls.Add($languageButton,1,0)
$layout.Controls.Add($header,0,0)
$status=New-UiLabel '状态：正在检查服务…';$status.Dock='Fill';$layout.Controls.Add($status,0,1)
$modelTable=[Windows.Forms.TableLayoutPanel]::new();$modelTable.Dock='Fill';$modelTable.AutoSize=$true
$modelTable.ColumnCount=3;$modelTable.RowCount=0
[void]$modelTable.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::AutoSize))
[void]$modelTable.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
[void]$modelTable.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::AutoSize))
$layout.Controls.Add($modelTable,0,2)
$rootBox=New-UiText $ModelRoot
$folderButton=New-UiButton '选择目录…';Add-ModelRow '模型目录' $rootBox $folderButton
$filterBox=New-UiText;$filterBox.PlaceholderText='按文件名筛选本地 GGUF…'
$scanButton=New-UiButton '刷新列表';Add-ModelRow '筛选模型' $filterBox $scanButton
$modelBox=[Windows.Forms.ComboBox]::new();$modelBox.DropDownStyle='DropDownList';$modelBox.DisplayMember='Label';$modelBox.ValueMember='Path'
$modelBox.Dock='Fill';$modelBox.Margin=[Windows.Forms.Padding]::new(4,8,4,8);$modelBox.DropDownWidth=1100
$fileButton=New-UiButton '浏览 GGUF…';Add-ModelRow 'GGUF 模型' $modelBox $fileButton
$modelPath=New-UiText '' $true;Add-ModelRow '所选文件' $modelPath $null
$mmPath=New-UiText '' $true
$mmButtons=[Windows.Forms.FlowLayoutPanel]::new();$mmButtons.AutoSize=$true;$mmButtons.WrapContents=$false
$mmButton=New-UiButton '选择 mmproj…';$mmClearButton=New-UiButton '清除'
$mmButtons.Controls.Add($mmButton);$mmButtons.Controls.Add($mmClearButton)
Add-ModelRow '视觉投影（可选）' $mmPath $mmButtons
$tabs=[Windows.Forms.TabControl]::new();$tabs.Dock='Fill'
$layout.Controls.Add($tabs,0,3)
$loadTable=New-ParameterPage '加载与显存' 'GPU 自动层数读取所选 GGUF；模型过大时可取消自动，手动降低层数。'
$gpuLayerControl=Add-Numeric $loadTable 'GPU 卸载层数' 0 512 0
$autoGpuCheck=[Windows.Forms.CheckBox]::new();$autoGpuCheck.Text='自动（选择模型后读取最大层数）';$autoGpuCheck.AutoSize=$true;$autoGpuCheck.Checked=$true
Add-Parameter $loadTable '自动 GPU 层数' $autoGpuCheck;$gpuLayerControl.Enabled=$false
$flashControl=Add-Choice $loadTable 'Flash Attention' @('on','off','auto') 'on'
$loadModeControl=Add-Choice $loadTable '模型加载方式' @('auto','mmap','mlock','mmap+mlock','none','dio') 'auto'
$threadsControl=Add-Numeric $loadTable 'CPU 线程（0 = 自动）' 0 256 0
$threadsBatchControl=Add-Numeric $loadTable '批处理线程（0 = 跟随 CPU 线程）' 0 256 0
$batchControl=Add-Numeric $loadTable '逻辑批大小（batch）' 1 2048 256
$ubatchControl=Add-Numeric $loadTable '物理批大小（ubatch）' 1 2048 128
$kvTable=New-ParameterPage '上下文与 KV 缓存' '这些参数在下次启动或切换模型时生效。更大的上下文与缓存可能增加内存占用。'
$contextControl=Add-Numeric $kvTable '上下文长度（tokens）' 1024 262144 32768 0 1024
$kvTypeControl=Add-Choice $kvTable 'KV 缓存精度' @('f16','f32','q8_0','q5_0','q4_0') 'q5_0'
$budgetControl=Add-Numeric $kvTable 'KVMem GPU 缓存预算（tokens）' 0 262144 8192 0 128
$reserveControl=Add-Numeric $kvTable '生成预留（tokens）' 0 65536 2048 0 128
$cpuArenaControl=Add-Numeric $kvTable 'KVMem CPU 缓存（GiB）' 0 256 1
$samplingTable=New-ParameterPage '生成与采样' '这里设置服务默认值；酒馆请求中的采样参数会覆盖对应的服务默认值。'
$maxTokensControl=Add-Numeric $samplingTable '最大生成长度（tokens，-1 = 不限）' -1 65536 2048 0 128
$temperatureControl=Add-Numeric $samplingTable '温度（Temperature）' 0 2 0.7 2 0.05
$topPControl=Add-Numeric $samplingTable 'Top-P' 0 1 0.8 2 0.05
$topKControl=Add-Numeric $samplingTable 'Top-K' 0 1000 20
$minPControl=Add-Numeric $samplingTable 'Min-P' 0 1 0 2 0.01
$repeatControl=Add-Numeric $samplingTable '重复惩罚' 0.1 3 1 2 0.05
$presenceControl=Add-Numeric $samplingTable '存在惩罚（Presence penalty）' -2 2 0 2 0.05
$frequencyControl=Add-Numeric $samplingTable '频率惩罚（Frequency penalty）' -2 2 0 2 0.05
$seedControl=Add-Numeric $samplingTable '随机种子（-1 = 随机）' -1 4294967295 -1
$thinkingControl=Add-Choice $samplingTable '思考模式' @('禁用思考','模型默认') '禁用思考'
$hintText=if((Get-KVMemUiLanguage) -eq 'en'){"SillyTavern API: http://127.0.0.1:18200/v1    Model: kvmem-current`r`nGPU backend: $($script:backendCompatibility.SummaryEnglish)"}else{"酒馆 API：http://127.0.0.1:18200/v1    模型：kvmem-current`r`nGPU 后端：$($script:backendCompatibility.Summary)"}
$hint=New-UiLabel $hintText
$hint.ForeColor=[Drawing.Color]::FromArgb(45,86,140);$layout.Controls.Add($hint,0,4)
$actions=[Windows.Forms.FlowLayoutPanel]::new();$actions.AutoSize=$true;$actions.Dock='Fill';$actions.WrapContents=$true
$action=New-UiButton '启动 / 切换模型';$action.BackColor=[Drawing.Color]::FromArgb(34,116,220);$action.ForeColor=[Drawing.Color]::White
$stopButton=New-UiButton '停止 KVMem';$webButton=New-UiButton '打开 KVMem 页面';$logsButton=New-UiButton '查看运行日志';$copyButton=New-UiButton '复制酒馆地址'
foreach($button in @($action,$stopButton,$webButton,$logsButton,$copyButton)){$actions.Controls.Add($button)}
$layout.Controls.Add($actions,0,5)
$feedback=New-UiText '' $true;$feedback.Multiline=$true;$feedback.ScrollBars='Vertical';$feedback.Height=58
$layout.Controls.Add($feedback,0,6)
$foot=New-UiLabel '提示：长文件路径可选中后复制；参数支持鼠标滚轮，页签内容不足时可向下滚动。'
$foot.ForeColor=[Drawing.Color]::DimGray;$layout.Controls.Add($foot,0,7)
$form.add_Resize({
    $width=[Math]::Max(200,$form.ClientSize.Width-56)
    foreach($label in @($status,$hint,$foot)){$label.MaximumSize=[Drawing.Size]::new($width,0)}
})

function Write-UiFeedback([string]$Message) {
    $Message=Get-KVMemUiText $Message
    $feedback.AppendText("[$(Get-Date -Format HH:mm:ss)] $Message`r`n")
}
function Invoke-UiAction([scriptblock]$Work) {
    try { & $Work }
    catch {
        $message=$_.Exception.Message
        Write-UiFeedback "操作失败：$message"
        New-Item -ItemType Directory -Force -Path $logsPath|Out-Null
        Add-Content -LiteralPath (Join-Path $logsPath 'controller-errors.log') -Value "$(Get-Date -Format o) $($_ | Out-String)"
        [void](Show-LocalizedMessage $message 'KVMem 操作失败' 'OK' 'Error')
    }
}

function Show-ControllerLogs {
    if($script:logWindow -and !$script:logWindow.IsDisposed){$script:logWindow.WindowState='Normal';$script:logWindow.Activate();return}
    New-Item -ItemType Directory -Force -Path $logsPath|Out-Null
    $window=[Windows.Forms.Form]::new();$window.Text='KVMem 运行日志';$window.Size=[Drawing.Size]::new(1000,650)
    $window.MinimumSize=[Drawing.Size]::new(680,400);$window.StartPosition='CenterParent';$window.Font=$form.Font
    $container=[Windows.Forms.TableLayoutPanel]::new();$container.Dock='Fill';$container.ColumnCount=1;$container.RowCount=2
    [void]$container.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))
    [void]$container.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
    $window.Controls.Add($container)
    $toolbar=[Windows.Forms.FlowLayoutPanel]::new();$toolbar.AutoSize=$true;$toolbar.Dock='Fill'
    $refreshLogs=New-UiButton '刷新日志列表';$toolbar.Controls.Add($refreshLogs)
    $toolbar.Controls.Add((New-UiLabel '选择左侧文件查看末尾 500 行；后台仍可继续写入日志。'))
    $container.Controls.Add($toolbar,0,0)
    $split=[Windows.Forms.SplitContainer]::new();$split.Size=[Drawing.Size]::new(960,520);$split.Dock='Fill';$split.Panel1MinSize=180;$split.Panel2MinSize=180
    $container.Controls.Add($split,0,1)
    $list=[Windows.Forms.ListBox]::new();$list.Dock='Fill';$list.HorizontalScrollbar=$true;$list.DisplayMember='Name'
    $viewer=[Windows.Forms.TextBox]::new();$viewer.Multiline=$true;$viewer.ReadOnly=$true;$viewer.WordWrap=$false
    $viewer.ScrollBars='Both';$viewer.Dock='Fill';$viewer.Font=[Drawing.Font]::new('Consolas',10)
    $split.Panel1.Controls.Add($list);$split.Panel2.Controls.Add($viewer)
    $list.Tag=$viewer;$refreshLogs.Tag=$list
    $list.add_SelectedIndexChanged({param($sender,$eventArgs) Invoke-UiAction {
        if($sender.SelectedItem){$sender.Tag.Text=(Get-Content -LiteralPath $sender.SelectedItem.FullName -Tail 500 -ErrorAction Stop) -join "`r`n"}
    }})
    $refreshLogs.add_Click({param($sender,$eventArgs) Invoke-UiAction {
        $target=$sender.Tag;$target.Items.Clear()
        foreach($file in @(Get-ChildItem -LiteralPath $logsPath -Filter '*.log'|Sort-Object LastWriteTime -Descending|Select-Object -First 80)){[void]$target.Items.Add($file)}
        if($target.Items.Count){$target.SelectedIndex=0}else{$target.Tag.Text='暂无日志；启动模型后会产生运行日志。'}
    }})
    $script:logWindow=$window
    $window.Show($form);$split.SplitterDistance=320;$refreshLogs.PerformClick()
    Write-UiFeedback '已打开运行日志窗口。可选择 stdout、stderr 或控制器错误日志。'
}


function Update-Status {
    if($script:statusTask -and $script:statusTask.IsCompleted){
        try{$id=[string]$script:statusTask.GetAwaiter().GetResult()}catch{$id=''}
        $script:statusTask=$null
        if($script:operationProcess -and !$script:operationProcess.HasExited){return}
        if($id){$status.Text="状态：运行中    模型：$id";$status.ForeColor=[Drawing.Color]::FromArgb(25,125,76)}
        else{$status.Text='状态：未就绪（服务未启动或正在加载模型）';$status.ForeColor=[Drawing.Color]::FromArgb(100,100,100)}
    }
    if(!$script:statusTask){$script:statusTask=[KVMemStatusProbe]::ProbeAsync()}
}
function Quote-PsLiteral([string]$Value) { "'" + $Value.Replace("'","''") + "'" }
function Start-ControllerOperation([string]$Body,[string]$Label) {
    if($script:operationProcess -and !$script:operationProcess.HasExited){[void](Show-LocalizedMessage '已有启动或停止操作正在执行。' 'KVMem' 'OK' 'Information');return}
    New-Item -ItemType Directory -Force -Path $logsPath|Out-Null
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $taskFile=Join-Path $logsPath "controller-operation-$stamp.ps1"
    $outFile=Join-Path $logsPath "controller-operation-$stamp.stdout.log"
    $errFile=Join-Path $logsPath "controller-operation-$stamp.stderr.log"
    [IO.File]::WriteAllText($taskFile,"`$ErrorActionPreference='Stop'`r`n$Body`r`n",[Text.UTF8Encoding]::new($true))
    $pwsh=Join-Path $root '.tools\pwsh\pwsh.exe'
    if(!(Test-Path -LiteralPath $pwsh)){$pwsh=(Get-Command pwsh.exe -ErrorAction Stop).Source}
    $script:operationProcess=Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',("`"$taskFile`"")) -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput $outFile -RedirectStandardError $errFile -PassThru
    $script:operationLabel=$Label
    $script:operationErrorFile=$errFile
    $action.Enabled=$false
    Write-UiFeedback "$Label；详情记录在 $outFile"
    $status.Text="状态：$Label …";$status.ForeColor=[Drawing.Color]::FromArgb(180,110,20)
}
function Update-Operation {
    if(!$script:operationProcess -or !$script:operationProcess.HasExited){return}
    $exit=$script:operationProcess.ExitCode;$script:operationProcess.Dispose();$script:operationProcess=$null
    $action.Enabled=$true
    if($exit -eq 0){$status.Text="状态：操作命令已完成，等待服务就绪";Write-UiFeedback '命令已完成。模型加载可能需要一段时间，服务就绪后状态会显示运行中。'}
    else{$status.Text="状态：操作失败（退出码 $exit）";$detail=if(Test-Path -LiteralPath $script:operationErrorFile){Get-Content -LiteralPath $script:operationErrorFile -Raw}else{'没有错误输出'};Write-UiFeedback "操作失败：$detail"}
}
function Render-Models {
    $previous=$modelPath.Text
    $term=$filterBox.Text.Trim();$modelBox.BeginUpdate();$modelBox.Items.Clear()
    foreach($m in $script:models){if(!$term -or $m.Label.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0){[void]$modelBox.Items.Add($m)}}
    $modelBox.EndUpdate()
    for($i=0;$i -lt $modelBox.Items.Count;$i++){if($modelBox.Items[$i].Path -eq $previous){$modelBox.SelectedIndex=$i;break}}
    if($modelBox.Items.Count -gt 0 -and $modelBox.SelectedIndex -lt 0){$modelBox.SelectedIndex=0}
    if($modelBox.Items.Count -eq 0){Write-UiFeedback '没有匹配的模型。可修改筛选文字，或使用“浏览 GGUF”。'}
}
function Start-ModelScan {
    if($script:scanTask -and !$script:scanTask.IsCompleted){Write-UiFeedback '正在扫描模型，请稍候。';return}
    $scanRoot=$rootBox.Text.Trim();if(!(Test-Path -LiteralPath $scanRoot -PathType Container)){[void](Show-LocalizedMessage "找不到目录：`n$scanRoot" 'KVMem' 'OK' 'Warning');return}
    $scanButton.Enabled=$false;$status.Text='状态：正在扫描 GGUF 模型…'
    $script:scanTask=[KVMemModelScanner]::ScanAsync($scanRoot)
}

function Complete-ModelScan {
    if(!$script:scanTask -or !$script:scanTask.IsCompleted){return}
    $scanTask=$script:scanTask;$script:scanTask=$null;$scanButton.Enabled=$true
    if($scanTask.IsFaulted){$status.Text='状态：扫描失败';[void](Show-LocalizedMessage $scanTask.Exception.GetBaseException().Message '模型扫描失败' 'OK' 'Error');return}
    $script:models=@($scanTask.Result|ForEach-Object{$f=[IO.FileInfo]::new($_);[pscustomobject]@{Label="$($f.BaseName) · $([math]::Round($f.Length/1GB,2)) GiB";Path=$f.FullName}})
    Render-Models;Write-UiFeedback "扫描完成：找到 $($script:models.Count) 个 GGUF 模型。"
}

function Start-LayerScan([string]$Path) {
    $script:layerTask=$null;$script:layerPath=$Path;$script:modelLayerCount=0
    if(!$Path){$autoGpuCheck.Text='自动（选择模型后读取最大层数）';return}
    $autoGpuCheck.Text='自动（正在读取模型最大层数…）'
    $script:layerTask=[KVMemModelScanner]::ReadLayerCountAsync($Path)
}
function Complete-LayerScan {
    if(!$script:layerTask -or !$script:layerTask.IsCompleted){return}
    $task=$script:layerTask;$script:layerTask=$null
    if($task.IsFaulted){$autoGpuCheck.Text='自动（无法读取层数；可手动设置）';return}
    $script:modelLayerCount=[int]$task.Result
    $autoGpuCheck.Text="自动（模型最大 $($script:modelLayerCount) 层）"
    if($autoGpuCheck.Checked){$gpuLayerControl.Value=[math]::Min([decimal]$script:modelLayerCount,$gpuLayerControl.Maximum)}
}

$filterBox.add_TextChanged({Invoke-UiAction {Render-Models}})
$modelBox.add_SelectedIndexChanged({if($modelBox.SelectedItem){$modelPath.Text=$modelBox.SelectedItem.Path;Start-LayerScan $modelBox.SelectedItem.Path}})
$autoGpuCheck.add_CheckedChanged({$gpuLayerControl.Enabled=!$autoGpuCheck.Checked;if($autoGpuCheck.Checked -and $script:modelLayerCount -gt 0){$gpuLayerControl.Value=[math]::Min([decimal]$script:modelLayerCount,$gpuLayerControl.Maximum)}})
$scanButton.add_Click({Invoke-UiAction {Start-ModelScan}})
$folderButton.add_Click({Invoke-UiAction {$d=[Windows.Forms.FolderBrowserDialog]::new();try{$d.Description='选择要扫描 GGUF 模型的目录';$d.SelectedPath=$rootBox.Text;if($d.ShowDialog($form) -eq 'OK'){$rootBox.Text=$d.SelectedPath;Start-ModelScan}}finally{$d.Dispose()}}})
$fileButton.add_Click({Invoke-UiAction {$d=[Windows.Forms.OpenFileDialog]::new();try{$d.Title='选择任意 GGUF 模型';$d.Filter='GGUF 模型 (*.gguf)|*.gguf|所有文件 (*.*)|*.*';$d.CheckFileExists=$true;if($d.ShowDialog($form) -eq 'OK'){$modelPath.Text=$d.FileName;Start-LayerScan $d.FileName}}finally{$d.Dispose()}}})
$mmButton.add_Click({Invoke-UiAction {$d=[Windows.Forms.OpenFileDialog]::new();try{$d.Title='选择视觉投影文件（可选）';$d.Filter='mmproj 文件 (*.gguf)|*.gguf|所有文件 (*.*)|*.*';$d.CheckFileExists=$true;if($d.ShowDialog($form) -eq 'OK'){$mmPath.Text=$d.FileName}}finally{$d.Dispose()}}})

$action.add_Click({Invoke-UiAction {
    $model=$modelPath.Text.Trim()
    if(!(Test-Path -LiteralPath $model -PathType Leaf) -or [IO.Path]::GetExtension($model) -ne '.gguf'){[void](Show-LocalizedMessage '请先选择一个存在的 GGUF 文件。' 'KVMem' 'OK' 'Warning');return}
    if($autoGpuCheck.Checked -and ($script:layerPath -ne $model -or $script:modelLayerCount -lt 1)){[void](Show-LocalizedMessage '正在读取该 GGUF 的层数，或元数据无法识别。请稍候，或取消自动并手动设置 GPU 层数。' 'KVMem' 'OK' 'Warning');return}
    $mm=$mmPath.Text.Trim();if($mm -and !(Test-Path -LiteralPath $mm -PathType Leaf)){[void](Show-LocalizedMessage "找不到 mmproj：`n$mm" 'KVMem' 'OK' 'Warning');return}
    $listener=Get-NetTCPConnection -State Listen -LocalPort 18200 -ErrorAction SilentlyContinue|Select-Object -First 1
    $body="`$ErrorActionPreference='Stop'`r`n"
    if($listener){$owner=Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)" -ErrorAction SilentlyContinue
        if(!$owner -or ![string]::Equals($owner.ExecutablePath,$serverPath,[StringComparison]::OrdinalIgnoreCase)){[void](Show-LocalizedMessage "18200 端口由其他程序使用（PID $($listener.OwningProcess)），未做更改。" '端口冲突' 'OK' 'Warning');return}
        if((Show-LocalizedMessage '当前模型将停止并切换到所选模型。继续？' '切换模型' 'YesNo' 'Question') -ne 'Yes'){return}
        $body+="& $(Quote-PsLiteral $stopScript)`r`n`$until=(Get-Date).AddSeconds(30)`r`nwhile((Get-Date) -lt `$until -and (Get-NetTCPConnection -State Listen -LocalPort 18200 -ErrorAction SilentlyContinue)){Start-Sleep -Milliseconds 250}`r`nif(Get-NetTCPConnection -State Listen -LocalPort 18200 -ErrorAction SilentlyContinue){throw '旧服务未释放 18200 端口'}`r`n"
    }
    $gpuLayers=if($autoGpuCheck.Checked){$script:modelLayerCount}else{[int]$gpuLayerControl.Value}
    $inv=[Globalization.CultureInfo]::InvariantCulture
    $disableThinking=if($thinkingControl.SelectedIndex -eq 0){'$true'}else{'$false'}
    $body+="& $(Quote-PsLiteral $startScript) -Model $(Quote-PsLiteral $model) -ModelAlias 'kvmem-current' -Context $([int]$contextControl.Value) -GpuLayers $gpuLayers -KvmemBudget $([int]$budgetControl.Value) -GenerationReserve $([int]$reserveControl.Value) -CpuMemoryGiB $([int]$cpuArenaControl.Value) -BatchSize $([int]$batchControl.Value) -UBatchSize $([int]$ubatchControl.Value) -Threads $([int]$threadsControl.Value) -ThreadsBatch $([int]$threadsBatchControl.Value) -KvDtype '$($kvTypeControl.SelectedItem)' -FlashAttention '$($flashControl.SelectedItem)' -LoadMode '$($loadModeControl.SelectedItem)' -MaxTokens $([int]$maxTokensControl.Value) -Temperature $($temperatureControl.Value.ToString($inv)) -TopP $($topPControl.Value.ToString($inv)) -TopK $([int]$topKControl.Value) -MinP $($minPControl.Value.ToString($inv)) -RepeatPenalty $($repeatControl.Value.ToString($inv)) -PresencePenalty $($presenceControl.Value.ToString($inv)) -FrequencyPenalty $($frequencyControl.Value.ToString($inv)) -Seed $([long]$seedControl.Value) -DisableThinking:$disableThinking"
    if($mm){$body+=" -Mmproj $(Quote-PsLiteral $mm)"}
    Start-ControllerOperation $body "正在加载 $([IO.Path]::GetFileName($model))"
}})
$stopButton.add_Click({Invoke-UiAction {$l=Get-NetTCPConnection -State Listen -LocalPort 18200 -ErrorAction SilentlyContinue|Select-Object -First 1;if(!$l){$status.Text='状态：KVMem 已停止';Write-UiFeedback 'KVMem 当前没有运行，无需停止。';return};$o=Get-CimInstance Win32_Process -Filter "ProcessId = $($l.OwningProcess)" -ErrorAction SilentlyContinue;if(!$o -or ![string]::Equals($o.ExecutablePath,$serverPath,[StringComparison]::OrdinalIgnoreCase)){[void](Show-LocalizedMessage "18200 端口属于其他程序（PID $($l.OwningProcess)），已取消。" 'KVMem' 'OK' 'Warning');return};Start-ControllerOperation "& $(Quote-PsLiteral $stopScript)" '正在停止 KVMem'}})
$webButton.add_Click({Invoke-UiAction {
    if(![Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners().Where({$_.Port -eq 18200}).Count){Write-UiFeedback '请先启动模型；模型加载完成后才能打开 KVMem 页面。';return}
    $info=[Diagnostics.ProcessStartInfo]::new('http://127.0.0.1:18200/');$info.UseShellExecute=$true;[void][Diagnostics.Process]::Start($info)
}})
$logsButton.add_Click({Invoke-UiAction {Show-ControllerLogs}})
$copyButton.add_Click({Invoke-UiAction {[Windows.Forms.Clipboard]::SetText('http://127.0.0.1:18200/v1');Write-UiFeedback '已复制酒馆 API 地址。模型 ID：kvmem-current'}})
$mmClearButton.add_Click({$mmPath.Clear();Write-UiFeedback '已清除视觉投影文件。'})
$modelPath.add_TextChanged({$tips.SetToolTip($modelPath,$modelPath.Text)})
$mmPath.add_TextChanged({$tips.SetToolTip($mmPath,$mmPath.Text)})
$languageButton.add_Click({Invoke-UiAction {
    $next=if((Get-KVMemUiLanguage) -eq 'en'){'zh'}else{'en'}
    Set-KVMemUiLanguage -Language $next
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $languageFile)|Out-Null
    [IO.File]::WriteAllText($languageFile,(ConvertTo-Json @{Language=$next} -Compress),[Text.UTF8Encoding]::new($false))
    Apply-UiLanguage
}})
$timer=[Windows.Forms.Timer]::new();$timer.Interval=500;$timer.add_Tick({Invoke-UiAction {Update-Status;Complete-ModelScan;Complete-LayerScan;Update-Operation;Apply-UiLanguage}})
$form.add_Shown({$form.WindowState=[Windows.Forms.FormWindowState]::Normal;$form.Activate();$form.BringToFront();$status.Text='状态：正在检查 KVMem…';Start-ModelScan;$timer.Start()})
$form.add_FormClosing({$timer.Stop()})
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
[void][Windows.Forms.Application]::Run($form)
