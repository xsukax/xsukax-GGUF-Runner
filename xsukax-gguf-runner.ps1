<#
.SYNOPSIS
    xsukax GGUF Runner - Complete AI Model Interface for Windows
    
.DESCRIPTION
    Menu-driven tool with smooth streaming AI responses, auto-downloads llama.cpp,
    manages GGUF models, provides interactive chat, API server, and GUI modes.
    
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\xsukax-gguf-runner.ps1
    
.NOTES
    Author: xsukax
    License: GPL v3.0
    Version: 2.5.0 - Smooth Streaming
#>

[CmdletBinding()]
param([switch]$Help)

$ErrorActionPreference = 'Stop'
$script:Version = '2.5.0'
$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:LlamaDir = Join-Path $script:ScriptDir 'llama'
$script:ModelsDir = Join-Path $script:ScriptDir 'ggufs'
$script:ConfigFile = Join-Path $script:ScriptDir 'gguf-config.json'
$script:ChatHistoryFile = Join-Path $script:ScriptDir 'chat-history.json'
$script:LlamaVersion = 'b7839'
$script:ServerProcess = $null

$script:DefaultConfig = @{
    Temperature = 0.8
    ContextSize = 4096
    MaxTokens = 2048
    GpuLayers = 0
    ServerPort = 8080
    Threads = 0
    LastModel = ''
}

$script:Config = $script:DefaultConfig.Clone()

function Write-Success { param([string]$Msg); Write-Host ('  [OK] ' + $Msg) -ForegroundColor Green }
function Write-Err { param([string]$Msg); Write-Host ('  [ERROR] ' + $Msg) -ForegroundColor Red }
function Write-Warn { param([string]$Msg); Write-Host ('  [!] ' + $Msg) -ForegroundColor Yellow }
function Write-Inf { param([string]$Msg); Write-Host ('  [i] ' + $Msg) -ForegroundColor Cyan }
function Write-Dim { param([string]$Msg); Write-Host ('      ' + $Msg) -ForegroundColor DarkGray }

function Write-Logo {
    Write-Host ''
    Write-Host '    =================================================================' -ForegroundColor Cyan
    Write-Host '    |    X   X  SSSS  U   U  K   K   AAA   X   X                    |' -ForegroundColor Cyan
    Write-Host '    |     X X  S      U   U  K  K   A   A   X X                     |' -ForegroundColor Cyan
    Write-Host '    |      X    SSS   U   U  KKK    AAAAA    X                      |' -ForegroundColor Cyan
    Write-Host '    |     X X      S  U   U  K  K   A   A   X X                     |' -ForegroundColor Cyan
    Write-Host '    |    X   X  SSSS   UUU   K   K  A   A  X   X                    |' -ForegroundColor Cyan
    Write-Host '    |                                                               |' -ForegroundColor Cyan
    Write-Host '    |                   GGUF Runner v2.5.0                          |' -ForegroundColor White
    Write-Host '    |           Smooth Streaming AI Interface                       |' -ForegroundColor Gray
    Write-Host '    =================================================================' -ForegroundColor Cyan
    Write-Host ''
}

function Write-MenuHeader {
    param([string]$Title)
    Write-Host ''
    Write-Host '  -----------------------------------------------------------------' -ForegroundColor DarkCyan
    Write-Host ('  | ' + $Title) -ForegroundColor White
    Write-Host '  -----------------------------------------------------------------' -ForegroundColor DarkCyan
    Write-Host ''
}

function Write-MenuItem {
    param([string]$Key, [string]$Text, [string]$Status = '')
    $line = '      [' + $Key + '] ' + $Text
    if ($Status -ne '') { $line = $line + ' (' + $Status + ')' }
    Write-Host $line -ForegroundColor White
}

function Write-Separator { Write-Host '      --------------------------------------------------------' -ForegroundColor DarkGray }

function Write-StatusBar {
    $modelStatus = if ($script:Config.LastModel -and (Test-Path $script:Config.LastModel -ErrorAction SilentlyContinue)) { Split-Path $script:Config.LastModel -Leaf } else { 'None selected' }
    $gpuStatus = if ($script:Config.GpuLayers -eq 0) { 'CPU' } elseif ($script:Config.GpuLayers -eq -1) { 'GPU Auto' } else { 'GPU ' + $script:Config.GpuLayers + 'L' }
    Write-Host ''
    Write-Host '  --- Status ---' -ForegroundColor DarkGray
    Write-Host ('  Model: ' + $modelStatus) -ForegroundColor Cyan
    Write-Host ('  Context: ' + $script:Config.ContextSize + ' | Mode: ' + $gpuStatus) -ForegroundColor Green
}

function Read-MenuChoice {
    param([string]$Prompt = 'Select option')
    Write-Host ''
    Write-Host '  >> ' -ForegroundColor Yellow -NoNewline
    return Read-Host $Prompt
}

function Pause-Continue {
    Write-Host ''
    Write-Host '  Press any key to continue...' -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

function Load-Config {
    if (Test-Path $script:ConfigFile) {
        try {
            $loaded = Get-Content $script:ConfigFile -Raw | ConvertFrom-Json
            foreach ($key in $script:DefaultConfig.Keys) {
                if ($loaded.PSObject.Properties.Name -contains $key) {
                    $script:Config[$key] = $loaded.$key
                }
            }
        } catch { $script:Config = $script:DefaultConfig.Clone() }
    }
}

function Save-Config {
    try { $script:Config | ConvertTo-Json | Set-Content $script:ConfigFile -Force } catch { }
}

function Initialize-Folders {
    if (-not (Test-Path $script:LlamaDir)) { New-Item -ItemType Directory -Path $script:LlamaDir -Force | Out-Null }
    if (-not (Test-Path $script:ModelsDir)) { New-Item -ItemType Directory -Path $script:ModelsDir -Force | Out-Null }
}

function Download-WithProgress {
    param([string]$Url, [string]$OutputPath)
    try {
        Write-Inf 'Starting download...'
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($Url, $OutputPath)
        return (Test-Path $OutputPath)
    } catch {
        Write-Err ('Download failed: ' + $_.Exception.Message)
        return $false
    }
}

function Extract-Archive {
    param([string]$ZipPath, [string]$DestPath)
    try {
        Write-Inf 'Extracting archive...'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $DestPath)
        return $true
    } catch {
        Write-Err ('Extraction failed: ' + $_.Exception.Message)
        return $false
    }
}

