$script:KVMemUiLanguage = 'zh'

# Canonical UI strings are Chinese. English values are used when the UI language is
# switched, and Get-KVMemUiText maps them back so language changes can be replayed
# without reloading the window.
$script:KVMemUiTranslations = [ordered]@{
    'KVMem 本地模型控制台' = 'KVMem Local Model Console'
    'KVMem 模型控制台' = 'KVMem Model Console'
    '本地 GGUF 推理 · 上下文缓存管理' = 'Local GGUF inference · context cache management'
    'KVMem 兼容性检查' = 'KVMem compatibility check'
    '没有匹配的 KVMem GGUF 后端' = 'No matching KVMem GGUF backend'

    '状态：正在检查服务…' = 'Status: Checking service...'
    '状态：正在检查 KVMem…' = 'Status: Checking KVMem...'
    '状态：未就绪（服务未启动或正在加载模型）' = 'Status: Not ready (server stopped or model loading)'
    '状态：服务运行中（无已加载模型）' = 'Status: Server running (no model loaded)'
    '状态：服务运行中（未返回模型 ID）' = 'Status: Server running (model ID not returned)'
    '状态：就绪，未找到 GGUF 模型' = 'Status: Ready, no GGUF models found'
    '状态：扫描失败' = 'Status: Model scan failed'
    '状态：正在扫描 GGUF 模型…' = 'Status: Scanning GGUF models...'
    '状态：KVMem 已停止' = 'Status: KVMem stopped'
    '状态：运行中 · 模型：' = 'Status: Running · Model: '
    '状态：操作命令已完成，等待服务就绪' = 'Status: Command completed; waiting for the server'
    '状态：模型层数读取失败' = 'Status: Could not read model layers'

    '模型与目录' = 'Models & folders'
    '选择要扫描的模型目录，或直接浏览单个 GGUF 文件。' = 'Choose the folder to scan, or browse to a single GGUF file.'
    '模型目录' = 'Model folder'
    '筛选模型' = 'Filter models'
    'GGUF 模型' = 'GGUF model'
    '所选文件' = 'Selected file'
    '视觉投影（可选）' = 'Vision projector (optional)'
    '选择目录…' = 'Choose folder...'
    '刷新列表' = 'Refresh list'
    '浏览 GGUF…' = 'Browse GGUF...'
    '选择 mmproj…' = 'Choose mmproj...'
    '清除' = 'Clear'
    '按文件名筛选本地 GGUF…' = 'Filter local GGUF files by name...'

    '加载与显存' = 'Model loading & VRAM'
    'GPU 自动层数读取所选 GGUF；模型过大时可取消自动，手动降低层数。' = 'GPU layers are read from the selected GGUF. Disable automatic mode to set a lower value manually.'
    'GPU 卸载层数' = 'GPU offload layers'
    '自动 GPU 层数' = 'Automatic GPU layers'
    '自动（选择模型后读取最大层数）' = 'Auto (read maximum after selecting a model)'
    '自动（正在读取模型最大层数…）' = 'Auto (reading maximum model layers...)'
    '自动（无法读取层数；可手动设置）' = 'Auto (layer count unavailable; set manually)'

    '上下文与 KV 缓存' = 'Context & KV cache'
    '这些参数在下次启动或切换模型时生效。更大的上下文与缓存可能增加内存占用。' = 'These settings apply the next time a model starts or switches. Larger context and caches use more memory.'
    '上下文长度（tokens）' = 'Context length (tokens)'
    'KV 缓存精度' = 'KV cache type'
    'KVMem GPU 缓存预算（tokens）' = 'KVMem GPU cache budget (tokens)'
    '生成预留（tokens）' = 'Generation reserve (tokens)'
    'KVMem CPU 缓存（GiB）' = 'KVMem CPU cache (GiB)'

    '生成与采样' = 'Generation & sampling'
    '这里设置服务默认值；客户端请求中的采样参数会覆盖对应的服务默认值。' = 'Service defaults. Sampling parameters in client requests override these values.'
    '最大生成长度（tokens，-1 = 不限）' = 'Maximum generation length (tokens, -1 = unlimited)'
    '温度（Temperature）' = 'Temperature'
    'Top-P' = 'Top-P'
    'Top-K' = 'Top-K'
    'Min-P' = 'Min-P'
    '重复惩罚' = 'Repeat penalty'
    '存在惩罚（Presence penalty）' = 'Presence penalty'
    '频率惩罚（Frequency penalty）' = 'Frequency penalty'
    '随机种子（-1 = 随机）' = 'Random seed (-1 = random)'
    '思考模式' = 'Thinking mode'
    '禁用思考' = 'Disable thinking'
    '模型默认' = 'Model default'
    'Flash Attention' = 'Flash Attention'
    '模型加载方式' = 'Model load mode'
    'CPU 线程（0 = 自动）' = 'CPU threads (0 = auto)'
    '批处理线程（0 = 跟随 CPU 线程）' = 'Batch threads (0 = follow CPU threads)'
    '逻辑批大小（batch）' = 'Logical batch size'
    '物理批大小（ubatch）' = 'Physical batch size'

    '客户端 API：http://127.0.0.1:18200/v1    模型：kvmem-current' = 'Client API: http://127.0.0.1:18200/v1    Model: kvmem-current'
    '启动 / 切换模型' = 'Start / switch model'
    '停止 KVMem' = 'Stop KVMem'
    '打开 KVMem 页面' = 'Open KVMem page'
    '查看运行日志' = 'View runtime logs'
    '复制客户端地址' = 'Copy client URL'
    '运行记录' = 'Activity log'
    '清空记录' = 'Clear log'
    '提示：长文件路径可选中后复制；参数支持鼠标滚轮，页签内容不足时可向下滚动。' = 'Tip: Select long paths to copy them. Numeric settings support the mouse wheel; scroll tabs when needed.'
    '本地运行 · 模型与日志不会上传' = 'Runs locally · models and logs are never uploaded'

    'KVMem 运行日志' = 'KVMem Runtime Logs'
    '刷新日志列表' = 'Refresh log list'
    '选择左侧文件查看末尾 500 行；后台仍可继续写入日志。' = 'Select a file to view its last 500 lines. Logs may continue updating.'
    '日志文件读取失败' = 'Could not read the log file'
    '日志文件为空。' = 'This log file is empty.'
    '模型扫描失败' = 'Model scan failed'
    '端口冲突' = 'Port conflict'
    '切换模型' = 'Switch model'
    '选择要扫描 GGUF 模型的目录' = 'Choose a folder to scan for GGUF models'
    '选择任意 GGUF 模型' = 'Choose a GGUF model'
    '选择视觉投影文件（可选）' = 'Choose a vision projector (optional)'
    'GGUF 模型 (*.gguf)|*.gguf|所有文件 (*.*)|*.*' = 'GGUF models (*.gguf)|*.gguf|All files (*.*)|*.*'
    'mmproj 文件 (*.gguf)|*.gguf|所有文件 (*.*)|*.*' = 'mmproj files (*.gguf)|*.gguf|All files (*.*)|*.*'
    '没有错误输出' = 'No error output'
    'KVMem 操作失败' = 'KVMem operation failed'
    'KVMem 当前没有运行，无需停止。' = 'KVMem is not running.'
    '已有启动或停止操作正在执行。' = 'A start or stop operation is already in progress.'
    'KVMem GPU 兼容性资源缺失。' = 'KVMem GPU compatibility resources are missing.'
    '没有匹配的模型。可修改筛选文字，或使用“浏览 GGUF”。' = 'No matching models. Change the filter or use Browse GGUF.'
    '暂无日志；启动模型后会产生运行日志。' = 'No logs yet. Runtime logs are created after a model starts.'
    '中文' = 'Chinese'
    '命令已完成。模型加载可能需要一段时间，服务就绪后状态会显示运行中。' = 'Command completed. Model loading may take a while; status changes to Running when ready.'
    '请先启动模型；模型加载完成后才能打开 KVMem 页面。' = 'Start a model first. The KVMem page is available after it loads.'
    '请先选择一个存在的 GGUF 文件。' = 'Select an existing GGUF file first.'
    '正在读取该 GGUF 的层数，或元数据无法识别。请稍候，或取消自动并手动设置 GPU 层数。' = 'Reading GGUF layers or metadata is unavailable. Wait, or disable Auto and set GPU layers manually.'
    '正在扫描模型，请稍候。' = 'Model scan in progress. Please wait.'
    '已打开运行日志窗口。可选择 stdout、stderr 或控制器错误日志。' = 'Runtime logs opened. Choose stdout, stderr, or controller errors.'
    '已复制客户端 API 地址。模型 ID：kvmem-current' = 'Client API URL copied. Model ID: kvmem-current'
    '已清除视觉投影文件。' = 'Vision projector cleared.'
    '已清空运行记录。' = 'Activity log cleared.'
    '正在停止 KVMem' = 'Stopping KVMem'
    'KVMem 已停止。' = 'KVMem stopped.'
}

