#Requires -Version 7.0
[CmdletBinding()]
param([string]$PreflightFile,[string]$ProfileFile)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$server = Join-Path $root 'workers\ninfer\infer-kvmem-server.exe'
$startScript = Join-Path $root 'Start-KVMem-v018.ps1'
$stopScript = Join-Path $root 'Stop-KVMem-v018.ps1'
$modelRoot = Join-Path $root 'models'
$logs = Join-Path $root 'codex\logs'
$converterRoot = Join-Path $root 'converter'
$converterLogs = Join-Path $converterRoot 'logs'
$converterJobPath = Join-Path $converterLogs 'active-job.json'
$defaultResourceRoot = Join-Path $converterRoot 'models\Qwen3.8-27B'
$configPath = Join-Path $root 'codex\ui-config.json'
$launcherPidPath = Join-Path $root 'codex\launcher.pid'
$port = 18210

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
public static class GGUFPreflight {
    static string ReadString(BinaryReader r) {
        ulong n=r.ReadUInt64();
        if(n>1048576) throw new InvalidDataException("Metadata string is too long");
        byte[] b=r.ReadBytes((int)n);
        if(b.Length!=(int)n) throw new EndOfStreamException("Truncated metadata string");
        return Encoding.UTF8.GetString(b);
    }
    static void Skip(BinaryReader r,uint t) {
        switch(t) {
            case 0: case 7: r.ReadByte(); return;
            case 1: r.ReadSByte(); return;
            case 2: r.ReadUInt16(); return;
            case 3: r.ReadInt16(); return;
            case 4: r.ReadUInt32(); return;
            case 5: r.ReadInt32(); return;
            case 6: r.ReadSingle(); return;
            case 8: ReadString(r); return;
            case 9: {
                uint elementType=r.ReadUInt32(); ulong count=r.ReadUInt64();
                if(count>10000000) throw new InvalidDataException("Metadata array is too large");
                for(ulong i=0;i<count;i++) Skip(r,elementType);
                return;
            }
            case 10: r.ReadUInt64(); return;
            case 11: r.ReadInt64(); return;
            case 12: r.ReadDouble(); return;
            default: throw new InvalidDataException("Unknown metadata type: "+t);
        }
    }
    public static string Check(string path) {
        using(var f=File.OpenRead(path)) using(var r=new BinaryReader(f)) {
            if(r.ReadUInt32()!=0x46554747) throw new InvalidDataException("GGUF magic is missing");
            uint version=r.ReadUInt32();
            if(version<2 || version>3) throw new InvalidDataException("Unsupported GGUF version: "+version);
            ulong tensorCount=r.ReadUInt64(), metadataCount=r.ReadUInt64();
            if(metadataCount>1000000 || tensorCount==0 || tensorCount>10000000) throw new InvalidDataException("Invalid GGUF header counts");
            string architecture=null, modelName=null;
            int layers=-1;
            uint alignment=32;
            for(ulong i=0;i<metadataCount;i++) {
                string key=ReadString(r); uint type=r.ReadUInt32();
                if((key=="general.architecture" || key=="general.name") && type==8) {
                    string value=ReadString(r);
                    if(key=="general.architecture") architecture=value; else modelName=value;
                } else if(key=="general.alignment" && type==4) alignment=r.ReadUInt32();
                else if(architecture!=null && key==architecture+".block_count" && type==4) layers=checked((int)r.ReadUInt32());
                else Skip(r,type);
            }
            if(String.IsNullOrWhiteSpace(architecture)) throw new InvalidDataException("general.architecture is missing");
            if(alignment==0 || alignment>1048576 || (alignment&(alignment-1))!=0) throw new InvalidDataException("Invalid GGUF alignment");
            bool hasTensor=false; ulong previousOffset=0;
            for(ulong i=0;i<tensorCount;i++) {
                if(String.IsNullOrWhiteSpace(ReadString(r))) throw new InvalidDataException("Tensor name is empty");
                uint dimensions=r.ReadUInt32();
                if(dimensions<1 || dimensions>4) throw new InvalidDataException("Invalid tensor dimension count");
                for(uint d=0;d<dimensions;d++) if(r.ReadUInt64()==0) throw new InvalidDataException("Tensor has a zero dimension");
                uint tensorType=r.ReadUInt32();
                if(tensorType>1024) throw new InvalidDataException("Unknown GGML tensor type: "+tensorType);
                ulong offset=r.ReadUInt64();
                if(hasTensor && offset<previousOffset) throw new InvalidDataException("Tensor data offsets are not ordered");
                previousOffset=offset; hasTensor=true;
            }
            long dataStart=checked((long)(((ulong)f.Position+alignment-1)/alignment*alignment));
            if(!hasTensor || dataStart>=f.Length || checked((ulong)dataStart+previousOffset)>=(ulong)f.Length)
                throw new InvalidDataException("Tensor directory is empty or its data offsets exceed file length");
            string recipe="No known exact official recipe match";
            string certainty="Architecture/name match is heuristic; tensor shapes and recipe execution are not tested.";
            if(architecture=="qwen35" && !String.IsNullOrWhiteSpace(modelName) && modelName.IndexOf("Qwen38",StringComparison.OrdinalIgnoreCase)>=0) {
                recipe="Candidate recipe: qwen3_8_27b_gguf (official ninfer-all recipe for Qwen3.8-27B GGUF)";
            }
            return "GGUF structure: PASS\r\nVersion: "+version+"\r\nArchitecture: "+architecture+"\r\nName: "+(modelName??"(not set)")+"\r\nLayers: "+(layers<0?"(not set)":layers.ToString())+"\r\nTensors: "+tensorCount+"\r\nSize: "+(f.Length/1073741824.0).ToString("F2")+" GiB\r\n"+recipe+"\r\n"+certainty+"\r\n\r\nConverter: not installed in this v0.18 package. This is a structural and recipe-candidate check, not a completed conversion.";
        }
    }
}
'@

