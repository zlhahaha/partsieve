$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath "$PSScriptRoot\.."
$taskVersion = moon version --all
if ($LASTEXITCODE -ne 0 -or ($taskVersion -join "`n") -notmatch 'moonc v0\.10\.14\+7d59c7ec9') {
  throw 'Toolchain differs from dependency evidence; review before upgrading'
}
moon update
if ($LASTEXITCODE -ne 0) { throw 'Registry update failed' }
moon install
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed' }
.\tools\check-dependencies.ps1
if ($LASTEXITCODE -ne 0) { throw 'Dependency source drift' }
.\tools\check-fixtures.ps1
if ($LASTEXITCODE -ne 0) { throw 'Fixture drift' }
$taskInterfaces = @{}
Get-ChildItem -Filter pkg.generated.mbti -Recurse |
  Where-Object { $_.FullName -notmatch '[\\/](\.mooncakes|_build)[\\/]' } |
  ForEach-Object { $taskInterfaces[$_.FullName] = [IO.File]::ReadAllText($_.FullName) }
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
.\tools\check-resources.ps1
.\tools\generate-test-evidence.ps1
moon run examples/sdk --target native
if ($LASTEXITCODE -ne 0) { throw 'SDK example failed' }
moon run examples/business --target native
if ($LASTEXITCODE -ne 0) { throw 'Business SDK example failed' }

moon run examples/resources --target native --deny-warn
if ($LASTEXITCODE -ne 0) { throw "Resource SDK example failed" }

.\tools\acceptance-demo.ps1
if ($LASTEXITCODE -ne 0) { throw "Fixed acceptance demonstration failed" }