function Set-KVMemUiLanguage {
    param([ValidateSet('zh', 'en')][string]$Language)
    $script:KVMemUiLanguage = $Language
}

function Get-KVMemUiLanguage { return $script:KVMemUiLanguage }

function Convert-KVMemUiText {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text -or $script:KVMemUiLanguage -eq 'zh') { return $Text }
    if ($script:KVMemUiTranslations.Contains($Text)) { return $script:KVMemUiTranslations[$Text] }

    $patterns = @(
        @('^自动（模型最大 (\d+) 层）$', 'Auto (model maximum: {0} layers)'),
        @('^状态：就绪，共找到 (\d+) 个 GGUF 模型$', 'Status: Ready, {0} GGUF model(s) found'),
        @('^状态：正在加载 (.+)$', 'Status: Loading {0}'),
        @('^状态：([^…]+) …$', 'Status: {0}...'),
        @('^状态：操作失败（退出码 (\d+)）$', 'Status: Operation failed (exit code {0})'),
        @('^操作失败（退出码 (\d+)）$', 'Operation failed (exit code {0})'),
        @('^正在加载 (.+)$', 'Loading {0}')
    )
    foreach ($pattern in $patterns) {
        if ($Text -match $pattern[0]) { return ($pattern[1] -f $Matches[1]) }
    }

    $result = $Text
    $result = $result.Replace('状态：运行中 · 模型：', 'Status: Running · Model: ')
    $result = $result.Replace('状态：', 'Status: ')
    $result = $result.Replace('正在停止 KVMem', 'Stopping KVMem')
    $result = $result.Replace('正在加载 ', 'Loading ')
    $result = $result.Replace('扫描完成：找到 ', 'Scan complete: found ')
    $result = $result.Replace(' 个 GGUF 模型。', ' GGUF model(s).')
    $result = $result.Replace('操作失败：', 'Operation failed: ')
    $result = $result.Replace('；详情记录在 ', '; details: ')
    $result = $result.Replace('找不到目录：', 'Folder not found: ')
    $result = $result.Replace('找不到 mmproj：', 'mmproj not found: ')
    $result = $result.Replace('18200 端口属于其他程序（PID ', 'Port 18200 belongs to another process (PID ')
    $result = $result.Replace('），已取消。', '); cancelled.')
    $result = $result.Replace('18200 端口由其他程序使用（PID ', 'Port 18200 is used by another process (PID ')
    $result = $result.Replace('），未做更改。', '); no changes made.')
    $result = $result.Replace('当前模型将停止并切换到所选模型。继续？', 'The current model will stop and switch to the selected model. Continue?')
    $result = $result.Replace('旧服务未释放 18200 端口', 'The previous server did not release port 18200')
    return $result
}

