<#
.SYNOPSIS
    xsukax CLI GGUF Runner - Complete AI Model Interface for Windows
    
.DESCRIPTION
    Menu-driven tool that auto-downloads llama.cpp, manages GGUF models,
    and provides interactive chat, single-prompt, and API server modes.
    
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\xsukax-gguf-runner.ps1
    
.NOTES
    Author: xsukax
    License: GPL v3.0
#>

[CmdletBinding()]
param(
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$script:Version = '2.0.0'
$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:LlamaDir = Join-Path $script:ScriptDir 'llama'
$script:ModelsDir = Join-Path $script:ScriptDir 'ggufs'
$script:ConfigFile = Join-Path $script:ScriptDir 'gguf-config.json'
$script:LlamaVersion = 'b7839'

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

function Write-Color {
    param(
        [string]$Text,
        [string]$Color = 'White',
        [switch]$NoNewline
    )
    if ($NoNewline) {
        Write-Host $Text -ForegroundColor $Color -NoNewline
    }
    else {
        Write-Host $Text -ForegroundColor $Color
    }
}

function Write-Success {
    param([string]$Msg)
    Write-Host ('  [OK] ' + $Msg) -ForegroundColor Green
}

function Write-Err {
    param([string]$Msg)
    Write-Host ('  [ERROR] ' + $Msg) -ForegroundColor Red
}

function Write-Warn {
    param([string]$Msg)
    Write-Host ('  [!] ' + $Msg) -ForegroundColor Yellow
}

function Write-Inf {
    param([string]$Msg)
    Write-Host ('  [i] ' + $Msg) -ForegroundColor Cyan
}

function Write-Dim {
    param([string]$Msg)
    Write-Host ('      ' + $Msg) -ForegroundColor DarkGray
}

function Write-Logo {
    Write-Host ''
    Write-Host '    =================================================================' -ForegroundColor Cyan
    Write-Host '    |                                                               |' -ForegroundColor Cyan
    Write-Host '    |    X   X  SSSS  U   U  K   K   AAA   X   X                    |' -ForegroundColor Cyan
    Write-Host '    |     X X  S      U   U  K  K   A   A   X X                     |' -ForegroundColor Cyan
    Write-Host '    |      X    SSS   U   U  KKK    AAAAA    X                      |' -ForegroundColor Cyan
    Write-Host '    |     X X      S  U   U  K  K   A   A   X X                     |' -ForegroundColor Cyan
    Write-Host '    |    X   X  SSSS   UUU   K   K  A   A  X   X                    |' -ForegroundColor Cyan
    Write-Host '    |                                                               |' -ForegroundColor Cyan
    Write-Host '    |               CLI GGUF Runner v2.0.0                          |' -ForegroundColor White
    Write-Host '    |               Local AI Model Interface                        |' -ForegroundColor Gray
    Write-Host '    |                                                               |' -ForegroundColor Cyan
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
    param(
        [string]$Key,
        [string]$Text,
        [string]$Status = ''
    )
    $line = '      [' + $Key + '] ' + $Text
    if ($Status -ne '') {
        $line = $line + ' (' + $Status + ')'
    }
    Write-Host $line -ForegroundColor White
}

function Write-Separator {
    Write-Host '      --------------------------------------------------------' -ForegroundColor DarkGray
}

function Write-StatusBar {
    if ($script:Config.LastModel -and $script:Config.LastModel -ne '') {
        $modelStatus = Split-Path $script:Config.LastModel -Leaf
    }
    else {
        $modelStatus = 'None selected'
    }
    
    if ($script:Config.GpuLayers -eq 0) {
        $gpuStatus = 'CPU'
    }
    elseif ($script:Config.GpuLayers -eq -1) {
        $gpuStatus = 'GPU Auto'
    }
    else {
        $gpuStatus = 'GPU ' + $script:Config.GpuLayers + 'L'
    }
    
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
        }
        catch {
            $script:Config = $script:DefaultConfig.Clone()
        }
    }
}

function Save-Config {
    try {
        $script:Config | ConvertTo-Json | Set-Content $script:ConfigFile -Force
    }
    catch {
        # Ignore save errors
    }
}

function Initialize-Folders {
    if (-not (Test-Path $script:LlamaDir)) {
        New-Item -ItemType Directory -Path $script:LlamaDir -Force | Out-Null
    }
    if (-not (Test-Path $script:ModelsDir)) {
        New-Item -ItemType Directory -Path $script:ModelsDir -Force | Out-Null
    }
}