function Install-LlamaCpp {
    Clear-Host
    Write-Logo
    Write-MenuHeader 'LLAMA.CPP AUTO-INSTALLER'
    
    $hasCuda = $false
    try {
        $null = nvidia-smi 2>&1
        if ($LASTEXITCODE -eq 0) { $hasCuda = $true; Write-Success 'NVIDIA GPU detected' }
    } catch { Write-Inf 'No NVIDIA GPU - using CPU version' }
    
    if ($hasCuda) {
        $fileName = 'llama-' + $script:LlamaVersion + '-bin-win-cuda-12.4-x64.zip'
        $fileSize = '~210 MB'
    } else {
        $fileName = 'llama-' + $script:LlamaVersion + '-bin-win-cpu-x64.zip'
        $fileSize = '~29 MB'
    }
    
    $downloadUrl = 'https://github.com/ggml-org/llama.cpp/releases/download/' + $script:LlamaVersion + '/' + $fileName
    $zipPath = Join-Path $script:ScriptDir $fileName
    
    Write-Host ''
    Write-Inf ('Version: ' + $script:LlamaVersion)
    Write-Inf ('Size: ' + $fileSize)
    Write-Host ''
    
    if (-not (Download-WithProgress -Url $downloadUrl -OutputPath $zipPath)) {
        Write-Err 'Download failed'
        Pause-Continue
        return $false
    }
    
    if (-not (Extract-Archive -ZipPath $zipPath -DestPath $script:LlamaDir)) {
        Pause-Continue
        return $false
    }
    
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Write-Success 'llama.cpp installed successfully!'
    Start-Sleep -Seconds 2
    return $true
}