if ($PreflightFile) {
    [GGUFPreflight]::Check((Resolve-Path -LiteralPath $PreflightFile).Path)
    exit 0
}

Add-Type -TypeDefinition @'
using System;
using System.Net.Http;
using System.Net.NetworkInformation;
using System.Threading.Tasks;
public sealed class KVMemV018ServiceProbe : IDisposable {
    readonly HttpClient client;
    Task<string> pending;
    public KVMemV018ServiceProbe() {
        client = new HttpClient(new HttpClientHandler { UseProxy = false });
        client.Timeout = TimeSpan.FromSeconds(2);
    }
    public void Start(int port) {
        if (pending == null) pending = Task.Run(() => CheckAsync(port));
    }
    public bool IsCompleted { get { return pending != null && pending.IsCompleted; } }
    public string TakeResult() {
        if (!IsCompleted) return null;
        var completed = pending;
        pending = null;
        return completed.GetAwaiter().GetResult();
    }
    async Task<string> CheckAsync(int port) {
        try {
            using (var response = await client.GetAsync("http://127.0.0.1:" + port + "/v1/models",
                    HttpCompletionOption.ResponseHeadersRead).ConfigureAwait(false)) {
                if (response.IsSuccessStatusCode) return "running";
            }
        } catch (HttpRequestException) {
        } catch (OperationCanceledException) {
        } catch (ObjectDisposedException) {
            return "stopped";
        }
        try {
            foreach (var endpoint in IPGlobalProperties.GetIPGlobalProperties().GetActiveTcpListeners())
                if (endpoint.Port == port) return "loading";
        } catch (NetworkInformationException) {
            return "unknown";
        }
        return "stopped";
    }
    public void Dispose() { client.Dispose(); }
}
'@

