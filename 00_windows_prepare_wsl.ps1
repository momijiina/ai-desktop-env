# 00_windows_prepare_wsl.ps1
# Windows側で実行する準備スクリプト。
# 目的:
# - C:\Users\<User>\.wslconfig を作成/更新
# - WSL mirrored networking を有効化
# - LXD/Workshop の dnsmasq 競合回避用に ignoredPorts=53,67 を設定
# - 可能なら Windows Firewall で 6080/TCP を許可
#
# 実行例:
# PowerShellを開いて:
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\00_windows_prepare_wsl.ps1

$ErrorActionPreference = "Stop"

$wslConfigPath = Join-Path $HOME ".wslconfig"

if (Test-Path $wslConfigPath) {
    $backupPath = "$wslConfigPath.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $wslConfigPath $backupPath
    Write-Host "既存の .wslconfig をバックアップしました: $backupPath"
}

@"
[wsl2]
networkingMode=mirrored
dnsTunneling=true
autoProxy=true

[experimental]
ignoredPorts=53,67
"@ | Set-Content -Encoding ASCII $wslConfigPath

Write-Host ".wslconfig を作成/更新しました: $wslConfigPath"

# 管理者権限チェック
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

if ($isAdmin) {
    Write-Host "管理者権限あり: Firewall rule を追加します。"

    if (-not (Get-NetFirewallRule -DisplayName "WSL noVNC 6080" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule `
          -DisplayName "WSL noVNC 6080" `
          -Direction Inbound `
          -Action Allow `
          -Protocol TCP `
          -LocalPort 6080 | Out-Null
        Write-Host "Windows Firewall: 6080/TCP を許可しました。"
    } else {
        Write-Host "Windows Firewall: 既に 6080/TCP 許可ルールがあります。"
    }

    # Hyper-V firewall rule は環境によりコマンドが無いことがあるため、失敗しても続行。
    if (Get-Command New-NetFirewallHyperVRule -ErrorAction SilentlyContinue) {
        try {
            New-NetFirewallHyperVRule `
              -Name "WSL-noVNC-6080" `
              -DisplayName "WSL noVNC 6080" `
              -Direction Inbound `
              -VMCreatorId "{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}" `
              -Protocol TCP `
              -LocalPorts 6080 `
              -ErrorAction SilentlyContinue | Out-Null
            Write-Host "Hyper-V Firewall: 6080/TCP 許可を試行しました。"
        } catch {
            Write-Host "Hyper-V Firewall rule はスキップしました: $($_.Exception.Message)"
        }
    }
} else {
    Write-Host "管理者権限ではないため、Firewall rule はスキップしました。"
    Write-Host "別PCからアクセスする場合は、PowerShellを管理者で開いてこのスクリプトを再実行してください。"
}

Write-Host "WSLを停止します。"
wsl --shutdown

Write-Host ""
Write-Host "完了。Ubuntuを起動して、01_wsl_build_ai_desktop_env.sh を実行してください。"
