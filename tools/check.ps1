$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath "$PSScriptRoot\.."
$taskVersion = moon version --all
if ($LASTEXITCODE -ne 0 -or ($taskVersion -join "`n") -notmatch 'moonc v0\.10\.14\+7d59c7ec9') {
  throw 'Toolchain differs from dependency evidence; review before upgrading'
}
python tools/lock_evidence.py
if ($LASTEXITCODE -ne 0) { throw 'Dependency source drift' }
python tools/record_fixture_provenance.py
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
moon test --target native --deny-warn
if ($LASTEXITCODE -ne 0) { throw 'moon test failed' }
moon build --target native --deny-warn
if ($LASTEXITCODE -ne 0) { throw 'moon build failed' }
python tests/regression.py
if ($LASTEXITCODE -ne 0) { throw 'Regression failed' }
moon run examples/sdk --target native
if ($LASTEXITCODE -ne 0) { throw 'SDK example failed' }
