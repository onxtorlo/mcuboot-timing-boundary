# clockrate_probe.ps1 — WSL2 게스트 시계(CLOCK_MONOTONIC)와 Windows 시계(QPC Stopwatch)의 진행 속도 비교.
# 매 구간(약 20초)마다 두 시계의 경과시간 비(ratio = WSL경과/Windows경과)를 기록. 보드는 사용하지 않음.
# 사용: powershell -File clockrate_probe.ps1 <out.csv> <minutes>
param([string]$Out, [double]$Minutes = 30, [int]$Interval = 20)
$sw = [System.Diagnostics.Stopwatch]::StartNew()
"win_s,wsl_mono_s,wsl_real_s,ratio_interval" | Out-File -Encoding utf8 $Out
$prevW = $null; $prevL = $null
while ($sw.Elapsed.TotalMinutes -lt $Minutes) {
  $w0 = $sw.Elapsed.TotalSeconds
  $l = (wsl -e python3 -c "import time; print(time.monotonic(), time.time())").Trim().Split(" ")
  $w1 = $sw.Elapsed.TotalSeconds
  $w = ($w0 + $w1) / 2
  $lm = [double]$l[0]; $lr = [double]$l[1]
  $ratio = ""
  if ($prevW -ne $null) { $ratio = "{0:F4}" -f (($lm - $prevL) / ($w - $prevW)) }
  "{0:F3},{1:F3},{2:F3},{3}" -f $w, $lm, $lr, $ratio | Out-File -Append -Encoding utf8 $Out
  $prevW = $w; $prevL = $lm
  Start-Sleep -Seconds $Interval
}
