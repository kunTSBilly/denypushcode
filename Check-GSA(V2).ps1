param(  
    [ValidateSet("Boot","Auto")]  
    [string]$Mode = "Auto"  
)  
  
# ========== 可自訂參數 ==========  
$checkIP   = "10.1.254.254"   # 判斷內外網的目標 IP  
$pingTimes = 5                # Ping 次數  
  
$regPath = "HKCU:\Software\Microsoft\Global Secure Access Client"  
$regName = "IsPrivateAccessDisabledByUser"  
  
$gsaServices = @(  
    "GlobalSecureAccessEngineService",  
    "GlobalSecureAccessTunnelingService"  
)  
  
$maxWaitSeconds = 10          # 停止服務時最多等待秒數  
# ===============================  
  
function Stop-GsaServiceForce {  
    param(  
        [string]$ServiceName  
    )  
  
    Write-Output "---- 開始處理服務停止：$ServiceName ----"  
  
    try {  
        $svc = Get-Service -Name $ServiceName -ErrorAction Stop  
    } catch {  
        Write-Output "❗ Get-Service 失敗：$ServiceName"  
        Write-Output "   錯誤：$($_.Exception.Message)"  
        return  
    }  
  
    if ($svc.Status -eq 'Stopped') {  
        Write-Output "ℹ️ 服務已經是停止狀態：$ServiceName"  
        return  
    }  
  
    try {  
        Write-Output "🛑 嘗試停止服務（強制）：$ServiceName"  
        Stop-Service -Name $ServiceName -Force -ErrorAction Stop -WarningAction SilentlyContinue  
    } catch {  
        Write-Output "❗ Stop-Service 失敗：$ServiceName"  
        Write-Output "   錯誤：$($_.Exception.Message)"  
        return  
    }  
  
    # 等待一段時間確認狀態  
    $elapsed = 0  
    do {  
        Start-Sleep -Seconds 1  
        $elapsed++  
        try {  
            $svc.Refresh()  
        } catch {  
            Write-Output "❗ 服務狀態刷新失敗：$ServiceName - $($_.Exception.Message)"  
            break  
        }  
    } while ($svc.Status -ne 'Stopped' -and $elapsed -lt $maxWaitSeconds)  
  
    if ($svc.Status -eq 'Stopped') {  
        Write-Output "✅ 服務已停止：$ServiceName"  
    } else {  
        Write-Output "⚠️ 服務在 $maxWaitSeconds 秒內仍未停止：$ServiceName"  
    }  
  
    Write-Output "---- 完成處理服務停止：$ServiceName ----"  
}  
  
Write-Output "===== GSA 監控程式開始執行：$(Get-Date) Mode = $Mode ====="  
  
# 共同步驟：一律把 StartupType 設為 Manual（確保重開機不自動啟動）  
foreach ($svc in $gsaServices) {  
    try {  
        Set-Service -Name $svc -StartupType Manual -ErrorAction Stop  
        Write-Output "🔁 已將服務 $svc 的 StartupType 設為 Manual"  
    } catch {  
        Write-Output "❗ 設定 StartupType 失敗：$svc - $($_.Exception.Message)"  
    }  
}  
  
# ========== Mode: Boot ==========  
if ($Mode -eq "Boot") {  
    Write-Output "🧷 Boot 模式：開機 / 登入預設一律關閉 GSA（不判斷內外網）"  
  
    # 設定註冊碼：停用 GSA (1)  
    try {  
        Set-ItemProperty -Path $regPath -Name $regName -Value 1 -ErrorAction Stop  
        Write-Output "🔧 [Boot] 已設定 $regName = 1（停用 GSA）"  
    } catch {  
        Write-Output "❗ [Boot] 設定註冊碼失敗：$regPath\$regName - $($_.Exception.Message)"  
    }  
  
    # 停止 GSA 相關服務  
    Stop-GsaServiceForce -ServiceName "GlobalSecureAccessEngineService"  
    Stop-GsaServiceForce -ServiceName "GlobalSecureAccessTunnelingService"  
  
    Write-Output "===== GSA 監控程式結束（Boot 模式） ====="  
    exit 0  
}  
  
