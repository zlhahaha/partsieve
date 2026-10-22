$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskCli = Join-Path $taskRoot '_build/native/debug/build/cmd/main/main'
if ($IsWindows) { $taskCli += '.exe' }
$taskCases = @(
  @('tests/fixtures/upstream/macro01.xlsm','docs/evidence/verified.xlsx','legacy','fcc9a0ca93810d894df21c71d5764db7252afd3b1232b5aef55c21f3efcc9e53'),
  @('tests/fixtures/poi/SimpleMacro.docm','docs/evidence/word-verified.docx','legacy','4bb624cf9a6e465b1658c69f6d0bc607ccccf25e2ee1e3048b3e11376d8aa65e'),
  @('tests/fixtures/business/report-1900.xlsm','tests/generated/business-v3/report-1900.xlsx','v2',''),
  @('tests/fixtures/business/report-1904.xlsm','tests/generated/business-v3/report-1904.xlsx','v2',''),
  @('tests/fixtures/business/report-inline.xlsm','tests/generated/business-v3/report-inline.xlsx','v2',''),
  @('tests/fixtures/business/document-layout.docm','tests/generated/business-v3/document-layout.docx','v2',''),
  @('tests/fixtures/business/document-template.docm','tests/generated/business-v3/document-template.docx','v2','')
)
foreach ($taskCase in $taskCases) {
  $taskSource = Join-Path $taskRoot $taskCase[0]
  $taskOutput = Join-Path $taskRoot $taskCase[1]
  $taskReceipt = [IO.Path]::ChangeExtension($taskOutput, '.receipt.json')
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($taskOutput)) | Out-Null
  if (-not (Test-Path -LiteralPath $taskOutput) -and -not (Test-Path -LiteralPath $taskReceipt)) {
    $taskReport = & $taskCli rebuild $taskSource -o $taskOutput --receipt $taskReceipt --receipt-format $taskCase[2]
    if ($LASTEXITCODE -ne 0) { throw "Evidence rebuild failed: $taskReport" }
  }
  # Never silently replace an existing partial or stale evidence pair.
  $taskReport = & $taskCli verify $taskOutput --original $taskSource --receipt $taskReceipt --receipt-format $taskCase[2]
  if ($LASTEXITCODE -ne 0) { throw "Evidence verification failed: $taskReport" }
  $taskHash = (Get-FileHash -LiteralPath $taskOutput -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($taskCase[3] -and $taskHash -ne $taskCase[3]) { throw 'Output byte drift' }
  Write-Output "$($taskCase[1]): Pass ($taskHash)"
}