function New-Label([string]$Text,[int]$X,[int]$Y,[int]$Width=150,[int]$Height=24) {
    $control=[Windows.Forms.Label]::new(); $control.Text=$Text
    $control.Location=[Drawing.Point]::new($X,$Y); $control.Size=[Drawing.Size]::new($Width,$Height)
    $control.TextAlign='MiddleLeft'; return $control
}
function New-TextBox([int]$X,[int]$Y,[int]$Width=170) {
    $control=[Windows.Forms.TextBox]::new(); $control.Location=[Drawing.Point]::new($X,$Y)
    $control.Size=[Drawing.Size]::new($Width,26); return $control
}
function New-Button([string]$Text,[int]$X,[int]$Y,[int]$Width=120) {
    $control=[Windows.Forms.Button]::new(); $control.Text=$Text
    $control.Location=[Drawing.Point]::new($X,$Y); $control.Size=[Drawing.Size]::new($Width,34); return $control
}
function ConvertTo-ProcessArgument([string]$Value) {
    '"' + [regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1') + '"'
}

$form=[Windows.Forms.Form]::new()
$form.Text='KVMem v0.18 控制台'; $form.StartPosition='CenterScreen'
$form.Size=[Drawing.Size]::new(860,970); $form.MinimumSize=[Drawing.Size]::new(860,970)
$form.Font=[Drawing.Font]::new('Microsoft YaHei UI',9)
$form.BackColor=[Drawing.Color]::FromArgb(244,246,249)

$title=New-Label 'KVMem v0.18.0 · NInfer RTX 40 / SM89' 24 14 650 32
$title.Font=[Drawing.Font]::new('Microsoft YaHei UI',15,[Drawing.FontStyle]::Bold); $form.Controls.Add($title)
$status=New-Label '服务状态：检测中' 24 52 760 26
$status.ForeColor=[Drawing.Color]::FromArgb(5,125,95); $form.Controls.Add($status)

$settings=[Windows.Forms.GroupBox]::new(); $settings.Text='模型与运行参数'
$settings.Location=[Drawing.Point]::new(20,86); $settings.Size=[Drawing.Size]::new(785,320); $form.Controls.Add($settings)
$models=[Windows.Forms.ComboBox]::new(); $models.Location=[Drawing.Point]::new(175,28)
$models.Size=[Drawing.Size]::new(485,28); $models.DropDownStyle='DropDownList'
$settings.Controls.Add((New-Label 'NInfer 模型 (.ninfer)' 18 30 150)); $settings.Controls.Add($models)
$browse=New-Button '浏览…' 670 26 90; $settings.Controls.Add($browse)
$context=New-TextBox 175 70; $budget=New-TextBox 175 110; $reserve=New-TextBox 175 150; $prefill=New-TextBox 175 190
$gpu=New-TextBox 565 70 170; $maxTokens=New-TextBox 565 110 170
$settings.Controls.Add((New-Label '上下文上限 (tokens)' 18 71 150)); $settings.Controls.Add($context)
$settings.Controls.Add((New-Label 'KVMem GPU Budget' 18 111 150)); $settings.Controls.Add($budget)
$settings.Controls.Add((New-Label '生成 Reserve' 18 151 150)); $settings.Controls.Add($reserve)
$settings.Controls.Add((New-Label 'Prefill chunk' 18 191 150)); $settings.Controls.Add($prefill)
$settings.Controls.Add((New-Label 'CUDA GPU 编号' 430 71 125)); $settings.Controls.Add($gpu)
$settings.Controls.Add((New-Label '最大输出 tokens' 430 111 125)); $settings.Controls.Add($maxTokens)
$vision=[Windows.Forms.CheckBox]::new(); $vision.Text='启用 Vision'; $vision.Location=[Drawing.Point]::new(435,151); $vision.AutoSize=$true
$settings.Controls.Add($vision)
$settings.Controls.Add((New-Label 'MTP draft tokens' 430 190 125))
$mtp=[Windows.Forms.NumericUpDown]::new(); $mtp.Location=[Drawing.Point]::new(565,190); $mtp.Size=[Drawing.Size]::new(170,27); $mtp.Minimum=0; $mtp.Maximum=15
$settings.Controls.Add($mtp)
$settings.Controls.Add((New-Label 'KV 类型' 430 230 125))
$kvType=[Windows.Forms.ComboBox]::new(); $kvType.Location=[Drawing.Point]::new(565,230); $kvType.Size=[Drawing.Size]::new(170,27); $kvType.DropDownStyle='DropDownList'
[void]$kvType.Items.AddRange(@('int8','bf16','fp8','nvfp4','k8v4','rk8v4','rk4v4','rk4v4-e8','rk2v4-e8'))
$settings.Controls.Add($kvType)
$modelFolder=New-TextBox 175 272 485; $modelFolder.Text=$modelRoot; $modelFolder.ReadOnly=$true
$settings.Controls.Add((New-Label '模型目录' 18 273 150)); $settings.Controls.Add($modelFolder)
$refresh=New-Button '刷新' 670 270 90; $settings.Controls.Add($refresh)

$start=New-Button '启动服务' 24 418 150; $stop=New-Button '停止服务' 188 418 150; $openWeb=New-Button '打开 Web UI' 352 418 150
$form.Controls.AddRange(@($start,$stop,$openWeb))

$conversion=[Windows.Forms.GroupBox]::new(); $conversion.Text='GGUF 结构与转换候选检查'
$conversion.Location=[Drawing.Point]::new(20,464); $conversion.Size=[Drawing.Size]::new(785,174); $form.Controls.Add($conversion)
$ggufPath=New-TextBox 18 27 630; $ggufPath.ReadOnly=$true; $conversion.Controls.Add($ggufPath)
$chooseGguf=New-Button '选择 GGUF…' 660 24 105; $conversion.Controls.Add($chooseGguf)
$checkFileButton=New-Button '检查文件' 18 65 135; $conversion.Controls.Add($checkFileButton)
$conversionResult=New-Label '选择 GGUF 后检查结构。候选配方不是转换成功保证；本机未安装转换器。' 165 65 595 86
$conversionResult.TextAlign='TopLeft'; $conversionResult.AutoEllipsis=$true; $conversion.Controls.Add($conversionResult)
$conversionGuide=New-Button '转换文档' 18 122 120; $conversion.Controls.Add($conversionGuide)
$converterBox=[Windows.Forms.GroupBox]::new(); $converterBox.Text='GGUF → NInfer 转换器'
$converterBox.Location=[Drawing.Point]::new(20,650); $converterBox.Size=[Drawing.Size]::new(805,235); $form.Controls.Add($converterBox)
$resourcesPath=New-TextBox 165 27 515; $resourcesPath.Text=$defaultResourceRoot
$converterBox.Controls.Add((New-Label '模型配置与 tokenizer' 18 29 145)); $converterBox.Controls.Add($resourcesPath)
$browseResources=New-Button '选择目录…' 690 25 95; $converterBox.Controls.Add($browseResources)
$visionPath=New-TextBox 165 63 515
$converterBox.Controls.Add((New-Label '视觉 mmproj (可选)' 18 65 145)); $converterBox.Controls.Add($visionPath)
$browseVision=New-Button '选择文件…' 690 61 95; $converterBox.Controls.Add($browseVision)
$includeVision=[Windows.Forms.CheckBox]::new(); $includeVision.Text='将视觉权重写入转换产物'
$includeVision.Location=[Drawing.Point]::new(165,95); $includeVision.AutoSize=$true; $converterBox.Controls.Add($includeVision)
$outputPath=New-TextBox 165 122 620
$converterBox.Controls.Add((New-Label '新建输出文件' 18 124 145)); $converterBox.Controls.Add($outputPath)
$installConverter=New-Button '安装转换器' 18 158 112
$downloadResources=New-Button '获取 Qwen 资源' 137 158 126
$preflightConverter=New-Button '转换预检' 270 158 100
$runConverter=New-Button '开始转换' 377 158 100
$openConverterLogs=New-Button '打开日志' 484 158 90
$cancelConverter=New-Button '取消任务' 581 158 90
$converterBox.Controls.AddRange(@($installConverter,$downloadResources,$preflightConverter,$runConverter,$openConverterLogs,$cancelConverter))
$converterStatus=New-Label '尚未检测转换器环境。安装、预检和转换均在独立进程中运行。' 18 199 765 23
$converterStatus.ForeColor=[Drawing.Color]::DimGray; $converterBox.Controls.Add($converterStatus)
$footer=New-Label '仅绑定 127.0.0.1 · API: http://127.0.0.1:18210/v1 · 配置保存在本版本 codex\ui-config.json' 24 895 785 26
$footer.ForeColor=[Drawing.Color]::DimGray; $form.Controls.Add($footer)

New-Item -ItemType Directory -Force -Path $modelRoot,$logs,(Split-Path $configPath) | Out-Null
$defaults=@{Context=32768;Budget=16384;Reserve=16384;Prefill=256;Gpu='0';MaxTokens=2048;Vision=$false;VisionResidency='cpu';VisionTokens=1024;MtpDrafts=0;KvType='int8';HostMiB=4096;ThinkingBudget=128;SinkTokens=12288;RecentTokens=1024;Model='';ConverterResources=$defaultResourceRoot;ConverterVision='';ConverterIncludeVision=$false;ConverterOutput=''}
if (Test-Path -LiteralPath $configPath) {
    try { $saved=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json; foreach($key in @($defaults.Keys)){if($null -ne $saved.$key){$defaults[$key]=$saved.$key}} } catch { }
}
if ($ProfileFile) {
    $profile=Get-Content -LiteralPath $ProfileFile -Raw | ConvertFrom-Json
    foreach($key in @($defaults.Keys)){if($null -ne $profile.$key){$defaults[$key]=$profile.$key}}
    $form.Text='KVMem v0.18 控制台 · 64K 长篇配置'
}
$context.Text=[string]$defaults.Context; $budget.Text=[string]$defaults.Budget; $reserve.Text=[string]$defaults.Reserve
$prefill.Text=[string]$defaults.Prefill; $gpu.Text=[string]$defaults.Gpu; $maxTokens.Text=[string]$defaults.MaxTokens
$vision.Checked=[bool]$defaults.Vision; $mtp.Value=[Math]::Max(0,[Math]::Min(15,[int]$defaults.MtpDrafts))
$kvType.SelectedItem=[string]$defaults.KvType; if(!$kvType.SelectedItem){$kvType.SelectedItem='int8'}
$resourcesPath.Text=[string]$defaults.ConverterResources; $visionPath.Text=[string]$defaults.ConverterVision
$includeVision.Checked=[bool]$defaults.ConverterIncludeVision; $outputPath.Text=[string]$defaults.ConverterOutput

function Refresh-Models {
    $selected=[string]$models.SelectedItem; $models.Items.Clear()
    Get-ChildItem -LiteralPath $modelRoot -Recurse -File -Filter '*.ninfer' -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$models.Items.Add($_.FullName) }
    if ($selected -and $models.Items.Contains($selected)) { $models.SelectedItem=$selected }
    elseif ($models.Items.Count) { $models.SelectedIndex=0 }
}
function Save-Config {
    @{Context=[int]$context.Text;Budget=[int]$budget.Text;Reserve=[int]$reserve.Text;Prefill=[int]$prefill.Text;
      Gpu=$gpu.Text;MaxTokens=[int]$maxTokens.Text;Vision=$vision.Checked;MtpDrafts=[int]$mtp.Value;KvType=[string]$kvType.SelectedItem;
      VisionResidency=[string]$defaults.VisionResidency;VisionTokens=[int]$defaults.VisionTokens;
      HostMiB=[int]$defaults.HostMiB;ThinkingBudget=[int]$defaults.ThinkingBudget;SinkTokens=[int]$defaults.SinkTokens;RecentTokens=[int]$defaults.RecentTokens;Model=[string]$models.SelectedItem;
      ConverterResources=$resourcesPath.Text;ConverterVision=$visionPath.Text;ConverterIncludeVision=$includeVision.Checked;ConverterOutput=$outputPath.Text} |
        ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8
}
function Get-ConverterJobProcess {
    if (!(Test-Path -LiteralPath $converterJobPath -PathType Leaf)) { return $null }
    try { $job=Get-Content -LiteralPath $converterJobPath -Raw | ConvertFrom-Json } catch { return $null }
    if (!$job.Pid -or !$job.Script) { return $null }
    $process=Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$job.Pid)" -ErrorAction SilentlyContinue
    if (!$process -or $process.Name -notmatch '^(pwsh|powershell)\.exe$' -or !$process.CommandLine.Contains([string]$converterRoot) -or !$process.CommandLine.Contains([string]$converterJobPath)) { return $null }
    return $process
}
function Start-ConverterJob([string]$Kind,[string]$Script,[string[]]$ScriptArguments) {
    $existing=Get-ConverterJobProcess
    if ($existing) { throw "已有转换任务在运行 (PID $($existing.ProcessId))。" }
    if (!(Test-Path -LiteralPath $Script -PathType Leaf)) { throw "转换脚本不存在：$Script" }
    New-Item -ItemType Directory -Force -Path $converterLogs | Out-Null
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'; $stdout=Join-Path $converterLogs "$stamp-$Kind.stdout.log"; $stderr=Join-Path $converterLogs "$stamp-$Kind.stderr.log"
    $resultPath=Join-Path $converterLogs "$stamp-$Kind.result.json"
    $readyMarker=Join-Path $converterLogs "$stamp-$Kind.ready"
    $runner=Join-Path $converterRoot 'Run-ConverterJob.ps1'
    if (!(Test-Path -LiteralPath $runner -PathType Leaf)) { throw "任务包装器不存在：$runner" }
    @{Kind=$Kind;Script=$Script;ScriptArguments=$ScriptArguments;Started=$null;Finished=$null;State='starting';Pid=0;
      Stdout=$stdout;Stderr=$stderr;Result=$resultPath;ReadyMarker=$readyMarker;ExitCode=$null} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $converterJobPath -Encoding utf8
    $pwsh=(Get-Command pwsh.exe -ErrorAction Stop).Source
    $arguments=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$runner,'-JobFile',$converterJobPath)
    $argumentLine=($arguments | ForEach-Object { ConvertTo-ProcessArgument ([string]$_) }) -join ' '
    $process=Start-Process -FilePath $pwsh -ArgumentList $argumentLine -WorkingDirectory $root -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
    $ready=$false
    for($attempt=0;$attempt -lt 50;$attempt++) {
        Start-Sleep -Milliseconds 100
        if (!(Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) { break }
        try { $current=Get-Content -LiteralPath $converterJobPath -Raw | ConvertFrom-Json } catch { continue }
        if ([int]$current.Pid -eq $process.Id -and $current.State -eq 'running') { $ready=$true; break }
    }
    if (!$ready) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw '转换任务包装器未能完成启动握手；请检查标准错误日志。'
    }
    New-Item -ItemType File -Path $readyMarker -Force | Out-Null
    $converterStatus.Text="$Kind 已启动 · PID $($process.Id)"
    $converterStatus.ForeColor=[Drawing.Color]::FromArgb(5,125,95)
}
function Update-ConverterStatus {
    $jobProcess=Get-ConverterJobProcess
    if ($jobProcess) {
        $job=Get-Content -LiteralPath $converterJobPath -Raw | ConvertFrom-Json
        if ($job.Result -and (Test-Path -LiteralPath $job.Result -PathType Leaf)) {
            try {
                $result=Get-Content -LiteralPath $job.Result -Raw | ConvertFrom-Json
                $converterStatus.Text="$($job.Kind) $($result.Status) · exit $($result.ExitCode) · $([IO.Path]::GetFileName([string]$job.Stdout))"
                $converterStatus.ForeColor=if($result.ExitCode -eq 0){[Drawing.Color]::FromArgb(5,125,95)}else{[Drawing.Color]::Firebrick}
                return
            } catch { }
        }
        $converterStatus.Text="$($job.Kind) 运行中 · PID $($jobProcess.ProcessId) · $([IO.Path]::GetFileName([string]$job.Stdout))"
        $converterStatus.ForeColor=[Drawing.Color]::FromArgb(5,125,95)
        return
    }
    if (Test-Path -LiteralPath $converterJobPath -PathType Leaf) {
        try {
            $job=Get-Content -LiteralPath $converterJobPath -Raw | ConvertFrom-Json
            if ($job.Result -and (Test-Path -LiteralPath $job.Result -PathType Leaf)) {
                $result=Get-Content -LiteralPath $job.Result -Raw | ConvertFrom-Json
                $converterStatus.Text="$($job.Kind) $($result.Status) · exit $($result.ExitCode) · 查看日志"
                $converterStatus.ForeColor=if($result.ExitCode -eq 0){[Drawing.Color]::FromArgb(5,125,95)}else{[Drawing.Color]::Firebrick}
                return
            }
            if ($job.Stdout -and (Test-Path -LiteralPath $job.Stdout)) {
                $converterStatus.Text="$($job.Kind) 已结束但未写入任务结果；请检查日志"
                $converterStatus.ForeColor=[Drawing.Color]::Firebrick
                return
            }
        } catch { }
    }
    if (Test-Path -LiteralPath (Join-Path $converterRoot 'env\Scripts\python.exe')) {
        $converterStatus.Text='转换器环境已安装。请先转换预检，再开始转换。'
        $converterStatus.ForeColor=[Drawing.Color]::DimGray
    }
}
$serviceProbe=[KVMemV018ServiceProbe]::new()
$script:nextServiceCheck=[DateTime]::MinValue
$script:nextConverterCheck=[DateTime]::MinValue
function Update-ServiceStatus {
    # Only consume completed work on the UI thread; network timeouts stay in the worker.
    if ($serviceProbe.IsCompleted) {
        $state=$serviceProbe.TakeResult()
        $status.Text=switch ($state) {
            'running' { "服务状态：运行中 · http://127.0.0.1:$port/" }
            'loading' { '服务状态：端口已监听，服务仍在加载' }
            'unknown' { '服务状态：无法读取端口状态' }
            default { '服务状态：未运行' }
        }
    }
    if ([DateTime]::UtcNow -ge $script:nextServiceCheck) {
        $serviceProbe.Start($port)
        $script:nextServiceCheck=[DateTime]::UtcNow.AddSeconds(2)
    }
}
function Start-V018Service {
    if (!$models.SelectedItem) { throw '请先选择 .ninfer 模型。' }
    $modelPath=[string]$models.SelectedItem
    if (!(Test-Path -LiteralPath $modelPath -PathType Leaf)) { throw '所选 NInfer 模型文件不存在。' }
    $c=[int]$context.Text; $b=[int]$budget.Text; $r=[int]$reserve.Text; $p=[int]$prefill.Text; $n=[int]$maxTokens.Text
    if ($b -lt 128 -or $r -lt 64 -or $c -lt 256 -or $n -lt 1 -or $p -lt 128) { throw 'Context、Budget、Reserve、Prefill 或最大输出超出允许范围。' }
    if ($b%64 -or $r%64 -or ($b+$r) -gt $c -or $p%128 -or $p -gt $r) {
        throw 'Budget/Reserve 必须为 64 倍数，Budget+Reserve ≤ Context，Prefill 必须为 128 倍数且 ≤ Reserve。'
    }
    if ($gpu.Text -notmatch '^\d+$') { throw 'GPU 编号必须为非负整数。' }
    if (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue) { throw "端口 $port 已被占用。" }
    Save-Config
    $arguments=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$startScript,'-Model',$modelPath,
        '-Gpu',$gpu.Text,'-Context',"$c",'-Budget',"$b",'-Reserve',"$r",'-Prefill',"$p",'-MaxTokens',"$n",
        '-HostMiB',"$($defaults.HostMiB)",'-ThinkingBudget',"$($defaults.ThinkingBudget)",'-SinkTokens',"$($defaults.SinkTokens)",'-RecentTokens',"$($defaults.RecentTokens)",
        '-VisionResidency',[string]$defaults.VisionResidency,'-VisionTokens',"$($defaults.VisionTokens)",
        '-Port',"$port",'-KvType',[string]$kvType.SelectedItem,'-MtpDrafts',"$([int]$mtp.Value)")
    if (!$vision.Checked) { $arguments += '-NoVision' }
    $argumentLine=($arguments | ForEach-Object { ConvertTo-ProcessArgument ([string]$_) }) -join ' '
    $pwsh=(Get-Command pwsh.exe -ErrorAction Stop).Source
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'; $stdout=Join-Path $logs "launcher-$stamp.stdout.log"; $stderr=Join-Path $logs "launcher-$stamp.stderr.log"
    $process=Start-Process -FilePath $pwsh -ArgumentList $argumentLine -WorkingDirectory $root -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
    Set-Content -LiteralPath $launcherPidPath -Value $process.Id -Encoding ascii
    $status.Text="服务启动中 · launcher PID $($process.Id)"
}

