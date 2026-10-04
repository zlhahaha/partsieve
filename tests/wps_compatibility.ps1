param(
  [string]$InputPath = "$PSScriptRoot\..\docs\evidence\verified.xlsx",
  [string]$SavedPath = "$PSScriptRoot\..\docs\evidence\wps-saved.xlsx"
)
$ErrorActionPreference = 'Stop'
$taskInput = (Resolve-Path -LiteralPath $InputPath).Path
$taskSaved = [IO.Path]::GetFullPath($SavedPath)
if (Test-Path -LiteralPath $taskSaved) { throw 'WPS saved copy already exists' }
$taskWps = New-Object -ComObject ket.Application
$taskBook = $null
$taskReopened = $null
try {
  # Only the already verified macro-free output is opened. No input VBA runs.
  $taskBook = $taskWps.Workbooks.Open($taskInput, 0, $true)
  $taskA1 = $taskBook.Worksheets.Item(1).Range('A1').Value2
  if ($taskA1 -ne 123) { throw 'Unexpected A1 before save' }
  $taskBook.SaveCopyAs($taskSaved)
  $taskBook.Close($false)
  $taskReopened = $taskWps.Workbooks.Open($taskSaved, 0, $true)
  $taskReopenedA1 = $taskReopened.Worksheets.Item(1).Range('A1').Value2
  if ($taskReopenedA1 -ne 123) { throw 'Unexpected A1 after save/reopen' }
  [pscustomobject]@{
    tool = 'WPS Spreadsheets COM ket.Application'
    automationVersion = $taskWps.Version
    binaryVersion = (Get-Item -LiteralPath 'C:\Program Files (x86)\Kingsoft\WPS Office\12.1.0.28505\office6\et.exe').VersionInfo.FileVersion
    status = 'Pass'
    input = $taskInput
    savedCopy = $taskSaved
    inputSha256 = (Get-FileHash -LiteralPath $taskInput -Algorithm SHA256).Hash.ToLower()
    savedSha256 = (Get-FileHash -LiteralPath $taskSaved -Algorithm SHA256).Hash.ToLower()
    openA1 = $taskA1
    reopenedA1 = $taskReopenedA1
    sheets = $taskReopened.Worksheets.Count
    macroExecution = 'NotPerformed; only macro-free verified output opened'
    repairDialogObservation = 'NotChecked; COM open/save/reopen completed without exceptions'
    visualFidelity = 'NotChecked; fixture contains one numeric cell, no image'
  } | ConvertTo-Json -Depth 5
} finally {
  if ($taskReopened) { $taskReopened.Close($false); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($taskReopened) }
  if ($taskBook) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($taskBook) }
  # Do not quit an application instance that might also hold the user's files.
  [void][Runtime.InteropServices.Marshal]::ReleaseComObject($taskWps)
}
