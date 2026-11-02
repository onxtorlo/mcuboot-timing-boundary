# run_s5_windows.ps1 — 세션 S5: Windows 네이티브 경로 (ST-Link는 usbipd detach 상태여야 함)
# (1) 고해상도 기준 3크기 x 8회 (2) 72000B 고해상도 40회 (3) T=0.05 이진탐색 2회 (4) 점검: 스캔 허위 2쌍 + R1 + R2
param([string]$Work)
$py = Join-Path $Work "win_measure.py"
$data = "\\wsl.localhost\Ubuntu-24.04\home\onxtorlo\mcuboot-timing-boundary\outputs\supp\data"
python $py hr "$Work\hr_S5.csv" S5 8 60000,76628,785920 2>$null | Out-Null
"HR_DONE S5 $(Get-Date -Format HH:mm:ss)"
python $py hr "$Work\ts_S5.csv" S5 40 72000 2>$null | Out-Null
"TS_DONE S5 $(Get-Date -Format HH:mm:ss)"
$specs = @()
foreach ($k in 1, 2) {
  $line = python $py scan "$Work\scan_S5_$k.csv" "S5_$k" 0.05 2>$null | Select-String "^scan" | Select-Object -Last 1
  "$line"
  $p = "$line".Split(" ")
  $specs += "F_S5_${k}:$($p[3]):$($p[2])"
}
python $py check "$Work\check_S5.csv" S5 @specs R1:785919:785920 R2:15470:15471 2>$null | Select-String "^checked"
Copy-Item "$Work\*S5*" $data -Force
"SESSION_DONE S5 $(Get-Date -Format HH:mm:ss)"