Refresh-Models; Update-ServiceStatus
if ($defaults.Model -and $models.Items.Contains([string]$defaults.Model)) { $models.SelectedItem=[string]$defaults.Model }
$refresh.Add_Click({Refresh-Models})
$browse.Add_Click({
    $dialog=[Windows.Forms.OpenFileDialog]::new(); $dialog.Filter='NInfer model (*.ninfer)|*.ninfer|All files (*.*)|*.*'
    if ($dialog.ShowDialog() -eq 'OK') { if(!$models.Items.Contains($dialog.FileName)){[void]$models.Items.Add($dialog.FileName)}; $models.SelectedItem=$dialog.FileName }
})
$chooseGguf.Add_Click({
    $dialog=[Windows.Forms.OpenFileDialog]::new(); $dialog.Filter='GGUF model (*.gguf)|*.gguf|All files (*.*)|*.*'
    if ($dialog.ShowDialog() -eq 'OK') {
        $ggufPath.Text=$dialog.FileName
        $name=[IO.Path]::GetFileNameWithoutExtension($dialog.FileName)
        $outputPath.Text=Join-Path $root "models\converted\$name.ninfer"
        $conversionResult.Text='已选择文件。请运行“转换预检”确认完整张量清单。'
    }
})
$browseResources.Add_Click({
    $dialog=[Windows.Forms.FolderBrowserDialog]::new(); $dialog.SelectedPath=$resourcesPath.Text
    if ($dialog.ShowDialog() -eq 'OK') { $resourcesPath.Text=$dialog.SelectedPath; Save-Config }
})
$browseVision.Add_Click({
    $dialog=[Windows.Forms.OpenFileDialog]::new(); $dialog.Filter='GGUF vision projector (*.gguf)|*.gguf|All files (*.*)|*.*'
    if ($dialog.ShowDialog() -eq 'OK') { $visionPath.Text=$dialog.FileName; $includeVision.Checked=$true; Save-Config }
})
$installConverter.Add_Click({
    try { Start-ConverterJob 'install' (Join-Path $converterRoot 'Install-Converter.ps1') @() }
    catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'NInfer 转换器','OK','Warning') }
})
$downloadResources.Add_Click({
    try {
        Start-ConverterJob 'resources' (Join-Path $converterRoot 'Download-ModelResources.ps1') @('-Destination',$resourcesPath.Text)
        Save-Config
    } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'模型资源','OK','Warning') }
})
$preflightConverter.Add_Click({
    try {
        if (!(Test-Path -LiteralPath $ggufPath.Text -PathType Leaf)) { throw '请先选择 GGUF 文件。' }
        $jobArgs=@('-Model',$ggufPath.Text,'-Resources',$resourcesPath.Text,'-Output',$(if($outputPath.Text){$outputPath.Text}else{'D:\preflight-only.ninfer'}),'-PreflightOnly')
        if ($includeVision.Checked) {
            if (!(Test-Path -LiteralPath $visionPath.Text -PathType Leaf)) { throw '已启用 Vision，但没有有效的 mmproj 文件。' }
            $jobArgs+=@('-Vision',$visionPath.Text,'-IncludeVision')
        }
        Start-ConverterJob 'preflight' (Join-Path $converterRoot 'Convert-GgufToNinfer.ps1') $jobArgs
    } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'GGUF 预检','OK','Warning') }
})
$runConverter.Add_Click({
    try {
        if (!(Test-Path -LiteralPath $ggufPath.Text -PathType Leaf)) { throw '请先选择 GGUF 文件。' }
        if (!(Test-Path -LiteralPath $resourcesPath.Text -PathType Container)) { throw '请先选择模型资源目录，或点击“获取 Qwen 资源”。' }
        if ([string]::IsNullOrWhiteSpace($outputPath.Text)) { throw '请指定一个新的 .ninfer 输出路径。' }
        $jobArgs=@('-Model',$ggufPath.Text,'-Resources',$resourcesPath.Text,'-Output',$outputPath.Text)
        if ($includeVision.Checked) {
            if (!(Test-Path -LiteralPath $visionPath.Text -PathType Leaf)) { throw '已启用 Vision，但没有有效的 mmproj 文件。' }
            $jobArgs+=@('-Vision',$visionPath.Text,'-IncludeVision')
        }
        Start-ConverterJob 'convert' (Join-Path $converterRoot 'Convert-GgufToNinfer.ps1') $jobArgs
        Save-Config
    } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'GGUF 转 NInfer','OK','Warning') }
})
$openConverterLogs.Add_Click({
    New-Item -ItemType Directory -Force -Path $converterLogs | Out-Null
    Start-Process explorer.exe -ArgumentList (ConvertTo-ProcessArgument $converterLogs)
})
$cancelConverter.Add_Click({
    $jobProcess=Get-ConverterJobProcess
    if (!$jobProcess) { $converterStatus.Text='没有运行中的转换任务。'; return }
    $tree=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue); $killIds=[Collections.Generic.HashSet[int]]::new(); [void]$killIds.Add([int]$jobProcess.ProcessId)
    do {
        $changed=$false
        foreach($candidate in $tree) {
            if ($killIds.Contains([int]$candidate.ParentProcessId) -and !$killIds.Contains([int]$candidate.ProcessId)) {
                [void]$killIds.Add([int]$candidate.ProcessId); $changed=$true
            }
        }
    } while($changed)
    $owned=[Collections.Generic.HashSet[int]]::new(); [void]$owned.Add([int]$jobProcess.ProcessId)
    do {
        $changed=$false
        foreach($candidate in $tree) {
            if ($killIds.Contains([int]$candidate.ProcessId) -and !$owned.Contains([int]$candidate.ProcessId) -and $candidate.CommandLine -and $candidate.CommandLine.Contains($converterRoot)) {
                [void]$owned.Add([int]$candidate.ProcessId); $changed=$true
            }
        }
    } while($changed)
    $job=Get-Content -LiteralPath $converterJobPath -Raw | ConvertFrom-Json
    foreach($id in @($owned | Sort-Object -Descending)) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    $result=@{Kind=$job.Kind;Script=$job.Script;Pid=$jobProcess.ProcessId;Started=$job.Started;Finished=(Get-Date).ToString('o');ExitCode=130;Status='已取消';Error='User cancelled from control panel.';Stdout=$job.Stdout;Stderr=$job.Stderr}
    $result|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $job.Result -Encoding utf8
    $job.State='cancelled';$job.ExitCode=130;$job.Finished=$result.Finished
    $job|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $converterJobPath -Encoding utf8
    $converterStatus.Text='已请求取消转换任务。'; $converterStatus.ForeColor=[Drawing.Color]::DarkOrange
})
$checkFileButton.Add_Click({
    if (!(Test-Path -LiteralPath $ggufPath.Text -PathType Leaf)) { [void][Windows.Forms.MessageBox]::Show('请选择存在的 GGUF 文件。'); return }
    $checkFileButton.Enabled=$false; $conversionResult.Text='正在流式读取 GGUF 元数据与张量目录…'; $form.Refresh()
    try {
        $result=[GGUFPreflight]::Check($ggufPath.Text)
        $mmproj=Get-ChildItem -LiteralPath (Split-Path $ggufPath.Text -Parent) -File -Filter '*mmproj*.gguf' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($mmproj) { $result += "`r`nSibling vision projector found: $($mmproj.Name)" }
        $conversionResult.Text=$result
    } catch { $conversionResult.Text="结构预检失败：$($_.Exception.Message)" }
    finally { $checkFileButton.Enabled=$true }
})
$conversionGuide.Add_Click({ Start-Process 'https://github.com/iamwavecut/ninfer-all/blob/8319e8f512477d0cfdef89e16c17c1ba9f9bc7b3/docs/weight-conversion.md' })
$start.Add_Click({ try { Start-V018Service } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'KVMem v0.18','OK','Warning') } })
$stop.Add_Click({
    try {
        & $stopScript -Port $port
        if (Test-Path -LiteralPath $launcherPidPath) {
            $id=[int](Get-Content -LiteralPath $launcherPidPath -Raw).Trim()
            $owner=Get-CimInstance Win32_Process -Filter "ProcessId = $id" -ErrorAction SilentlyContinue
            if ($owner -and $owner.Name -match '^(pwsh|powershell)\.exe$' -and $owner.CommandLine.Contains($startScript)) {
                Wait-Process -Id $id -Timeout 15 -ErrorAction SilentlyContinue
                $owner=Get-CimInstance Win32_Process -Filter "ProcessId = $id" -ErrorAction SilentlyContinue
                if ($owner -and $owner.CommandLine.Contains($startScript)) { Stop-Process -Id $id -Force }
            }
            Remove-Item -LiteralPath $launcherPidPath -Force
        }
        $status.Text='服务状态：已停止'
    } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'停止失败') }
})
$openWeb.Add_Click({ Start-Process "http://127.0.0.1:$port/" })
$timer=[Windows.Forms.Timer]::new(); $timer.Interval=100
$timer.Add_Tick({
    Update-ServiceStatus
    if ([DateTime]::UtcNow -ge $script:nextConverterCheck) {
        Update-ConverterStatus
        $script:nextConverterCheck=[DateTime]::UtcNow.AddSeconds(2)
    }
})
$timer.Start()
$form.Add_FormClosing({ Save-Config; $timer.Stop(); $serviceProbe.Dispose() })
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class KVMemV018Console { [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h,int c); public static void Hide(){var w=GetConsoleWindow();if(w!=IntPtr.Zero)ShowWindow(w,0);} }
'@
[KVMemV018Console]::Hide()
try { [void][Windows.Forms.Application]::Run($form) }
finally {
    $timer.Stop()
    $timer.Dispose()
    $serviceProbe.Dispose()
    $form.Dispose()
}