function Get-KVMemUiText {
    param([AllowNull()][string]$Text)
    if ($script:KVMemUiLanguage -eq 'en') { return Convert-KVMemUiText $Text }
    if ($null -eq $Text) { return $null }

    foreach ($key in $script:KVMemUiTranslations.Keys) {
        if ($script:KVMemUiTranslations[$key] -ceq $Text) { return $key }
    }

    $patterns = @(
        @('^Auto \(model maximum: (\d+) layers\)$', '自动（模型最大 {0} 层）'),
        @('^Status: Ready, (\d+) GGUF model\(s\) found$', '状态：就绪，共找到 {0} 个 GGUF 模型'),
        @('^Status: Loading (.+)$', '状态：正在加载 {0}'),
        @('^Status: (.+)\.\.\.$', '状态：{0} …'),
        @('^Status: Operation failed \(exit code (\d+)\)$', '状态：操作失败（退出码 {0}）'),
        @('^Operation failed \(exit code (\d+)\)$', '操作失败（退出码 {0}）')
    )
    foreach ($pattern in $patterns) {
        if ($Text -match $pattern[0]) { return ($pattern[1] -f $Matches[1]) }
    }

    $Text = $Text.Replace('Status: Running · Model: ', '状态：运行中 · 模型：')
    $Text = $Text.Replace('Status: ', '状态：')
    $Text = $Text.Replace('Stopping KVMem', '正在停止 KVMem')
    $Text = $Text.Replace('Loading ', '正在加载 ')
    $Text = $Text.Replace('Scan complete: found ', '扫描完成：找到 ')
    $Text = $Text.Replace(' GGUF model(s).', ' 个 GGUF 模型。')
    $Text = $Text.Replace('Operation failed: ', '操作失败：')
    $Text = $Text.Replace('); details: ', '）；详情记录在 ')
    return $Text
}

Export-ModuleMember -Function Set-KVMemUiLanguage, Get-KVMemUiLanguage, Convert-KVMemUiText, Get-KVMemUiText
