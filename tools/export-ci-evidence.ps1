param([Parameter(Mandatory)][string]$RunDirectory)
$ErrorActionPreference = 'Stop'
$taskManifest = Get-Content -Raw -LiteralPath "$RunDirectory/run.json" | ConvertFrom-Json
if ($taskManifest.result -ne 'Pass') { throw 'Only a completed run may export evidence' }
foreach ($taskMapping in @(
  @('evidence', 'docs/evidence'),
  @('business', 'tests/generated/business-v3'),
  @('next', 'tests/generated/next-v7_1'),
  @('demo', 'tests/generated/acceptance-demo/ci-current')
)) {
  if (Test-Path -LiteralPath $taskMapping[1]) { throw "CI export destination exists: $($taskMapping[1])" }
  [IO.Directory]::CreateDirectory((Split-Path -Parent $taskMapping[1])) | Out-Null
  Copy-Item -LiteralPath "$RunDirectory/$($taskMapping[0])" -Destination $taskMapping[1] -Recurse
}
foreach ($taskMapping in @(
  @('resources.json', 'resources-v7_1.json'),
  @('robustness-v1.json', 'robustness-v1.json'),
  @('batch-v1.json', 'batch-v1.json')
)) {
  $taskTarget = 'tests/generated/' + $taskMapping[1]
  if (Test-Path -LiteralPath $taskTarget) { throw "CI export destination exists: $taskTarget" }
  Copy-Item -LiteralPath "$RunDirectory/$($taskMapping[0])" -Destination $taskTarget
}
