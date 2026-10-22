$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskLock = Get-Content -Raw -LiteralPath (Join-Path $taskRoot 'docs/dependency-lock.json') | ConvertFrom-Json
foreach ($taskModule in $taskLock.dependencies) {
  $taskDirectory = Join-Path $taskRoot ('.mooncakes/' + $taskModule.module)
  $taskManifest = [IO.File]::ReadAllText((Join-Path $taskDirectory 'moon.mod'))
  if (-not $taskManifest.Contains('version = "' + $taskModule.version + '"')) { throw "Dependency version drift: $($taskModule.module)" }
  $taskPaths = @{}
  foreach ($taskFile in Get-ChildItem -LiteralPath $taskDirectory -Recurse -File -Force) {
    $taskRelative = [IO.Path]::GetRelativePath($taskDirectory, $taskFile.FullName).Replace('\', '/')
    if ($taskRelative.Split('/') -contains '_build') { continue }
    $taskPaths[$taskRelative] = $taskFile.FullName
  }
  [string[]]$taskNames = @($taskPaths.Keys)
    # Match the original Windows pathlib ordering by path components.
  $taskComparer = [Collections.Generic.Comparer[string]]::Create({
    param($taskLeft, $taskRight)
    $taskLeftParts = $taskLeft.Split('/')
    $taskRightParts = $taskRight.Split('/')
    for ($taskIndex = 0; $taskIndex -lt [Math]::Min($taskLeftParts.Length, $taskRightParts.Length); $taskIndex++) {
      $taskOrder = [StringComparer]::Ordinal.Compare($taskLeftParts[$taskIndex].ToLowerInvariant(), $taskRightParts[$taskIndex].ToLowerInvariant())
      if ($taskOrder -ne 0) { return $taskOrder }
    }
    return $taskLeftParts.Length.CompareTo($taskRightParts.Length)
  })
  [Array]::Sort($taskNames, $taskComparer)
  $taskHash = [Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
  try {
    foreach ($taskName in $taskNames) {
      $taskNameBytes = [Text.Encoding]::UTF8.GetBytes($taskName)
      $taskData = [IO.File]::ReadAllBytes($taskPaths[$taskName])
      foreach ($taskBytes in @($taskNameBytes, $taskData)) {
        $taskLength = [BitConverter]::GetBytes([uint64]$taskBytes.Length)
        if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($taskLength) }
        $taskHash.AppendData($taskLength)
        $taskHash.AppendData($taskBytes)
      }
    }
    $taskDigest = [Convert]::ToHexString($taskHash.GetHashAndReset()).ToLowerInvariant()
  } finally { $taskHash.Dispose() }
  if ($taskDigest -ne $taskModule.installed_source_sha256 -or $taskNames.Count -ne $taskModule.source_file_count) {
    throw "Installed dependency source drift: $($taskModule.module) ($taskDigest, $($taskNames.Count))"
  }
}
Write-Output 'Dependency source/version evidence verified.'
