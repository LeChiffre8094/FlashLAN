@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
set "LAN_SHARE_ROOT=%~dp0"
set "LAN_LAUNCHER=%~f0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:LAN_LAUNCHER, [System.Text.Encoding]::UTF8); & ([scriptblock]::Create(($s -split '(?m)^# POWERSHELL_BEGIN\r?$',2)[1]))"

if %errorlevel% neq 0 (
    echo.
    echo ========================================================
    echo  [提示] 运行遇到问题或已退出 (退出码: %errorlevel%)
    echo  如果提示找不到 caddy.exe，请将 caddy.exe 放到此 BAT 旁边。
    echo ========================================================
    pause
)
exit /b %errorlevel%
# POWERSHELL_BEGIN
$ErrorActionPreference = 'Stop'
try {
    $shareRoot = [IO.Path]::GetFullPath($env:LAN_SHARE_ROOT)
    if ($shareRoot.Length -gt [IO.Path]::GetPathRoot($shareRoot).Length) { $shareRoot = $shareRoot.TrimEnd('\') }
    
    # 查找 caddy.exe 的多种可能位置
    $candidatePaths = @(
        (Join-Path $shareRoot 'caddy.exe'),
        (Join-Path $shareRoot '..\caddy.exe'),
        $env:CADDY_EXE,
        'C:\Caddy\caddy.exe',
        (Join-Path $env:LOCALAPPDATA 'Caddy\caddy.exe'),
        (Join-Path $env:USERPROFILE 'Downloads\caddy.exe')
    )
    $caddyPath = $candidatePaths | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
    if (-not $caddyPath) {
        $command = Get-Command caddy.exe -ErrorAction SilentlyContinue
        if ($command) { $caddyPath = $command.Source }
    }
    if (-not $caddyPath) {
        Write-Host ''
        Write-Host '========================================================' -ForegroundColor Yellow
        Write-Host ' 【提示】当前目录或系统中未找到 caddy.exe' -ForegroundColor Yellow
        Write-Host '========================================================' -ForegroundColor Yellow
        Write-Host ' 解决方法：'
        Write-Host ' 1. 如果你之前下载过 caddy.exe，请把它复制到这个 BAT 文件旁边，'
        Write-Host '    或者放到 C:\Caddy\caddy.exe（以后所有文件夹均可通用）。'
        Write-Host ' 2. 如果还没有 caddy.exe，请访问官方下载：https://caddyserver.com/download'
        Write-Host '========================================================' -ForegroundColor Yellow
        Write-Host ''
        Read-Host '按回车键关闭窗口'
        exit 1
    }
    
    function Test-FreePort([int] $number) {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Any, $number)
        try { $listener.Start(); return $true } catch { return $false } finally { $listener.Stop() }
    }
    
    $stateDirectory = Join-Path $env:LOCALAPPDATA 'FlashLAN'
    [IO.Directory]::CreateDirectory($stateDirectory) | Out-Null
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $key = [BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($shareRoot.ToLowerInvariant()))).Replace('-', '') }
    finally { $hasher.Dispose() }
    
    $portFile = Join-Path $stateDirectory ($key + '.port')
    $portNumber = 8080
    $savedPort = 0
    if ((Test-Path -LiteralPath $portFile) -and [int]::TryParse([IO.File]::ReadAllText($portFile).Trim(), [ref]$savedPort) -and $savedPort -ge 1024 -and $savedPort -le 65535) { $portNumber = $savedPort }
    if (-not (Test-FreePort $portNumber)) {
        $previous = $portNumber
        $portNumber = 0
        foreach ($candidate in 8080..8199) { if (Test-FreePort $candidate) { $portNumber = $candidate; break } }
        if ($portNumber -eq 0) { throw '8080–8199 端口均被占用，请关闭不需要的共享窗口。' }
        Write-Host "端口 $previous 已占用，本目录改用 $portNumber。请在 App 中使用下面的新地址。" -ForegroundColor Yellow
    }
    [IO.File]::WriteAllText($portFile, [string]$portNumber)
    
    Write-Host ''
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host '        ⚡ 闪传 FlashLAN · 极速局域网文件服务      ' -ForegroundColor Cyan
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host "共享目录：$shareRoot"
    Write-Host "服务端口：$portNumber"
    Write-Host ''
    Write-Host '请在手机端【闪传 LAN】添加以下直连地址：' -ForegroundColor Green
    try {
        $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -ExpandProperty IPAddress -Unique)
    } catch { $addresses = @() }
    foreach ($ip in $addresses) {
        Write-Host ("  ➜  http://{0}:{1}" -f $ip, $portNumber) -ForegroundColor Green
    }
    if ($addresses.Count -eq 0) { Write-Host '未找到局域网 IPv4 地址，请检查 Wi-Fi 连接。' -ForegroundColor Yellow }
    Write-Host ''
    Write-Host '传输模式：直连零拷贝高性能模式（满速 50–100 MB/s 无损传输）' -ForegroundColor DarkCyan
    Write-Host '提示：保持本窗口开启以维持共享服务；按 Ctrl+C 停止。' -ForegroundColor Gray
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host ''

    $fileHandler = @{
        handler = 'file_server'
        root = $shareRoot
        browse = @{}
        index_names = @()
        hide = @('Start-FlashLAN.bat'; 'Start-LANDownloader.bat'; 'caddy.exe')
    }
    $config = @{
        admin = @{ disabled = $true }
        apps = @{ http = @{ servers = @{
            public = @{
                listen = @((':' + $portNumber))
                routes = @(
                    @{ handle = @($fileHandler) }
                )
            }
        } } }
    }
    $configPath = Join-Path $stateDirectory ($key + '-direct.json')
    [IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 25), [Text.UTF8Encoding]::new($false))
    & $caddyPath validate --config $configPath
    if ($LASTEXITCODE -ne 0) { throw 'Caddy 配置验证失败，请联系开发者。' }
    & $caddyPath run --config $configPath
    if ($LASTEXITCODE -ne 0) { throw "Caddy 启动失败（退出码 $LASTEXITCODE），请检查端口和目录。" }
} catch {
    Write-Host ''
    Write-Host '========================================================' -ForegroundColor Red
    Write-Host ('运行异常：' + $_.Exception.Message) -ForegroundColor Red
    Write-Host '========================================================' -ForegroundColor Red
    Write-Host ''
    Read-Host '按回车键关闭窗口'
    exit 1
}
