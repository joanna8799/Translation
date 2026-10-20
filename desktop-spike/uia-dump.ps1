# 桌面閱讀器讀字驗證（Windows）
# 問題：Ridi PC 閱讀器、Naver Series 閱讀器這類桌面 app，能不能用 Windows 的 UI Automation 直接讀到正文？
# 讀得到，桌面版小說翻譯就走這條（跟 Android 無障礙服務同一個做法），不用 OCR，也不怕 DRM 擋截圖。
#
# 用法：
#   1. 先把閱讀器開到正文頁。
#   2. 開 PowerShell（一般權限即可），執行：  powershell -ExecutionPolicy Bypass -File .\uia-dump.ps1
#   3. 5 秒內點一下閱讀器視窗讓它在最前面。
#   4. 結果印在 PowerShell 裡，也存成 uia-dump.txt。把最後一行「節點 N 個，字數 M」和前面幾行貼回來。
#
# 判讀：字數 ≥ 200 而且內容就是正文 → 讀得到。只有按鈕、章名 → 閱讀器是自繪的，要走截圖 OCR。

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System; using System.Runtime.InteropServices;
public class RTUser32 { [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); }
"@

Write-Host "5 秒內點一下閱讀器視窗…"
Start-Sleep -Seconds 5
$h = [RTUser32]::GetForegroundWindow()
$win = [System.Windows.Automation.AutomationElement]::FromHandle($h)
$lines = @()
$lines += "視窗：" + $win.Current.Name + "  class=" + $win.Current.ClassName + "  pid=" + $win.Current.ProcessId

$all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
$count = 0; $chars = 0
foreach ($e in $all) {
  $t = $null
  try { $tp = $e.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern); $t = $tp.DocumentRange.GetText(-1) } catch {}
  if (-not $t) { try { $vp = $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); $t = $vp.Current.Value } catch {} }
  if (-not $t) { $t = $e.Current.Name }
  if ($t) { $t = $t.Trim() }
  if ($t -and $t.Length -ge 4) {
    $count++; $chars += $t.Length
    $lines += "[" + $e.Current.ControlType.ProgrammaticName.Replace("ControlType.", "") + "] " + $t.Substring(0, [Math]::Min(100, $t.Length)).Replace("`r", " ").Replace("`n", " ")
  }
}
$lines += "節點 $count 個，字數 $chars"
$lines | Tee-Object -FilePath (Join-Path $PSScriptRoot "uia-dump.txt")
