param([switch]$Offline)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath "$PSScriptRoot\.."
$taskRun = 'tests/generated/check-runs/' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N')
[IO.Directory]::CreateDirectory((Join-Path $PWD $taskRun)) | Out-Null
$taskPreviousOutput = $env:PARTSIEVE_TEST_OUTPUT
$env:PARTSIEVE_TEST_OUTPUT = (Join-Path $PWD $taskRun).Replace('\', '/')
$taskRunReport = [ordered]@{ schema = 'partsieve.check-run.v1'; result = 'Running'; output = $taskRun }
$taskRunReport | ConvertTo-Json | Set-Content -LiteralPath "$taskRun/run.json" -Encoding utf8
Write-Output "Check results: $taskRun"
try {
  $taskVersion = moon version --all
  if ($LASTEXITCODE -ne 0 -or ($taskVersion -join "`n") -notmatch 'moonc v0\.10\.14\+7d59c7ec9') {
    throw 'Toolchain differs from dependency evidence; review before upgrading'
  }
  if (-not $Offline) {
    moon update
    if ($LASTEXITCODE -ne 0) { throw 'Registry update failed' }
    moon install
    if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed' }
  }
  .\tools\check-dependencies.ps1
  if ($LASTEXITCODE -ne 0) { throw 'Dependency source drift' }
  .\tools\check-fixtures.ps1
  if ($LASTEXITCODE -ne 0) { throw 'Fixture drift' }
  $taskInterfaces = @{}
  # Prune generated/private trees before traversal: filtering after -Recurse still
  # visits old owner-only evidence directories and can fail before source checks.
  $taskSourceDirectories = [Collections.Generic.Stack[string]]::new()
  $taskSourceDirectories.Push($PWD.Path)
  while ($taskSourceDirectories.Count -gt 0) {
    $taskDirectory = $taskSourceDirectories.Pop()
    Get-ChildItem -LiteralPath $taskDirectory -File -Filter pkg.generated.mbti |
      ForEach-Object { $taskInterfaces[$_.FullName] = [IO.File]::ReadAllText($_.FullName) }
    Get-ChildItem -LiteralPath $taskDirectory -Directory |
      Where-Object {
        $_.Name -notin @('.git', '.mooncakes', '_build', 'target', '.moonagent', 'generated', 'bin', 'obj', 'test-deps') -and
        $_.FullName -notmatch '[\\/]docs[\\/]evidence$' -and
        -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
      } |
      ForEach-Object { $taskSourceDirectories.Push($_.FullName) }
  }
  moon info
  if ($LASTEXITCODE -ne 0) { throw 'moon info failed' }
  foreach ($taskPath in $taskInterfaces.Keys) {
    if ([IO.File]::ReadAllText($taskPath) -ne $taskInterfaces[$taskPath]) {
      throw "Public interface changed: $taskPath"
    }
  }
  moon fmt --check
  if ($LASTEXITCODE -ne 0) { throw 'Format check failed' }
  moon check --target native --deny-warn
  if ($LASTEXITCODE -ne 0) { throw 'moon check failed' }
  moon build --target native --deny-warn
  if ($LASTEXITCODE -ne 0) { throw 'moon build failed' }
  moon build --release --target native --deny-warn
  if ($LASTEXITCODE -ne 0) { throw 'Release build failed' }
  # Native integration tests execute these already built CLI/probe binaries.
  moon test --target native --deny-warn
  if ($LASTEXITCODE -ne 0) { throw 'moon test failed' }
  moon run tests/next --target native --deny-warn
  if ($LASTEXITCODE -ne 0) { throw 'Click-link and Word OLE regression failed' }
  moon run tests/robustness --target native --deny-warn
  if ($LASTEXITCODE -ne 0) { throw 'Deterministic robustness regression failed' }
  moon run tests/batch --target native --deny-warn
  if ($LASTEXITCODE -ne 0) { throw 'Batch directory regression failed' }
  .\tools\check-resources.ps1 -OutputPath "$taskRun/resources.json"
  .\tools\generate-test-evidence.ps1 -EvidenceRoot "$taskRun/evidence" -BusinessRoot "$taskRun/business"
  moon run examples/sdk --target native
  if ($LASTEXITCODE -ne 0) { throw 'SDK example failed' }
  moon run examples/business --target native
  if ($LASTEXITCODE -ne 0) { throw 'Business SDK example failed' }

  moon run examples/resources --target native --deny-warn
  if ($LASTEXITCODE -ne 0) { throw "Resource SDK example failed" }

  .\tools\acceptance-demo.ps1 -OutputDirectory (Join-Path $PWD "$taskRun/demo")
  if ($LASTEXITCODE -ne 0) { throw "Fixed acceptance demonstration failed" }
  $taskRunReport.result = 'Pass'
  # Stable CI exports come only from this completed run in a clean checkout.
  if ($env:GITHUB_ACTIONS -eq 'true') {
    $taskRunReport | ConvertTo-Json | Set-Content -LiteralPath "$taskRun/run.json" -Encoding utf8
    & "$PSScriptRoot/export-ci-evidence.ps1" -RunDirectory $taskRun
  }
} catch {
  $taskRunReport.result = 'Fail'
  $taskRunReport['error'] = $_.Exception.Message
  throw
} finally {
  $taskRunReport | ConvertTo-Json | Set-Content -LiteralPath "$taskRun/run.json" -Encoding utf8
  $env:PARTSIEVE_TEST_OUTPUT = $taskPreviousOutput
}
