$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
foreach ($taskManifestPath in @('tests/fixtures/provenance.json','tests/fixtures/poi/provenance.json')) {
  $taskManifest = Get-Content -Raw -LiteralPath (Join-Path $taskRoot $taskManifestPath) | ConvertFrom-Json
  foreach ($taskRecord in $taskManifest.files) {
    $taskPath = Join-Path $taskRoot $taskRecord.path
    if ((Get-Item -LiteralPath $taskPath).Length -ne $taskRecord.bytes -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $taskPath).Hash.ToLowerInvariant() -ne $taskRecord.sha256 -or
        -not $taskRecord.source.Contains($taskManifest.commit)) { throw "Fixture drift: $($taskRecord.path)" }
  }
}
$taskBusiness = Get-Content -Raw -LiteralPath (Join-Path $taskRoot 'tests/fixtures/business/provenance.json') | ConvertFrom-Json
foreach ($taskRecord in $taskBusiness.files.PSObject.Properties) {
  $taskPath = Join-Path $taskRoot ('tests/fixtures/business/' + $taskRecord.Name)
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $taskPath).Hash.ToLowerInvariant() -ne $taskRecord.Value) { throw "Business fixture drift: $($taskRecord.Name)" }
}
$taskCorpus = Get-Content -Raw -LiteralPath (Join-Path $taskRoot 'tests/corpus/provenance.json') | ConvertFrom-Json
foreach ($taskRecord in $taskCorpus.files.PSObject.Properties) {
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $taskRoot ('tests/corpus/' + $taskRecord.Name))).Hash.ToLowerInvariant() -ne $taskRecord.Value) { throw "Native corpus drift: $($taskRecord.Name)" }
}
Write-Output 'Pinned fixture and native corpus hashes verified.'