function Find-Executable {
    param([string]$Name)
    $searchPaths = @(
        (Join-Path $script:LlamaDir ($Name + '.exe')),
        (Join-Path $script:LlamaDir ('bin\' + $Name + '.exe')),
        (Join-Path $script:LlamaDir ('build\bin\Release\' + $Name + '.exe'))
    )
    foreach ($p in $searchPaths) { if (Test-Path $p) { return $p } }
    $found = Get-ChildItem -Path $script:LlamaDir -Filter ($Name + '.exe') -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

function Get-LlamaCli {
    foreach ($n in @('llama-cli', 'main', 'llama')) {
        $p = Find-Executable -Name $n
        if ($p) { return $p }
    }
    return $null
}

function Get-LlamaServer {
    foreach ($n in @('llama-server', 'server')) {
        $p = Find-Executable -Name $n
        if ($p) { return $p }
    }
    return $null
}

function Ensure-LlamaCpp {
    $exe = Get-LlamaCli
    if (-not $exe) {
        Write-Warn 'llama.cpp not found - starting download...'
        Start-Sleep -Seconds 1
        if (-not (Install-LlamaCpp)) { return $null }
        $exe = Get-LlamaCli
    }
    return $exe
}

function Get-Models {
    if (-not (Test-Path $script:ModelsDir)) { return @() }
    return Get-ChildItem -Path $script:ModelsDir -Filter '*.gguf' -File | Sort-Object Name
}

function Get-ModelInfo {
    param([System.IO.FileInfo]$Model)
    $info = @{ Name = $Model.Name; SizeGB = [math]::Round($Model.Length / 1GB, 2); Quant = ''; Params = '' }
    if ($Model.Name -match '(Q\d+_[KM0-9_]+)') { $info.Quant = $matches[1] }
    if ($Model.Name -match '(\d+[Bb])') { $info.Params = $matches[1].ToUpper() }
    return $info
}

function Show-ModelSelector {
    Clear-Host
    Write-Logo
    Write-MenuHeader 'SELECT GGUF MODEL'
    $models = Get-Models
    
    if ($models.Count -eq 0) {
        Write-Warn 'No GGUF models found!'
        Write-Host ''
        Write-Inf ('Models folder: ' + $script:ModelsDir)
        Write-Host ''
        Write-Dim 'Download models from: https://huggingface.co/models?library=gguf'
        Pause-Continue
        return $null
    }
    
    Write-Success ('Found ' + $models.Count + ' model(s)')
    Write-Host ''
    
    for ($i = 0; $i -lt $models.Count; $i++) {
        $info = Get-ModelInfo -Model $models[$i]
        $num = $i + 1
        Write-Host ('      [' + $num + '] ' + $info.Name) -ForegroundColor Green
        $details = '          ' + $info.SizeGB + ' GB'
        if ($info.Params -ne '') { $details = $details + ' - ' + $info.Params }
        if ($info.Quant -ne '') { $details = $details + ' - ' + $info.Quant }
        Write-Host $details -ForegroundColor DarkGray
        Write-Host ''
    }
    
    Write-Separator
    Write-MenuItem '0' 'Back to main menu'
    $selection = Read-MenuChoice 'Select model'
    
    if ($selection -eq '0' -or $selection -eq '') { return $null }
    
    $idx = 0
    if ([int]::TryParse($selection, [ref]$idx)) {
        $idx = $idx - 1
        if ($idx -ge 0 -and $idx -lt $models.Count) {
            $script:Config.LastModel = $models[$idx].FullName
            Save-Config
            return $models[$idx].FullName
        }
    }
    
    Write-Warn 'Invalid selection'
    Start-Sleep -Seconds 1
    return Show-ModelSelector
}

function Build-LlamaArgs {
    param([string]$ModelPath, [switch]$IsServer)
    $argList = @('-m', $ModelPath, '-c', $script:Config.ContextSize)
    
    if (-not $IsServer) {
        $argList += '-n'
        $argList += $script:Config.MaxTokens
        $argList += '--temp'
        $argList += $script:Config.Temperature
    }
    
    $threads = if ($script:Config.Threads -gt 0) { $script:Config.Threads } else { [Environment]::ProcessorCount }
    $argList += '-t'
    $argList += $threads
    
    if ($script:Config.GpuLayers -ne 0) {
        $layers = if ($script:Config.GpuLayers -eq -1) { 999 } else { $script:Config.GpuLayers }
        $argList += '-ngl'
        $argList += $layers
    }
    
    return $argList
}

function Start-InteractiveMode {
    param([string]$ModelPath)
    $exe = Ensure-LlamaCpp
    if (-not $exe) { Write-Err 'llama.cpp not available'; Pause-Continue; return }
    
    Clear-Host
    Write-Logo
    Write-MenuHeader 'INTERACTIVE CHAT'
    Write-Inf ('Model: ' + (Split-Path $ModelPath -Leaf))
    Write-Host ''
    Write-Host '  Type messages below. Press Ctrl+C to exit.' -ForegroundColor DarkGray
    Write-Host '  =================================================================' -ForegroundColor DarkCyan
    Write-Host ''
    
    $argList = Build-LlamaArgs -ModelPath $ModelPath
    $argList += '-cnv'
    & $exe @argList
}

function Start-SinglePromptMode {
    param([string]$ModelPath)
    $exe = Ensure-LlamaCpp
    if (-not $exe) { Write-Err 'llama.cpp not available'; Pause-Continue; return }
    
    Clear-Host
    Write-Logo
    Write-MenuHeader 'SINGLE PROMPT MODE'
    Write-Inf ('Model: ' + (Split-Path $ModelPath -Leaf))
    Write-Host ''
    Write-Host '  Enter your prompt (press Enter twice to submit):' -ForegroundColor White
    Write-Host ''
    
    $lines = @()
    do {
        $line = Read-Host '  '
        if ($line -eq '' -and $lines.Count -gt 0) { break }
        if ($line -ne '') { $lines += $line }
    } while ($true)
    
    $prompt = $lines -join "`n"
    if ($prompt.Trim() -eq '') { Write-Warn 'No prompt entered'; Pause-Continue; return }
    
    Write-Host ''
    Write-Host '  =================================================================' -ForegroundColor DarkCyan
    Write-Host ''
    
    $argList = Build-LlamaArgs -ModelPath $ModelPath
    $argList += '-p'
    $argList += $prompt
    & $exe @argList
    
    Write-Host ''
    Pause-Continue
}

function Start-ServerMode {
    param([string]$ModelPath)
    $exe = Get-LlamaServer
    if (-not $exe) { Write-Err 'llama-server not found'; Pause-Continue; return }
    
    Clear-Host
    Write-Logo
    Write-MenuHeader 'API SERVER MODE'
    Write-Success 'Starting API server...'
    Write-Host ''
    Write-Inf ('Model: ' + (Split-Path $ModelPath -Leaf))
    Write-Inf ('Port: ' + $script:Config.ServerPort)
    Write-Host ''
    Write-Host '  --- Endpoints ---' -ForegroundColor Green
    Write-Host ('  Web UI:   http://localhost:' + $script:Config.ServerPort) -ForegroundColor White
    Write-Host ('  Chat API: http://localhost:' + $script:Config.ServerPort + '/v1/chat/completions') -ForegroundColor White
    Write-Host ''
    Write-Warn 'Press Ctrl+C to stop the server'
    Write-Host '  =================================================================' -ForegroundColor DarkCyan
    Write-Host ''
    
    $argList = Build-LlamaArgs -ModelPath $ModelPath -IsServer
    $argList += '--port'
    $argList += $script:Config.ServerPort
    & $exe @argList
}

function Stop-ServerProcess {
    param([int]$Port)
    try {
        $connections = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        foreach ($conn in $connections) {
            if ($conn.OwningProcess -gt 0) {
                Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
            }
        }
    } catch { }
    
    if ($null -ne $script:ServerProcess) {
        try { if (-not $script:ServerProcess.HasExited) { $script:ServerProcess.Kill() } } catch { }
        $script:ServerProcess = $null
    }
}

function Test-ServerReady {
    param([int]$Port, [int]$TimeoutSeconds = 180)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        try {
            $testUrl = 'http://127.0.0.1:' + $Port + '/v1/models'
            $response = Invoke-RestMethod -Uri $testUrl -Method Get -TimeoutSec 5 -ErrorAction Stop
            if ($response) { return $true }
        } catch { }
        
        Write-Host '.' -NoNewline -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
    
    return $false
}

function Start-GuiChatClient {
    $modelPath = $null
    if ($script:Config.LastModel -and (Test-Path $script:Config.LastModel -ErrorAction SilentlyContinue)) {
        $modelPath = $script:Config.LastModel
    } else {
        $modelPath = Show-ModelSelector
    }
    
    if (-not $modelPath) { Write-Warn 'No model selected'; Pause-Continue; return }
    
    $serverExe = Get-LlamaServer
    if (-not $serverExe) { Write-Err 'llama-server not found'; Pause-Continue; return }
    
    Clear-Host
    Write-Logo
    Write-MenuHeader 'STARTING GUI CHAT'
    Write-Inf ('Model: ' + (Split-Path $modelPath -Leaf))
    Write-Inf ('Port: ' + $script:Config.ServerPort)
    Write-Host ''
    
    Write-Inf 'Stopping any existing server...'
    Stop-ServerProcess -Port $script:Config.ServerPort
    Start-Sleep -Seconds 2
    
    Write-Inf 'Starting API server...'
    
    $argList = Build-LlamaArgs -ModelPath $modelPath -IsServer
    $argList += '--port'
    $argList += $script:Config.ServerPort
    $argString = $argList -join ' '
    
    $script:ServerProcess = Start-Process -FilePath $serverExe -ArgumentList $argString -WindowStyle Minimized -PassThru
    
    if ($null -eq $script:ServerProcess) { Write-Err 'Failed to start server'; Pause-Continue; return }
    
    Write-Host '  [i] Waiting for model to load ' -ForegroundColor Cyan -NoNewline
    
    $ready = Test-ServerReady -Port $script:Config.ServerPort -TimeoutSeconds 180
    Write-Host ''
    
    if (-not $ready) {
        Write-Err 'Server did not start in time'
        Stop-ServerProcess -Port $script:Config.ServerPort
        Pause-Continue
        return
    }
    
    Write-Success 'Server is ready!'
    Write-Inf 'Launching GUI with smooth streaming...'
    Start-Sleep -Seconds 1
    
    $apiUrl = 'http://127.0.0.1:' + $script:Config.ServerPort + '/v1/chat/completions'
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName Microsoft.VisualBasic
    
    # Add Win32 API for smooth scrolling
    $smoothScrollCode = @'
using System;
using System.Runtime.InteropServices;
public class SmoothScroll {
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
    
    public const int WM_VSCROLL = 0x115;
    public const int SB_BOTTOM = 7;
    public const int WM_SETREDRAW = 0x000B;
    
    public static void ScrollToBottom(IntPtr handle) {
        SendMessage(handle, WM_VSCROLL, (IntPtr)SB_BOTTOM, IntPtr.Zero);
    }
    
    public static void SuspendDrawing(IntPtr handle) {
        SendMessage(handle, WM_SETREDRAW, IntPtr.Zero, IntPtr.Zero);
    }
    
    public static void ResumeDrawing(IntPtr handle) {
        SendMessage(handle, WM_SETREDRAW, (IntPtr)1, IntPtr.Zero);
    }
}
'@
    
    try {
        Add-Type -TypeDefinition $smoothScrollCode -Language CSharp -ErrorAction SilentlyContinue
    } catch { }
    
    $script:Conversations = @()
    $script:CurrentConvId = $null
    $script:IsProcessing = $false
    $script:StopRequested = $false
    $script:TextBuffer = ''
    $script:LastScrollTime = [DateTime]::Now
    
    if (Test-Path $script:ChatHistoryFile) {
        try {
            $loaded = Get-Content $script:ChatHistoryFile -Raw | ConvertFrom-Json
            if ($loaded) {
                if ($loaded -is [Array]) { $script:Conversations = @($loaded) }
                else { $script:Conversations = @($loaded) }
            }
        } catch { $script:Conversations = @() }
    }
    
    function Save-ChatHistory {
        try {
            if ($script:Conversations.Count -gt 0) {
                $script:Conversations | ConvertTo-Json -Depth 10 -Compress | Set-Content $script:ChatHistoryFile -Force
            }
        } catch { }
    }
    
    function Get-CurrentConversation {
        if ($null -eq $script:CurrentConvId) { return $null }
        foreach ($c in $script:Conversations) { if ($c.id -eq $script:CurrentConvId) { return $c } }
        return $null
    }
    
    function Update-ConversationList {
        $script:ListBox.Items.Clear()
        foreach ($c in $script:Conversations) { $script:ListBox.Items.Add($c.title) | Out-Null }
        if ($script:CurrentConvId) {
            for ($i = 0; $i -lt $script:Conversations.Count; $i++) {
                if ($script:Conversations[$i].id -eq $script:CurrentConvId) {
                    $script:ListBox.SelectedIndex = $i
                    break
                }
            }
        }
    }
    
    function Scroll-ToBottom {
        try {
            [SmoothScroll]::ScrollToBottom($script:ChatBox.Handle)
        } catch {
            $script:ChatBox.SelectionStart = $script:ChatBox.TextLength
            $script:ChatBox.ScrollToCaret()
        }
    }
    
    function Append-TextSmooth {
        param([string]$Text, [System.Drawing.Color]$Color, [bool]$Bold = $false)
        
        $script:ChatBox.SelectionStart = $script:ChatBox.TextLength
        $script:ChatBox.SelectionLength = 0
        $script:ChatBox.SelectionColor = $Color
        
        if ($Bold) {
            $script:ChatBox.SelectionFont = New-Object System.Drawing.Font($script:ChatBox.Font.FontFamily, $script:ChatBox.Font.Size, [System.Drawing.FontStyle]::Bold)
        } else {
            $script:ChatBox.SelectionFont = New-Object System.Drawing.Font($script:ChatBox.Font.FontFamily, $script:ChatBox.Font.Size, [System.Drawing.FontStyle]::Regular)
        }
        
        $script:ChatBox.AppendText($Text)
    }
    
    function Update-ChatDisplay {
        $script:ChatBox.Clear()
        $conv = Get-CurrentConversation
        
        if ($null -eq $conv -or $conv.messages.Count -eq 0) {
            Append-TextSmooth -Text ('Welcome to xsukax AI Chat' + [Environment]::NewLine + [Environment]::NewLine) -Color ([System.Drawing.Color]::FromArgb(100, 149, 237)) -Bold $true
            Append-TextSmooth -Text ('Start by typing a message below.' + [Environment]::NewLine) -Color ([System.Drawing.Color]::Gray)
            Append-TextSmooth -Text ('Responses stream smoothly in real-time!' + [Environment]::NewLine) -Color ([System.Drawing.Color]::Gray)
            $script:TitleLabel.Text = 'xsukax AI Chat GUI'
            return
        }
        
        $script:TitleLabel.Text = $conv.title
        
        foreach ($msg in $conv.messages) {
            $isUser = ($msg.role -eq 'user')
            
            if ($isUser) {
                Append-TextSmooth -Text ('YOU: ' + [Environment]::NewLine) -Color ([System.Drawing.Color]::LimeGreen) -Bold $true
                Append-TextSmooth -Text ($msg.content + [Environment]::NewLine + [Environment]::NewLine) -Color ([System.Drawing.Color]::White)
            } else {
                Append-TextSmooth -Text ('AI: ' + [Environment]::NewLine) -Color ([System.Drawing.Color]::Cyan) -Bold $true
                Append-TextSmooth -Text ($msg.content + [Environment]::NewLine + [Environment]::NewLine) -Color ([System.Drawing.Color]::FromArgb(220, 220, 220))
            }
        }
        
        Scroll-ToBottom
    }
    
    function New-Conversation {
        $newConv = @{
            id = [System.Guid]::NewGuid().ToString()
            title = 'New Chat'
            messages = @()
            createdAt = (Get-Date).ToString('o')
        }
        $script:Conversations = @($newConv) + @($script:Conversations)
        $script:CurrentConvId = $newConv.id
        Save-ChatHistory
        Update-ConversationList
        Update-ChatDisplay
    }
    
    function Send-StreamingMessage {
        $userText = $script:InputBox.Text.Trim()
        if ($userText -eq '') { return }
        
        if ($script:IsProcessing) {
            $script:StopRequested = $true
            return
        }
        
        $conv = Get-CurrentConversation
        if ($null -eq $conv) { New-Conversation; $conv = Get-CurrentConversation }
        
        $userMsg = @{ role = 'user'; content = $userText }
        $conv.messages = @($conv.messages) + @($userMsg)
        
        if ($conv.messages.Count -eq 1 -or $conv.title -eq 'New Chat') {
            $maxLen = [Math]::Min(35, $userText.Length)
            $conv.title = $userText.Substring(0, $maxLen)
            if ($userText.Length -gt 35) { $conv.title = $conv.title + '...' }
            Update-ConversationList
        }
        
        $script:InputBox.Text = ''
        Update-ChatDisplay
        
        # Add AI response header
        Append-TextSmooth -Text ('AI: ' + [Environment]::NewLine) -Color ([System.Drawing.Color]::Cyan) -Bold $true
        
        $script:IsProcessing = $true
        $script:StopRequested = $false
        $script:TextBuffer = ''
        $script:SendBtn.Text = 'Stop'
        $script:SendBtn.BackColor = [System.Drawing.Color]::FromArgb(200, 50, 50)
        $script:InputBox.Enabled = $false
        
        $messagesForApi = @()
        foreach ($m in $conv.messages) {
            $messagesForApi += @{ role = $m.role; content = $m.content }
        }
        
        $requestBody = @{
            model = 'local-model'
            messages = $messagesForApi
            stream = $true
            max_tokens = $script:Config.MaxTokens
            temperature = $script:Config.Temperature
        } | ConvertTo-Json -Depth 10 -Compress
        
        $fullResponse = ''
        $displayBuffer = ''
        $inThinking = $false
        $charCount = 0
        
        try {
            $request = [System.Net.HttpWebRequest]::Create($apiUrl)
            $request.Method = 'POST'
            $request.ContentType = 'application/json'
            $request.Timeout = 300000
            $request.ReadWriteTimeout = 300000
            
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($requestBody)
            $request.ContentLength = $bodyBytes.Length
            
            $requestStream = $request.GetRequestStream()
            $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
            $requestStream.Close()
            
            $response = $request.GetResponse()
            $responseStream = $response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($responseStream)
            
            while (-not $reader.EndOfStream -and -not $script:StopRequested) {
                $line = $reader.ReadLine()
                
                if ($line -and $line.StartsWith('data: ')) {
                    $jsonData = $line.Substring(6)
                    
                    if ($jsonData -eq '[DONE]') { break }
                    
                    try {
                        $parsed = $jsonData | ConvertFrom-Json
                        
                        if ($parsed.choices -and $parsed.choices.Count -gt 0) {
                            $delta = $parsed.choices[0].delta
                            if ($delta -and $delta.content) {
                                $chunk = $delta.content
                                $fullResponse = $fullResponse + $chunk
                                
                                # Handle thinking tags
                                if ($chunk -match '<think>|<thinking>') { $inThinking = $true }
                                elseif ($chunk -match '</think>|</thinking>') { 
                                    $inThinking = $false 
                                    $chunk = ''
                                }
                                
                                if (-not $inThinking) {
                                    $cleanChunk = $chunk -replace '</?think>|</?thinking>', ''
                                    if ($cleanChunk -ne '') {
                                        $displayBuffer = $displayBuffer + $cleanChunk
                                        $charCount = $charCount + $cleanChunk.Length
                                        
                                        # Batch updates: flush buffer every 5 chars or on newline
                                        if ($charCount -ge 5 -or $cleanChunk.Contains([Environment]::NewLine)) {
                                            Append-TextSmooth -Text $displayBuffer -Color ([System.Drawing.Color]::FromArgb(220, 220, 220))
                                            $displayBuffer = ''
                                            $charCount = 0
                                            
                                            # Smooth scroll every 100ms max
                                            $now = [DateTime]::Now
                                            if (($now - $script:LastScrollTime).TotalMilliseconds -gt 100) {
                                                Scroll-ToBottom
                                                $script:LastScrollTime = $now
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } catch { }
                }
                
                [System.Windows.Forms.Application]::DoEvents()
            }
            
            # Flush remaining buffer
            if ($displayBuffer -ne '') {
                Append-TextSmooth -Text $displayBuffer -Color ([System.Drawing.Color]::FromArgb(220, 220, 220))
            }
            
            $reader.Close()
            $responseStream.Close()
            $response.Close()
            
        } catch {
            $errorMsg = 'Error: ' + $_.Exception.Message
            Append-TextSmooth -Text $errorMsg -Color ([System.Drawing.Color]::Red)
            $fullResponse = $errorMsg
        }
        
        if ($script:StopRequested) {
            Append-TextSmooth -Text ([Environment]::NewLine + '[Stopped]') -Color ([System.Drawing.Color]::Orange)
            $fullResponse = $fullResponse + ' [Stopped]'
        }
        
        Append-TextSmooth -Text ([Environment]::NewLine + [Environment]::NewLine) -Color ([System.Drawing.Color]::White)
        Scroll-ToBottom
        
        # Clean and save response
        $cleanResponse = $fullResponse -replace '<think>[\s\S]*?</think>', '' -replace '<thinking>[\s\S]*?</thinking>', ''
        $cleanResponse = $cleanResponse.Trim()
        
        $aiMsg = @{ role = 'assistant'; content = $cleanResponse }
        $conv.messages = @($conv.messages) + @($aiMsg)
        
        Save-ChatHistory
        
        $script:IsProcessing = $false
        $script:StopRequested = $false
        $script:SendBtn.Text = 'Send'
        $script:SendBtn.BackColor = [System.Drawing.Color]::FromArgb(35, 134, 54)
        $script:InputBox.Enabled = $true
        $script:InputBox.Focus()
    }
    
    # Create main form
    $script:Form = New-Object System.Windows.Forms.Form
    $script:Form.Text = 'xsukax AI Chat - Smooth Streaming - Port ' + $script:Config.ServerPort
    $script:Form.Size = New-Object System.Drawing.Size(1050, 720)
    $script:Form.StartPosition = 'CenterScreen'
    $script:Form.BackColor = [System.Drawing.Color]::FromArgb(22, 27, 34)
    $script:Form.ForeColor = [System.Drawing.Color]::White
    $script:Form.MinimumSize = New-Object System.Drawing.Size(800, 500)
    
    # Sidebar
    $sidePanel = New-Object System.Windows.Forms.Panel
    $sidePanel.Dock = 'Left'
    $sidePanel.Width = 250
    $sidePanel.BackColor = [System.Drawing.Color]::FromArgb(30, 35, 42)
    $script:Form.Controls.Add($sidePanel)
    
    $newChatBtn = New-Object System.Windows.Forms.Button
    $newChatBtn.Text = '+ New Chat'
    $newChatBtn.Location = New-Object System.Drawing.Point(10, 15)
    $newChatBtn.Size = New-Object System.Drawing.Size(230, 38)
    $newChatBtn.BackColor = [System.Drawing.Color]::FromArgb(35, 134, 54)
    $newChatBtn.ForeColor = [System.Drawing.Color]::White
    $newChatBtn.FlatStyle = 'Flat'
    $newChatBtn.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $newChatBtn.Add_Click({ New-Conversation })
    $sidePanel.Controls.Add($newChatBtn)
    
    $script:ListBox = New-Object System.Windows.Forms.ListBox
    $script:ListBox.Location = New-Object System.Drawing.Point(10, 65)
    $script:ListBox.Size = New-Object System.Drawing.Size(230, 380)
    $script:ListBox.BackColor = [System.Drawing.Color]::FromArgb(22, 27, 34)
    $script:ListBox.ForeColor = [System.Drawing.Color]::White
    $script:ListBox.BorderStyle = 'None'
    $script:ListBox.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $script:ListBox.Add_SelectedIndexChanged({
        if (-not $script:IsProcessing -and $script:ListBox.SelectedIndex -ge 0 -and $script:ListBox.SelectedIndex -lt $script:Conversations.Count) {
            $script:CurrentConvId = $script:Conversations[$script:ListBox.SelectedIndex].id
            Update-ChatDisplay
        }
    })
    $sidePanel.Controls.Add($script:ListBox)
    
    $renameBtn = New-Object System.Windows.Forms.Button
    $renameBtn.Text = 'Rename'
    $renameBtn.Location = New-Object System.Drawing.Point(10, 455)
    $renameBtn.Size = New-Object System.Drawing.Size(72, 30)
    $renameBtn.BackColor = [System.Drawing.Color]::FromArgb(50, 55, 65)
    $renameBtn.ForeColor = [System.Drawing.Color]::White
    $renameBtn.FlatStyle = 'Flat'
    $renameBtn.Add_Click({
        $conv = Get-CurrentConversation
        if ($conv -and -not $script:IsProcessing) {
            $newName = [Microsoft.VisualBasic.Interaction]::InputBox('Enter new name:', 'Rename', $conv.title)
            if ($newName -and $newName.Trim() -ne '') {
                $conv.title = $newName.Trim()
                Save-ChatHistory
                Update-ConversationList
                $script:TitleLabel.Text = $conv.title
            }
        }
    })
    $sidePanel.Controls.Add($renameBtn)
    
    $exportBtn = New-Object System.Windows.Forms.Button
    $exportBtn.Text = 'Export'
    $exportBtn.Location = New-Object System.Drawing.Point(88, 455)
    $exportBtn.Size = New-Object System.Drawing.Size(72, 30)
    $exportBtn.BackColor = [System.Drawing.Color]::FromArgb(31, 111, 235)
    $exportBtn.ForeColor = [System.Drawing.Color]::White
    $exportBtn.FlatStyle = 'Flat'
    $exportBtn.Add_Click({
        $conv = Get-CurrentConversation
        if ($conv -and -not $script:IsProcessing) {
            $dlg = New-Object System.Windows.Forms.SaveFileDialog
            $dlg.Filter = 'Text File (*.txt)|*.txt|JSON File (*.json)|*.json'
            $dlg.FileName = $conv.title -replace '[^a-zA-Z0-9]', '_'
            if ($dlg.ShowDialog() -eq 'OK') {
                if ($dlg.FileName -like '*.json') {
                    $conv | ConvertTo-Json -Depth 10 | Set-Content $dlg.FileName -Encoding UTF8
                } else {
                    $txt = $conv.title + "`r`n" + ('=' * $conv.title.Length) + "`r`n`r`n"
                    foreach ($m in $conv.messages) { $txt += $m.role.ToUpper() + ':' + "`r`n" + $m.content + "`r`n`r`n" }
                    $txt | Set-Content $dlg.FileName -Encoding UTF8
                }
                [System.Windows.Forms.MessageBox]::Show('Exported!', 'Success', 'OK', 'Information')
            }
        }
    })
    $sidePanel.Controls.Add($exportBtn)
    
    $deleteBtn = New-Object System.Windows.Forms.Button
    $deleteBtn.Text = 'Delete'
    $deleteBtn.Location = New-Object System.Drawing.Point(166, 455)
    $deleteBtn.Size = New-Object System.Drawing.Size(72, 30)
    $deleteBtn.BackColor = [System.Drawing.Color]::FromArgb(200, 50, 50)
    $deleteBtn.ForeColor = [System.Drawing.Color]::White
    $deleteBtn.FlatStyle = 'Flat'
    $deleteBtn.Add_Click({
        if ($script:CurrentConvId -and -not $script:IsProcessing) {
            $result = [System.Windows.Forms.MessageBox]::Show('Delete this conversation?', 'Confirm', 'YesNo', 'Question')
            if ($result -eq 'Yes') {
                $script:Conversations = @($script:Conversations | Where-Object { $_.id -ne $script:CurrentConvId })
                $script:CurrentConvId = if ($script:Conversations.Count -gt 0) { $script:Conversations[0].id } else { $null }
                Save-ChatHistory
                Update-ConversationList
                Update-ChatDisplay
            }
        }
    })
    $sidePanel.Controls.Add($deleteBtn)
    
    $copyBtn = New-Object System.Windows.Forms.Button
    $copyBtn.Text = 'Copy Chat'
    $copyBtn.Location = New-Object System.Drawing.Point(10, 495)
    $copyBtn.Size = New-Object System.Drawing.Size(228, 30)
    $copyBtn.BackColor = [System.Drawing.Color]::FromArgb(50, 55, 65)
    $copyBtn.ForeColor = [System.Drawing.Color]::White
    $copyBtn.FlatStyle = 'Flat'
    $copyBtn.Add_Click({
        $conv = Get-CurrentConversation
        if ($conv -and $conv.messages.Count -gt 0) {
            $txt = ''
            foreach ($m in $conv.messages) { $txt += $m.role.ToUpper() + ':' + "`r`n" + $m.content + "`r`n`r`n" }
            [System.Windows.Forms.Clipboard]::SetText($txt)
            [System.Windows.Forms.MessageBox]::Show('Chat copied to clipboard!', 'Copied', 'OK', 'Information')
        }
    })
    $sidePanel.Controls.Add($copyBtn)
    
    $infoLabel = New-Object System.Windows.Forms.Label
    $infoLabel.Text = 'Model: ' + (Split-Path $modelPath -Leaf)
    $infoLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $infoLabel.ForeColor = [System.Drawing.Color]::Gray
    $infoLabel.Location = New-Object System.Drawing.Point(10, 540)
    $infoLabel.Size = New-Object System.Drawing.Size(228, 35)
    $sidePanel.Controls.Add($infoLabel)
    
    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = 'Server: Port ' + $script:Config.ServerPort + ' | Streaming ON'
    $statusLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(35, 134, 54)
    $statusLabel.Location = New-Object System.Drawing.Point(10, 580)
    $statusLabel.AutoSize = $true
    $sidePanel.Controls.Add($statusLabel)
    
    # Main panel
    $mainPanel = New-Object System.Windows.Forms.Panel
    $mainPanel.Dock = 'Fill'
    $mainPanel.BackColor = [System.Drawing.Color]::FromArgb(22, 27, 34)
    $mainPanel.Padding = New-Object System.Windows.Forms.Padding(10)
    $script:Form.Controls.Add($mainPanel)
    $mainPanel.BringToFront()
    
    $script:TitleLabel = New-Object System.Windows.Forms.Label
    $script:TitleLabel.Text = 'xsukax AI Chat GUI'
    $script:TitleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $script:TitleLabel.ForeColor = [System.Drawing.Color]::White
    $script:TitleLabel.Location = New-Object System.Drawing.Point(15, 8)
    $script:TitleLabel.AutoSize = $true
    $mainPanel.Controls.Add($script:TitleLabel)
    
    $script:ChatBox = New-Object System.Windows.Forms.RichTextBox
    $script:ChatBox.Location = New-Object System.Drawing.Point(10, 45)
    $script:ChatBox.Size = New-Object System.Drawing.Size(($mainPanel.Width - 30), ($mainPanel.Height - 155))
    $script:ChatBox.BackColor = [System.Drawing.Color]::FromArgb(13, 17, 23)
    $script:ChatBox.ForeColor = [System.Drawing.Color]::White
    $script:ChatBox.Font = New-Object System.Drawing.Font('Consolas', 11)
    $script:ChatBox.ReadOnly = $true
    $script:ChatBox.BorderStyle = 'None'
    $script:ChatBox.ScrollBars = 'Vertical'
    $script:ChatBox.Anchor = 'Top, Bottom, Left, Right'
    $script:ChatBox.Add_MouseDown({
        param($s, $e)
        if ($e.Button -eq 'Right' -and $script:ChatBox.SelectedText.Length -gt 0) {
            [System.Windows.Forms.Clipboard]::SetText($script:ChatBox.SelectedText)
            [System.Windows.Forms.MessageBox]::Show('Copied!', 'Copy', 'OK', 'Information')
        }
    })
    $mainPanel.Controls.Add($script:ChatBox)
    
    $script:InputBox = New-Object System.Windows.Forms.TextBox
    $script:InputBox.Location = New-Object System.Drawing.Point(10, ($mainPanel.Height - 100))
    $script:InputBox.Size = New-Object System.Drawing.Size(($mainPanel.Width - 115), 80)
    $script:InputBox.BackColor = [System.Drawing.Color]::FromArgb(40, 44, 52)
    $script:InputBox.ForeColor = [System.Drawing.Color]::White
    $script:InputBox.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    $script:InputBox.Multiline = $true
    $script:InputBox.ScrollBars = 'Vertical'
    $script:InputBox.Anchor = 'Bottom, Left, Right'
    $script:InputBox.Add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq 'Enter' -and -not $e.Shift) {
            $e.SuppressKeyPress = $true
            Send-StreamingMessage
        }
    })
    $mainPanel.Controls.Add($script:InputBox)
    
    $script:SendBtn = New-Object System.Windows.Forms.Button
    $script:SendBtn.Text = 'Send'
    $script:SendBtn.Location = New-Object System.Drawing.Point(($mainPanel.Width - 95), ($mainPanel.Height - 100))
    $script:SendBtn.Size = New-Object System.Drawing.Size(75, 80)
    $script:SendBtn.BackColor = [System.Drawing.Color]::FromArgb(35, 134, 54)
    $script:SendBtn.ForeColor = [System.Drawing.Color]::White
    $script:SendBtn.FlatStyle = 'Flat'
    $script:SendBtn.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $script:SendBtn.Anchor = 'Bottom, Right'
    $script:SendBtn.Add_Click({ Send-StreamingMessage })
    $mainPanel.Controls.Add($script:SendBtn)
    
    $script:Form.Add_FormClosing({
        $script:StopRequested = $true
        Stop-ServerProcess -Port $script:Config.ServerPort
    })
    
    Update-ConversationList
    Update-ChatDisplay
    $script:InputBox.Focus()
    
    [void]$script:Form.ShowDialog()
    
    Stop-ServerProcess -Port $script:Config.ServerPort
}

function Show-SettingsMenu {
    while ($true) {
        Clear-Host
        Write-Logo
        Write-MenuHeader 'SETTINGS'
        Write-Host '      Current Configuration:' -ForegroundColor White
        Write-Host ''
        Write-Host ('      [1] Context Size:    ' + $script:Config.ContextSize) -ForegroundColor Cyan
        Write-Host ('      [2] Temperature:     ' + $script:Config.Temperature) -ForegroundColor Cyan
        Write-Host ('      [3] Max Tokens:      ' + $script:Config.MaxTokens) -ForegroundColor Cyan
        $gpuText = if ($script:Config.GpuLayers -eq 0) { 'CPU Only' } elseif ($script:Config.GpuLayers -eq -1) { 'Auto' } else { $script:Config.GpuLayers.ToString() + ' layers' }
        Write-Host ('      [4] GPU Layers:      ' + $gpuText) -ForegroundColor Cyan
        Write-Host ('      [5] Server Port:     ' + $script:Config.ServerPort) -ForegroundColor Cyan
        $threadText = if ($script:Config.Threads -eq 0) { 'Auto (' + [Environment]::ProcessorCount + ')' } else { $script:Config.Threads.ToString() }
        Write-Host ('      [6] CPU Threads:     ' + $threadText) -ForegroundColor Cyan
        Write-Host ''
        Write-Separator
        Write-MenuItem 'R' 'Reset to defaults'
        Write-MenuItem '0' 'Back to main menu'
        
        $choice = Read-MenuChoice 'Select setting'
        
        switch ($choice.ToUpper()) {
            '1' { $val = Read-Host '  Enter context size (512-131072)'; if ($val -match '^\d+$') { $iv = [int]$val; if ($iv -ge 512 -and $iv -le 131072) { $script:Config.ContextSize = $iv; Save-Config } } }
            '2' { $val = Read-Host '  Enter temperature (0.0-2.0)'; if ($val -match '^\d*\.?\d+$') { $dv = [double]$val; if ($dv -ge 0 -and $dv -le 2) { $script:Config.Temperature = $dv; Save-Config } } }
            '3' { $val = Read-Host '  Enter max tokens (1-32768)'; if ($val -match '^\d+$') { $iv = [int]$val; if ($iv -ge 1 -and $iv -le 32768) { $script:Config.MaxTokens = $iv; Save-Config } } }
            '4' { Write-Dim '0=CPU, -1=Auto GPU, N=layers'; $val = Read-Host '  GPU layers'; if ($val -match '^-?\d+$') { $script:Config.GpuLayers = [int]$val; Save-Config } }
            '5' { $val = Read-Host '  Enter port (1024-65535)'; if ($val -match '^\d+$') { $iv = [int]$val; if ($iv -ge 1024 -and $iv -le 65535) { $script:Config.ServerPort = $iv; Save-Config } } }
            '6' { $val = Read-Host '  CPU threads (0=auto)'; if ($val -match '^\d+$') { $script:Config.Threads = [int]$val; Save-Config } }
            'R' { $script:Config = $script:DefaultConfig.Clone(); Save-Config; Write-Success 'Reset done'; Start-Sleep -Seconds 1 }
            '0' { return }
            '' { return }
        }
    }
}

function Show-ToolsMenu {
    while ($true) {
        Clear-Host
        Write-Logo
        Write-MenuHeader 'TOOLS'
        
        $llamaExe = Get-LlamaCli
        $serverExe = Get-LlamaServer
        $models = Get-Models
        
        Write-Host '      Status:' -ForegroundColor White
        Write-Host ''
        if ($llamaExe) { Write-Host '      llama-cli:    OK' -ForegroundColor Green } else { Write-Host '      llama-cli:    Missing' -ForegroundColor Red }
        if ($serverExe) { Write-Host '      llama-server: OK' -ForegroundColor Green } else { Write-Host '      llama-server: Missing' -ForegroundColor Red }
        Write-Host ('      Models:       ' + $models.Count) -ForegroundColor Cyan
        Write-Host ''
        Write-Separator
        Write-MenuItem '1' 'Reinstall llama.cpp'
        Write-MenuItem '2' 'Open models folder'
        Write-MenuItem '3' 'Open llama folder'
        Write-MenuItem '0' 'Back'
        
        $choice = Read-MenuChoice 'Select'
        
        switch ($choice) {
            '1' { if (Test-Path $script:LlamaDir) { Remove-Item $script:LlamaDir -Recurse -Force -ErrorAction SilentlyContinue }; Initialize-Folders; Install-LlamaCpp }
            '2' { Initialize-Folders; Start-Process 'explorer.exe' $script:ModelsDir }
            '3' { Initialize-Folders; Start-Process 'explorer.exe' $script:LlamaDir }
            '0' { return }
            '' { return }
        }
    }
}

function Show-HelpScreen {
    Clear-Host
    Write-Logo
    Write-MenuHeader 'HELP'
    
    Write-Host '      QUICK START:' -ForegroundColor Yellow
    Write-Dim '1. Download GGUF model from HuggingFace'
    Write-Dim '2. Place in ggufs folder'
    Write-Dim '3. Select option 4 for GUI'
    Write-Host ''
    Write-Host '      SMOOTH STREAMING:' -ForegroundColor Yellow
    Write-Dim '- Text appears smoothly without flicker'
    Write-Dim '- Uses Win32 API for optimal scrolling'
    Write-Dim '- Click Stop to cancel generation'
    Write-Dim '- Right-click chat to copy selection'
    Write-Host ''
    Write-Host '      MODELS:' -ForegroundColor Yellow
    Write-Dim 'https://huggingface.co/models?library=gguf'
    
    Pause-Continue
}

function Show-MainMenu {
    while ($true) {
        Clear-Host
        Write-Logo
        Write-StatusBar
        Write-MenuHeader 'MAIN MENU'
        
        Write-MenuItem '1' 'Interactive Chat' 'console'
        Write-MenuItem '2' 'Single Prompt' 'one-shot'
        Write-MenuItem '3' 'API Server' 'standalone'
        Write-MenuItem '4' 'GUI Chat' 'smooth streaming'
        Write-Host ''
        Write-Separator
        Write-MenuItem 'M' 'Select Model'
        Write-MenuItem 'S' 'Settings'
        Write-MenuItem 'T' 'Tools'
        Write-MenuItem 'H' 'Help'
        Write-MenuItem 'Q' 'Quit'
        
        $choice = Read-MenuChoice 'Select'
        
        switch ($choice.ToUpper()) {
            '1' { $m = if ($script:Config.LastModel -and (Test-Path $script:Config.LastModel -ErrorAction SilentlyContinue)) { $script:Config.LastModel } else { Show-ModelSelector }; if ($m) { Start-InteractiveMode -ModelPath $m } }
            '2' { $m = if ($script:Config.LastModel -and (Test-Path $script:Config.LastModel -ErrorAction SilentlyContinue)) { $script:Config.LastModel } else { Show-ModelSelector }; if ($m) { Start-SinglePromptMode -ModelPath $m } }
            '3' { $m = if ($script:Config.LastModel -and (Test-Path $script:Config.LastModel -ErrorAction SilentlyContinue)) { $script:Config.LastModel } else { Show-ModelSelector }; if ($m) { Start-ServerMode -ModelPath $m } }
            '4' { Start-GuiChatClient }
            'M' { $null = Show-ModelSelector }
            'S' { Show-SettingsMenu }
            'T' { Show-ToolsMenu }
            'H' { Show-HelpScreen }
            'Q' { Clear-Host; Write-Host ''; Write-Host '  Thank you for using xsukax GGUF Runner!' -ForegroundColor Cyan; Write-Host ''; return }
        }
    }
}

function Main {
    if ($Help) {
        Write-Logo
        Write-Host '  USAGE: powershell -ExecutionPolicy Bypass -File .\xsukax-gguf-runner.ps1' -ForegroundColor Yellow
        Write-Host '  OPTIONS: -Help' -ForegroundColor Yellow
        Write-Host ''
        return
    }
    
    Load-Config
    Initialize-Folders
    $null = Ensure-LlamaCpp
    Show-MainMenu
}

try { Main }
catch {
    Write-Host ''
    Write-Host ('  ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ''
    exit 1
}
