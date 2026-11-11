param(
  [Parameter(Mandatory)][string]$Cli,
  [Parameter(Mandatory)][string]$CacheDirectory,
  [Parameter(Mandatory)][string]$OutputDirectory,
  [switch]$Offline,
  [string]$ManifestPath = ''
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskManifestPath = if ($ManifestPath) { (Resolve-Path -LiteralPath $ManifestPath).Path } else { Join-Path $taskRoot 'tests/external/poi-manifest.json' }
$taskManifest = Get-Content -Raw -LiteralPath $taskManifestPath | ConvertFrom-Json
$taskCli = (Resolve-Path -LiteralPath $Cli).Path
$taskCache = [IO.Path]::GetFullPath($CacheDirectory)
$taskOutput = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $taskOutput) { throw 'Choose a new output directory; old evidence is never replaced' }
[IO.Directory]::CreateDirectory($taskCache) | Out-Null
foreach ($taskCase in $taskManifest.cases) {
  if ($taskCase.name -notmatch '^[A-Za-z0-9_-]+\.(docx|xlsx|xlsm)$' -or
      $taskCase.url -notmatch ('^https://raw\.githubusercontent\.com/apache/poi/' + $taskManifest.revision + '/test-data/(document|spreadsheet)/')) {
    throw 'Unexpected corpus path or source'
  }
  $taskPath = Join-Path $taskCache $taskCase.name
  if (-not (Test-Path -LiteralPath $taskPath)) {
    if ($Offline) { throw "Missing offline fixture: $($taskCase.name)" }
    $taskPartial = $taskPath + '.' + [guid]::NewGuid().ToString('N') + '.partial'
    & curl.exe --fail --location --retry 3 --retry-all-errors --max-time 60 --max-filesize 1048576 --silent --show-error $taskCase.url --output $taskPartial
    if ($LASTEXITCODE -ne 0) { throw "Fixture download failed: $($taskCase.name)" }
    if ((Get-Item -LiteralPath $taskPartial).Length -ne $taskCase.bytes -or
        (Get-FileHash -LiteralPath $taskPartial -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskCase.sha256) {
      throw "Downloaded fixture drift: $($taskCase.name)"
    }
    Move-Item -LiteralPath $taskPartial -Destination $taskPath
  }
  if ((Get-Item -LiteralPath $taskPath).Length -ne $taskCase.bytes -or
      (Get-FileHash -LiteralPath $taskPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskCase.sha256) {
    throw "Cached fixture drift: $($taskCase.name)"
  }
}
# Retain upstream licensing alongside a network-fetched or pre-populated cache.
foreach ($taskLicense in @('LICENSE', 'NOTICE')) {
  $taskLicensePath = Join-Path $taskCache $taskLicense
  if (-not (Test-Path -LiteralPath $taskLicensePath)) {
    Copy-Item -LiteralPath (Join-Path $taskRoot "tests/fixtures/poi/$taskLicense") -Destination $taskLicensePath
  }
}
[IO.Directory]::CreateDirectory($taskOutput) | Out-Null
$taskDelivery = Join-Path $taskOutput 'delivery'
$taskText = & $taskCli batch $taskCache -o $taskDelivery --json
$taskExit = $LASTEXITCODE
$taskText | Set-Content -LiteralPath (Join-Path $taskOutput 'batch.stdout.json') -Encoding utf8
if ($taskExit -notin @(0, 2, 3)) { throw "Corpus execution failed: $taskExit" }
$taskBatch = Get-Content -Raw -LiteralPath (Join-Path $taskDelivery 'batch.json') | ConvertFrom-Json
$taskRows = @()
foreach ($taskCase in $taskManifest.cases) {
  $taskEntries = @($taskBatch.entries | Where-Object input -eq $taskCase.name)
  if ($taskEntries.Count -ne 1) { throw "Missing/duplicate result: $($taskCase.name)" }
  $taskEntry = $taskEntries[0]
  $taskSuffix = if ($taskCase.category -eq 'document') { '.docx' } else { '.xlsx' }
  $taskFile = Join-Path $taskDelivery ($taskCase.name + '.cleaned' + $taskSuffix)
  $taskReceipt = Join-Path $taskDelivery ($taskCase.name + '.receipt.json')
  if ($taskEntry.status -eq 'Success') {
    $taskVerified = & $taskCli verify $taskFile --original (Join-Path $taskCache $taskCase.name) --receipt $taskReceipt --receipt-format v2
    if ($LASTEXITCODE -ne 0) { throw "Actual-file verification failed: $($taskCase.name)" }
    $taskVerified | Set-Content -LiteralPath (Join-Path $taskOutput ($taskCase.name + '.verify.json')) -Encoding utf8
  } elseif ($taskEntry.status -in @('Refused', 'Failed')) {
    if ((Test-Path -LiteralPath $taskFile) -or (Test-Path -LiteralPath $taskReceipt)) { throw 'Rejected case left published output or receipt' }
  } else { throw "Unexpected selected-input status: $($taskEntry.status)" }
  $taskRows += $taskEntry
}
$taskResult = [ordered]@{
  schema = 'partsieve.external-corpus-result.v1'
  measurement = 'Complete; does not imply all documents are supported or safe'
  adoption = 'Third-party regression fixtures, not independent customer use'
  source_revision = $taskManifest.revision
  manifest_sha256 = (Get-FileHash -LiteralPath $taskManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
  cli_sha256 = (Get-FileHash -LiteralPath $taskCli -Algorithm SHA256).Hash.ToLowerInvariant()
  selected = $taskManifest.cases.Count
  success = @($taskRows | Where-Object status -eq 'Success').Count
  refused = @($taskRows | Where-Object status -eq 'Refused').Count
  failed = @($taskRows | Where-Object status -eq 'Failed').Count
  cases = $taskRows
}
$taskResult | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $taskOutput 'result.json') -Encoding utf8
Write-Output ("Measured {0}: {1} supported, {2} refused, {3} failed" -f $taskResult.selected, $taskResult.success, $taskResult.refused, $taskResult.failed)
if ($taskResult.failed -gt 0) { throw 'Corpus includes integrity/processing failures; inspect result.json' }