function Download-WithProgress {
    param(
        [string]$Url,
        [string]$OutputPath
    )
    
    try {
        $uri = New-Object System.Uri($Url)
        $request = [System.Net.HttpWebRequest]::Create($uri)
        $request.Timeout = 30000
        $response = $request.GetResponse()
        $totalBytes = $response.ContentLength
        $responseStream = $response.GetResponseStream()
        $fileStream = New-Object System.IO.FileStream($OutputPath, [System.IO.FileMode]::Create)
        $buffer = New-Object byte[] 65536
        $bytesRead = 0
        $totalRead = 0
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        
        while (($bytesRead = $responseStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fileStream.Write($buffer, 0, $bytesRead)
            $totalRead += $bytesRead
            
            if ($totalBytes -gt 0) {
                $percent = [math]::Round(($totalRead / $totalBytes) * 100, 0)
                $mbRead = [math]::Round($totalRead / 1MB, 1)
                $mbTotal = [math]::Round($totalBytes / 1MB, 1)
                $elapsed = $sw.Elapsed.TotalSeconds
                if ($elapsed -gt 0) {
                    $speed = [math]::Round($totalRead / 1MB / $elapsed, 1)
                }
                else {
                    $speed = 0
                }
                $statusText = $mbRead.ToString() + ' MB / ' + $mbTotal.ToString() + ' MB - ' + $speed.ToString() + ' MB/s'
                Write-Progress -Activity 'Downloading' -Status $statusText -PercentComplete $percent
            }
        }
        
        $fileStream.Close()
        $responseStream.Close()
        $response.Close()
        Write-Progress -Activity 'Downloading' -Completed
        
        return (Test-Path $OutputPath)
    }
    catch {
        Write-Err ('Download failed: ' + $_.Exception.Message)
        return $false
    }
}

function Extract-Archive {
    param(
        [string]$ZipPath,
        [string]$DestPath
    )
    try {
        Write-Inf 'Extracting archive...'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $DestPath)
        return $true
    }
    catch {
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
        if ($LASTEXITCODE -eq 0) {
            $hasCuda = $true
            Write-Success 'NVIDIA GPU detected'
        }
    }
    catch {
        Write-Inf 'No NVIDIA GPU - using CPU version'
    }
    
    if ($hasCuda) {
        $fileName = 'llama-' + $script:LlamaVersion + '-bin-win-cuda-12.4-x64.zip'
        $fileType = 'CUDA 12.4'
        $fileSize = '~210 MB'
    }
    else {
        $fileName = 'llama-' + $script:LlamaVersion + '-bin-win-cpu-x64.zip'
        $fileType = 'CPU'
        $fileSize = '~29 MB'
    }
    
    $downloadUrl = 'https://github.com/ggml-org/llama.cpp/releases/download/' + $script:LlamaVersion + '/' + $fileName
    $zipPath = Join-Path $script:ScriptDir $fileName
    
    Write-Host ''
    Write-Inf ('Version: ' + $script:LlamaVersion)
    Write-Inf ('Type: ' + $fileType)
    Write-Inf ('Size: ' + $fileSize)
    Write-Host ''
    
    Write-Inf 'Downloading llama.cpp...'
    if (-not (Download-WithProgress -Url $downloadUrl -OutputPath $zipPath)) {
        Write-Host ''
        Write-Err 'Download failed'
        Write-Warn 'Manual download:'
        Write-Dim ('https://github.com/ggml-org/llama.cpp/releases/tag/' + $script:LlamaVersion)
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
    
    $paths = @(
        (Join-Path $script:LlamaDir ($Name + '.exe')),
        (Join-Path $script:LlamaDir ('bin\' + $Name + '.exe')),
        (Join-Path $script:LlamaDir ('build\bin\Release\' + $Name + '.exe'))
    )
    
    foreach ($p in $paths) {
        if (Test-Path $p) {
            return $p
        }
    }
    
    $found = Get-ChildItem -Path $script:LlamaDir -Filter ($Name + '.exe') -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        return $found.FullName
    }
    
    return $null
}

function Get-LlamaCli {
    $names = @('llama-cli', 'main', 'llama')
    foreach ($n in $names) {
        $p = Find-Executable -Name $n
        if ($p) {
            return $p
        }
    }
    return $null
}

function Get-LlamaServer {
    $names = @('llama-server', 'server')
    foreach ($n in $names) {
        $p = Find-Executable -Name $n
        if ($p) {
            return $p
        }
    }
    return $null
}

function Ensure-LlamaCpp {
    $exe = Get-LlamaCli
    if (-not $exe) {
        Write-Warn 'llama.cpp not found - starting download...'
        Start-Sleep -Seconds 1
        if (-not (Install-LlamaCpp)) {
            return $null
        }
        $exe = Get-LlamaCli
    }
    return $exe
}

function Get-Models {
    if (-not (Test-Path $script:ModelsDir)) {
        return @()
    }
    return Get-ChildItem -Path $script:ModelsDir -Filter '*.gguf' -File | Sort-Object Name
}

function Get-ModelInfo {
    param([System.IO.FileInfo]$Model)
    
    $info = @{
        Name = $Model.Name
        SizeGB = [math]::Round($Model.Length / 1GB, 2)
        Quant = ''
        Params = ''
    }
    
    if ($Model.Name -match '(Q\d+_[KM0-9_]+)') {
        $info.Quant = $matches[1]
    }
    if ($Model.Name -match '(\d+[Bb])') {
        $info.Params = $matches[1].ToUpper()
    }
    
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
        Write-Host '      Download models from:' -ForegroundColor White
        Write-Dim 'https://huggingface.co/models?library=gguf'
        Write-Dim 'https://huggingface.co/TheBloke'
        Write-Host ''
        Write-Host '      Recommended starter models:' -ForegroundColor White
        Write-Dim '- TinyLlama-1.1B-Chat (Q4_K_M) - 0.6 GB'
        Write-Dim '- Phi-3-mini-4k (Q4_K_M) - 2.4 GB'
        Write-Dim '- Mistral-7B-Instruct (Q4_K_M) - 4.4 GB'
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
        if ($info.Params -ne '') {
            $details = $details + ' - ' + $info.Params
        }
        if ($info.Quant -ne '') {
            $details = $details + ' - ' + $info.Quant
        }
        Write-Host $details -ForegroundColor DarkGray
        Write-Host ''
    }
    
    Write-Separator
    Write-MenuItem '0' 'Back to main menu'
    
    $selection = Read-MenuChoice 'Select model'
    
    if ($selection -eq '0' -or $selection -eq '') {
        return $null
    }
    
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
    param(
        [string]$ModelPath,
        [switch]$IsServer
    )
    
    $argList = @('-m', $ModelPath, '-c', $script:Config.ContextSize)
    
    if (-not $IsServer) {
        $argList += '-n'
        $argList += $script:Config.MaxTokens
        $argList += '--temp'
        $argList += $script:Config.Temperature
    }
    
    if ($script:Config.Threads -gt 0) {
        $threads = $script:Config.Threads
    }
    else {
        $threads = [Environment]::ProcessorCount
    }
    $argList += '-t'
    $argList += $threads
    
    if ($script:Config.GpuLayers -ne 0) {
        if ($script:Config.GpuLayers -eq -1) {
            $layers = 999
        }
        else {
            $layers = $script:Config.GpuLayers
        }
        $argList += '-ngl'
        $argList += $layers
    }
    
    return $argList
}

function Start-InteractiveMode {
    param([string]$ModelPath)
    
    $exe = Ensure-LlamaCpp
    if (-not $exe) {
        Write-Err 'llama.cpp not available'
        Pause-Continue
        return
    }
    
    Clear-Host
    Write-Logo
    Write-MenuHeader 'INTERACTIVE CHAT'
    
    $modelName = Split-Path $ModelPath -Leaf
    Write-Inf ('Model: ' + $modelName)
    Write-Inf ('Context: ' + $script:Config.ContextSize + ' | Temp: ' + $script:Config.Temperature + ' | Max: ' + $script:Config.MaxTokens)
    
    if ($script:Config.GpuLayers -ne 0) {
        if ($script:Config.GpuLayers -eq -1) {
            $gpu = 'Auto'
        }
        else {
            $gpu = $script:Config.GpuLayers.ToString() + ' layers'
        }
        Write-Inf ('GPU: ' + $gpu)
    }
    
    Write-Host ''
    Write-Host '  =================================================================' -ForegroundColor DarkCyan
    Write-Host '   Type messages below. Press Ctrl+C to exit.' -ForegroundColor DarkGray
    Write-Host '  =================================================================' -ForegroundColor DarkCyan
    Write-Host ''
    
    $argList = Build-LlamaArgs -ModelPath $ModelPath
    $argList += '-cnv'
    
    & $exe @argList
}

function Start-SinglePromptMode {
    param([string]$ModelPath)
    
    $exe = Ensure-LlamaCpp
    if (-not $exe) {
        Write-Err 'llama.cpp not available'
        Pause-Continue
        return
    }
    
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
        if ($line -eq '' -and $lines.Count -gt 0) {
            break
        }
        if ($line -ne '') {
            $lines += $line
        }
    } while ($true)
    
    $prompt = $lines -join "`n"
    
    if ($prompt.Trim() -eq '') {
        Write-Warn 'No prompt entered'
        Pause-Continue
        return
    }
    
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
    if (-not $exe) {
        Write-Err 'llama-server not found'
        Write-Inf ('Server executable should be in: ' + $script:LlamaDir)
        Pause-Continue
        return
    }
    
    Clear-Host
    Write-Logo
    Write-MenuHeader 'API SERVER MODE'
    
    Write-Success 'Starting API server...'
    Write-Host ''
    Write-Inf ('Model: ' + (Split-Path $ModelPath -Leaf))
    Write-Inf ('Port: ' + $script:Config.ServerPort)
    Write-Inf ('Context: ' + $script:Config.ContextSize)
    Write-Host ''
    Write-Host '  --- Endpoints ---' -ForegroundColor Green
    Write-Host ('  Web UI:   http://localhost:' + $script:Config.ServerPort) -ForegroundColor White
    Write-Host ('  Chat API: http://localhost:' + $script:Config.ServerPort + '/v1/chat/completions') -ForegroundColor White
    Write-Host ''
    Write-Warn 'Press Ctrl+C to stop the server'
    Write-Host ''
    Write-Host '  =================================================================' -ForegroundColor DarkCyan
    Write-Host ''
    
    $argList = Build-LlamaArgs -ModelPath $ModelPath -IsServer
    $argList += '--port'
    $argList += $script:Config.ServerPort
    
    & $exe @argList
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
        
        if ($script:Config.GpuLayers -eq 0) {
            $gpuText = 'CPU Only'
        }
        elseif ($script:Config.GpuLayers -eq -1) {
            $gpuText = 'Auto (All)'
        }
        else {
            $gpuText = $script:Config.GpuLayers.ToString() + ' layers'
        }
        Write-Host ('      [4] GPU Layers:      ' + $gpuText) -ForegroundColor Cyan
        Write-Host ('      [5] Server Port:     ' + $script:Config.ServerPort) -ForegroundColor Cyan
        
        if ($script:Config.Threads -eq 0) {
            $threadText = 'Auto (' + [Environment]::ProcessorCount + ')'
        }
        else {
            $threadText = $script:Config.Threads.ToString()
        }
        Write-Host ('      [6] CPU Threads:     ' + $threadText) -ForegroundColor Cyan
        
        Write-Host ''
        Write-Separator
        Write-MenuItem 'R' 'Reset to defaults'
        Write-MenuItem '0' 'Back to main menu'
        
        $choice = Read-MenuChoice 'Select setting to change'
        
        switch ($choice) {
            '1' {
                $val = Read-Host '  Enter context size (512-131072)'
                if ($val -match '^\d+$') {
                    $intVal = [int]$val
                    if ($intVal -ge 512 -and $intVal -le 131072) {
                        $script:Config.ContextSize = $intVal
                        Save-Config
                    }
                }
            }
            '2' {
                $val = Read-Host '  Enter temperature (0.0-2.0)'
                if ($val -match '^\d+\.?\d*$') {
                    $dblVal = [double]$val
                    if ($dblVal -ge 0 -and $dblVal -le 2) {
                        $script:Config.Temperature = $dblVal
                        Save-Config
                    }
                }
            }
            '3' {
                $val = Read-Host '  Enter max tokens (1-32768)'
                if ($val -match '^\d+$') {
                    $intVal = [int]$val
                    if ($intVal -ge 1 -and $intVal -le 32768) {
                        $script:Config.MaxTokens = $intVal
                        Save-Config
                    }
                }
            }
            '4' {
                Write-Host ''
                Write-Dim '0 = CPU only, -1 = Auto (all layers), N = specific count'
                $val = Read-Host '  Enter GPU layers'
                if ($val -match '^-?\d+$') {
                    $script:Config.GpuLayers = [int]$val
                    Save-Config
                }
            }
            '5' {
                $val = Read-Host '  Enter server port (1024-65535)'
                if ($val -match '^\d+$') {
                    $intVal = [int]$val
                    if ($intVal -ge 1024 -and $intVal -le 65535) {
                        $script:Config.ServerPort = $intVal
                        Save-Config
                    }
                }
            }
            '6' {
                Write-Host ''
                Write-Dim '0 = Auto-detect, or specify number of threads'
                $val = Read-Host '  Enter CPU threads'
                if ($val -match '^\d+$') {
                    $script:Config.Threads = [int]$val
                    Save-Config
                }
            }
            'R' {
                $script:Config = $script:DefaultConfig.Clone()
                Save-Config
                Write-Success 'Settings reset to defaults'
                Start-Sleep -Seconds 1
            }
            'r' {
                $script:Config = $script:DefaultConfig.Clone()
                Save-Config
                Write-Success 'Settings reset to defaults'
                Start-Sleep -Seconds 1
            }
            '0' { return }
            '' { return }
        }
    }
}

function Show-ToolsMenu {
    while ($true) {
        Clear-Host
        Write-Logo
        Write-MenuHeader 'TOOLS AND INFO'
        
        $llamaExe = Get-LlamaCli
        $serverExe = Get-LlamaServer
        $models = Get-Models
        
        Write-Host '      System Status:' -ForegroundColor White
        Write-Host ''
        
        if ($llamaExe) {
            Write-Host '      llama-cli:    Installed' -ForegroundColor Green
        }
        else {
            Write-Host '      llama-cli:    Not found' -ForegroundColor Red
        }
        
        if ($serverExe) {
            Write-Host '      llama-server: Installed' -ForegroundColor Green
        }
        else {
            Write-Host '      llama-server: Not found' -ForegroundColor Red
        }
        
        Write-Host ('      Models:       ' + $models.Count + ' found') -ForegroundColor Cyan
        
        Write-Host ''
        Write-Separator
        Write-MenuItem '1' 'Reinstall llama.cpp'
        Write-MenuItem '2' 'Open models folder'
        Write-MenuItem '3' 'Open llama folder'
        Write-MenuItem '4' 'Show model download links'
        Write-MenuItem '0' 'Back to main menu'
        
        $choice = Read-MenuChoice 'Select option'
        
        switch ($choice) {
            '1' {
                if (Test-Path $script:LlamaDir) {
                    Remove-Item $script:LlamaDir -Recurse -Force -ErrorAction SilentlyContinue
                }
                Initialize-Folders
                Install-LlamaCpp
            }
            '2' {
                Initialize-Folders
                Start-Process 'explorer.exe' $script:ModelsDir
            }
            '3' {
                Initialize-Folders
                Start-Process 'explorer.exe' $script:LlamaDir
            }
            '4' {
                Write-Host ''
                Write-Host '      Model Sources:' -ForegroundColor White
                Write-Host ''
                Write-Dim 'HuggingFace GGUF Models:'
                Write-Dim 'https://huggingface.co/models?library=gguf'
                Write-Host ''
                Write-Dim 'TheBloke Quantized Models:'
                Write-Dim 'https://huggingface.co/TheBloke'
                Write-Host ''
                Write-Dim 'Bartowski Models:'
                Write-Dim 'https://huggingface.co/bartowski'
                Pause-Continue
            }
            '0' { return }
            '' { return }
        }
    }
}

function Show-HelpScreen {
    Clear-Host
    Write-Logo
    Write-MenuHeader 'HELP AND DOCUMENTATION'
    
    Write-Host '      QUICK START:' -ForegroundColor Yellow
    Write-Dim '1. Download a GGUF model from HuggingFace'
    Write-Dim '2. Place the .gguf file in the ggufs folder'
    Write-Dim '3. Select Interactive Chat from the main menu'
    Write-Host ''
    
    Write-Host '      FOLDERS:' -ForegroundColor Yellow
    Write-Dim 'llama/  - llama.cpp binaries (auto-downloaded)'
    Write-Dim 'ggufs/  - Your GGUF model files go here'
    Write-Host ''
    
    Write-Host '      GPU ACCELERATION:' -ForegroundColor Yellow
    Write-Dim 'Set GPU Layers in Settings:'
    Write-Dim '  0  = CPU only (default)'
    Write-Dim '  -1 = Auto (offload all layers to GPU)'
    Write-Dim '  N  = Specific number of layers'
    Write-Host ''
    
    Write-Host '      LOW MEMORY TIPS:' -ForegroundColor Yellow
    Write-Dim '- Use Q4_K_M or smaller quantizations'
    Write-Dim '- Reduce context size to 2048 or lower'
    Write-Dim '- Choose smaller models (1B-3B parameters)'
    Write-Host ''
    
    Write-Host '      COMMAND LINE:' -ForegroundColor Yellow
    Write-Dim 'powershell -ExecutionPolicy Bypass -File .\xsukax-gguf-runner.ps1 -Help'
    
    Pause-Continue
}

function Show-MainMenu {
    while ($true) {
        Clear-Host
        Write-Logo
        Write-StatusBar
        Write-MenuHeader 'MAIN MENU'
        
        Write-MenuItem '1' 'Interactive Chat' 'conversation mode'
        Write-MenuItem '2' 'Single Prompt' 'one-shot generation'
        Write-MenuItem '3' 'API Server' 'OpenAI-compatible endpoint'
        Write-Host ''
        Write-Separator
        Write-MenuItem 'M' 'Select Model'
        Write-MenuItem 'S' 'Settings'
        Write-MenuItem 'T' 'Tools and Info'
        Write-MenuItem 'H' 'Help'
        Write-MenuItem 'Q' 'Quit'
        
        $choice = Read-MenuChoice 'Select option'
        $choiceUpper = $choice.ToUpper()
        
        switch ($choiceUpper) {
            '1' {
                $model = $null
                if ($script:Config.LastModel -and $script:Config.LastModel -ne '' -and (Test-Path $script:Config.LastModel)) {
                    $model = $script:Config.LastModel
                }
                else {
                    $model = Show-ModelSelector
                }
                if ($model) {
                    Start-InteractiveMode -ModelPath $model
                }
            }
            '2' {
                $model = $null
                if ($script:Config.LastModel -and $script:Config.LastModel -ne '' -and (Test-Path $script:Config.LastModel)) {
                    $model = $script:Config.LastModel
                }
                else {
                    $model = Show-ModelSelector
                }
                if ($model) {
                    Start-SinglePromptMode -ModelPath $model
                }
            }
            '3' {
                $model = $null
                if ($script:Config.LastModel -and $script:Config.LastModel -ne '' -and (Test-Path $script:Config.LastModel)) {
                    $model = $script:Config.LastModel
                }
                else {
                    $model = Show-ModelSelector
                }
                if ($model) {
                    Start-ServerMode -ModelPath $model
                }
            }
            'M' {
                $null = Show-ModelSelector
            }
            'S' {
                Show-SettingsMenu
            }
            'T' {
                Show-ToolsMenu
            }
            'H' {
                Show-HelpScreen
            }
            'Q' {
                Clear-Host
                Write-Host ''
                Write-Host '  Thank you for using xsukax CLI GGUF Runner!' -ForegroundColor Cyan
                Write-Host ''
                return
            }
        }
    }
}

function Main {
    if ($Help) {
        Clear-Host
        Write-Logo
        Write-MenuHeader 'COMMAND LINE HELP'
        Write-Host '      USAGE:' -ForegroundColor Yellow
        Write-Dim 'powershell -ExecutionPolicy Bypass -File .\xsukax-gguf-runner.ps1'
        Write-Host ''
        Write-Host '      OPTIONS:' -ForegroundColor Yellow
        Write-Dim '-Help    Show this help message'
        Write-Host ''
        Write-Host '      All configuration is done through the interactive menu.' -ForegroundColor White
        Write-Host ''
        return
    }
    
    Load-Config
    Initialize-Folders
    
    $null = Ensure-LlamaCpp
    
    Show-MainMenu
}

try {
    Main
}
catch {
    Write-Host ''
    Write-Host '  FATAL ERROR: ' -ForegroundColor Red -NoNewline
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''
    exit 1
}