$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath "$PSScriptRoot/.."
moon build --release --target native --deny-warn
if ($LASTEXITCODE -ne 0) { throw 'Resource regression build failed' }
$taskStem = Join-Path (Get-Location) '_build/native/release/build/tests/resources/resources'
$taskBinary = if (Test-Path -LiteralPath ($taskStem + '.exe')) { $taskStem + '.exe' } else { $taskStem }
$taskReports = @()
foreach ($taskCase in @('word-1m', 'word-4m', 'word-7m', 'sheet-5000', 'sheet-20000', 'word-xml-over', 'sheet-nodes-over')) {
  $taskStart = [Diagnostics.ProcessStartInfo]::new($taskBinary)
  $taskStart.ArgumentList.Add($taskCase)
  $taskStart.UseShellExecute = $false
  $taskStart.CreateNoWindow = $true
  $taskStart.RedirectStandardOutput = $true
  $taskStart.RedirectStandardError = $true
  $taskWatch = [Diagnostics.Stopwatch]::StartNew()
  $taskProcess = [Diagnostics.Process]::Start($taskStart)
  $taskOutput = $taskProcess.StandardOutput.ReadToEndAsync()
  $taskError = $taskProcess.StandardError.ReadToEndAsync()
  $taskPeak = $null
  while (-not $taskProcess.WaitForExit(50)) {
    try {
      $taskProcess.Refresh()
      $taskSample = $taskProcess.PeakWorkingSet64
      if ($taskSample -gt 0 -and ($null -eq $taskPeak -or $taskSample -gt $taskPeak)) { $taskPeak = $taskSample }
    } catch { }
    if ($taskWatch.ElapsedMilliseconds -lt 120000) { continue }
    $taskProcess.Kill($true)
    $taskProcess.WaitForExit()
    $taskProcess.Dispose()
    throw "Resource regression timed out: $taskCase"
  }
  $taskWatch.Stop()
  $taskText = $taskOutput.GetAwaiter().GetResult()
  $taskDiagnostic = $taskError.GetAwaiter().GetResult()
  if ($taskProcess.ExitCode -ne 0) {
    $taskProcess.Dispose()
    throw "Resource regression failed: $taskCase : $taskDiagnostic $taskText"
  }
  $taskReport = $taskText.Trim() | ConvertFrom-Json

  $taskReport | Add-Member -NotePropertyName elapsed_ms -NotePropertyValue $taskWatch.ElapsedMilliseconds
  $taskReport | Add-Member -NotePropertyName peak_working_set_bytes -NotePropertyValue $taskPeak
  $taskReports += $taskReport
  $taskProcess.Dispose()
  Write-Output ("Resource Pass: {0}, {1} ms" -f $taskCase, $taskWatch.ElapsedMilliseconds)
}
$taskEvidence = [ordered]@{
  tool = 'PartSieve Native resource regression'
  version = '0.6.0-spike'
  os = [Runtime.InteropServices.RuntimeInformation]::OSDescription
  architecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
  build = 'Release'
  observation = 'Whole child process: fixture construction plus successful rebuild and negative checks. Timings and peak working set are observations, not portable performance thresholds or measured cancellation latency. A null or zero peak means unavailable.'
  cases = $taskReports
}
if (-not (Test-Path -LiteralPath tests/generated)) { New-Item -ItemType Directory tests/generated | Out-Null }
$taskEvidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath tests/generated/resources-v6.json -Encoding utf8