# ========== Mode: Auto ==========  
# 1. Ping 多次，儲存結果（True or False）  
try {  
    $pings = 1..$pingTimes | ForEach-Object {  
        Test-Connection -ComputerName $checkIP -Count 1 -Quiet -ErrorAction SilentlyContinue  
    }  
} catch {  
    Write-Output "❗ Test-Connection 執行失敗：$($_.Exception.Message)"  
    Write-Output "===== GSA 監控程式異常結束（Auto 模式） ====="  
    exit 1  
}  
  
# 2. 判斷是否全通 / 全斷  
$allSuccess = ($pings -notcontains $false)  # 全部都通 → 內網  
$allFail    = ($pings -notcontains $true)   # 全部都斷 → 外網  
  
# 3. 取得目前註冊值  
try {  
    $currentValue = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction Stop |  
                    Select-Object -ExpandProperty $regName  
} catch {  
    Write-Output "❗ 讀取註冊碼失敗：$regPath\$regName - $($_.Exception.Message)"  
    $currentValue = $null  
}  
  
# 4. 依 Ping 結果判斷與設定（Auto 模式）  
if ($allSuccess) {  
    Write-Output "✅ $checkIP 連續 $pingTimes 次皆成功 → 判斷為內網，自動關閉 GSA"  
  
    # 設定註冊碼：停用 GSA (1)  
    try {  
        if ($currentValue -ne 1) {  
            Set-ItemProperty -Path $regPath -Name $regName -Value 1 -ErrorAction Stop  
            Write-Output "🔧 已設定 $regName = 1（停用 GSA）"  
        } else {  
            Write-Output "⚠️ GSA 註冊碼已是停用狀態，無需變更"  
        }  
    } catch {  
        Write-Output "❗ 設定註冊碼失敗：$regPath\$regName - $($_.Exception.Message)"  
    }  
  
    # 停止 GSA 相關服務  
    Stop-GsaServiceForce -ServiceName "GlobalSecureAccessEngineService"  
    Stop-GsaServiceForce -ServiceName "GlobalSecureAccessTunnelingService"  
  
} elseif ($allFail) {  
    Write-Output "🌐 $checkIP 連續 $pingTimes 次皆失敗 → 判斷為外網，自動啟用 GSA"  
  
    # 設定註冊碼：啟用 GSA (0)  
    try {  
        if ($currentValue -ne 0) {  
            Set-ItemProperty -Path $regPath -Name $regName -Value 0 -ErrorAction Stop  
            Write-Output "🔧 已設定 $regName = 0（啟用 GSA）"  
        } else {  
            Write-Output "⚠️ GSA 註冊碼已是啟用狀態，無需變更"  
        }  
    } catch {  
        Write-Output "❗ 設定註冊碼失敗：$regPath\$regName - $($_.Exception.Message)"  
    }  
  
    # 啟動 GSA 相關服務  
    foreach ($svc in $gsaServices) {  
        try {  
            $service = Get-Service -Name $svc -ErrorAction Stop  
            if ($service.Status -ne 'Running') {  
                Write-Output "▶️ 嘗試啟動服務：$svc"  
                Start-Service -Name $svc -ErrorAction Stop  
                Write-Output "✅ 已啟動服務：$svc"  
            } else {  
                Write-Output "ℹ️ 服務已在執行中：$svc"  
            }  
        } catch {  
            Write-Output "❗ 啟動服務失敗：$svc - $($_.Exception.Message)"  
        }  
    }  
  
    Write-Output "ℹ️ 使用者在啟用 GSA 時，仍需依 Entra 設定完成 MFA 驗證。"  
  
} else {  
    Write-Output "⚖️ 連線狀況不穩定（部分成功、部分失敗），GSA 狀態不變更"  
}  
  
Write-Output "===== GSA 監控程式結束（Auto 模式） ====="  
