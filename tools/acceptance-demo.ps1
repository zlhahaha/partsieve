param([string]$OutputDirectory = '')
$ErrorActionPreference = 'Stop'

function Get-DemoHash([string]$Path) {
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Invoke-DemoCli([string]$Label, [string[]]$Arguments, [int]$ExpectedExit = 0) {
  $start = [Diagnostics.ProcessStartInfo]::new($script:demoCli)
  $start.UseShellExecute = $false
  $start.CreateNoWindow = $true
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::Start($start)
  $stdout = $process.StandardOutput.ReadToEndAsync()
  $stderr = $process.StandardError.ReadToEndAsync()
  if (-not $process.WaitForExit(90000)) {
    $process.Kill($true)
    $process.WaitForExit()
    $process.Dispose()
    throw "Demo command timed out: $Label"
  }
  $text = $stdout.GetAwaiter().GetResult()
  $diagnostic = $stderr.GetAwaiter().GetResult()
  $code = $process.ExitCode
  $process.Dispose()
  [IO.File]::WriteAllText((Join-Path $script:demoRun ($Label + '.stdout.json')), $text)
  [IO.File]::WriteAllText((Join-Path $script:demoRun ($Label + '.stderr.txt')), $diagnostic)
  $script:demoCommands.Add([ordered]@{ name = $Label; arguments = $Arguments; exit_code = $code })
  if ($code -ne $ExpectedExit) { throw "Unexpected exit code for ${Label}: $code : $diagnostic $text" }
  $text | ConvertFrom-Json
}

# In a prepared bundle, the same script runs using only its local executable.
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'demo-inputs.json')) {
  if ($OutputDirectory) { throw 'A prepared bundle chooses a new runs subdirectory automatically' }
  $demoBundle = $PSScriptRoot
} else {
  $demoRepo = Split-Path -Parent $PSScriptRoot
  Push-Location -LiteralPath $demoRepo
  try {
    $module = [IO.File]::ReadAllText((Join-Path $demoRepo 'moon.mod'))
    if ($module -notmatch 'version\s*=\s*"0\.7\.1-spike"') { throw 'This fixed demonstration targets PartSieve 0.7.1-spike' }
    moon build --release --target native --deny-warn
    if ($LASTEXITCODE -ne 0) { throw 'Native Release build failed' }
    $multiSource = Join-Path $demoRepo 'tests/fixtures/business/demo-word-three-objects.docm'
    if (-not (Test-Path -LiteralPath $multiSource)) { throw 'Fixed demonstration fixture is missing' }
    $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $demoBundle = if ($OutputDirectory) { [IO.Path]::GetFullPath($OutputDirectory) } else { Join-Path $demoRepo ('tests/generated/acceptance-demo/' + $stamp) }
    if (Test-Path -LiteralPath $demoBundle) { throw 'Choose a new output directory; existing bundles are never overwritten' }
    [IO.Directory]::CreateDirectory($demoBundle) | Out-Null
    foreach ($folder in @('inputs', 'bin', 'licenses')) { [IO.Directory]::CreateDirectory((Join-Path $demoBundle $folder)) | Out-Null }
    $stem = Join-Path $demoRepo '_build/native/release/build/cmd/main/main'
    $native = if (Test-Path -LiteralPath ($stem + '.exe')) { $stem + '.exe' } else { $stem }
    $binaryName = if ([IO.Path]::GetExtension($native) -eq '.exe') { 'partsieve.exe' } else { 'partsieve' }
    Copy-Item -LiteralPath $native -Destination (Join-Path $demoBundle ('bin/' + $binaryName))
    $inputs = @(
      @('report.xlsm', (Join-Path $demoRepo 'tests/fixtures/business/report-1900.xlsm')),
      @('word-three-objects.docm', $multiSource),
      @('unsupported.docx', (Join-Path $demoRepo 'tests/fixtures/poi/SampleDoc.docx'))
    )
    $inputRecords = @()
    foreach ($item in $inputs) {
      $target = Join-Path $demoBundle ('inputs/' + $item[0])
      Copy-Item -LiteralPath $item[1] -Destination $target
      $inputRecords += [ordered]@{ name = $item[0]; sha256 = Get-DemoHash $target }
    }
    foreach ($item in @(
      @('LICENSE', 'partsieve-LICENSE'),
      @('tests/fixtures/upstream/LICENSE.txt', 'XlsxWriter-LICENSE.txt'),
      @('tests/fixtures/poi/LICENSE', 'POI-LICENSE'),
      @('tests/fixtures/poi/NOTICE', 'POI-NOTICE'),
      @('tests/fixtures/business/provenance.json', 'business-provenance.json'),
      @('tests/fixtures/poi/provenance.json', 'poi-provenance.json')
    )) { Copy-Item -LiteralPath (Join-Path $demoRepo $item[0]) -Destination (Join-Path $demoBundle ('licenses/' + $item[1])) }
    Copy-Item -LiteralPath (Join-Path $demoRepo 'docs/acceptance-demo.md') -Destination (Join-Path $demoBundle '演示说明.md')
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $demoBundle 'run-demo.ps1')
    $revision = $null
    $dirty = $null
    $sourceKind = 'package-without-git'
    if ((Test-Path -LiteralPath (Join-Path $demoRepo '.git')) -and (Get-Command git -ErrorAction SilentlyContinue)) {
      $revision = git -c safe.directory=$demoRepo -c core.excludesfile=NUL rev-parse HEAD
      if ($LASTEXITCODE -ne 0) { throw 'Cannot record source revision' }
      $dirty = [bool](git -c safe.directory=$demoRepo -c core.excludesfile=NUL status --porcelain)
      $sourceKind = 'git-checkout'
    }
    $manifest = [ordered]@{
      schema = 'partsieve.acceptance-demo.v1'; tool = 'partsieve/0.7.1-spike'
      source_revision = $revision; source_worktree_dirty = $dirty; source_kind = $sourceKind
      platform = [Runtime.InteropServices.RuntimeInformation]::OSDescription
      architecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
      binary = 'bin/' + $binaryName; binary_sha256 = Get-DemoHash (Join-Path $demoBundle ('bin/' + $binaryName))
      inputs = $inputRecords
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $demoBundle 'demo-inputs.json') -Encoding utf8
  } finally { Pop-Location }
}

$demoManifest = Get-Content -LiteralPath (Join-Path $demoBundle 'demo-inputs.json') -Raw | ConvertFrom-Json
$script:demoCli = Join-Path $demoBundle $demoManifest.binary
if ((Get-DemoHash $script:demoCli) -ne $demoManifest.binary_sha256) { throw 'Bundled executable hash changed' }
foreach ($item in $demoManifest.inputs) {
  if ((Get-DemoHash (Join-Path $demoBundle ('inputs/' + $item.name))) -ne $item.sha256) { throw "Input hash changed: $($item.name)" }
}
$script:demoRun = Join-Path $demoBundle ('runs/' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($script:demoRun) | Out-Null
$script:demoCommands = [Collections.Generic.List[object]]::new()
$reportInput = Join-Path $demoBundle 'inputs/report.xlsm'
$wordInput = Join-Path $demoBundle 'inputs/word-three-objects.docm'
$reportOutput = Join-Path $script:demoRun '01-report.xlsx'
$wordOutput = Join-Path $script:demoRun '02-word.docx'

foreach ($item in @(@('01-report', $reportInput, $reportOutput), @('02-word', $wordInput, $wordOutput))) {
  $label = $item[0]; $inputFile = $item[1]; $outputFile = $item[2]
  $planPath = Join-Path $script:demoRun ($label + '.plan.json')
  $receiptPath = Join-Path $script:demoRun ($label + '.receipt.json')
  $plan = Invoke-DemoCli ($label + '-prepare') @('prepare', $inputFile)
  $plan | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $planPath -Encoding utf8
  $rebuilt = Invoke-DemoCli ($label + '-rebuild') @('rebuild', $inputFile, '-o', $outputFile, '--plan', $planPath, '--receipt', $receiptPath, '--receipt-format', 'v2')
  $verified = Invoke-DemoCli ($label + '-verify') @('verify', $outputFile, '--original', $inputFile, '--receipt', $receiptPath, '--receipt-format', 'v2')
  $golden = if ($label -eq '01-report') { '8332e75de9f125a9a35089e9b767ac55e02b27a5bcdb644a538749f8b6b29c02' } else { '9ab228316e311e207b4332cdbfd7bc55aa0580c0fefef73cc425eceaa82adffb' }
  if ($verified.tool -ne $demoManifest.tool -or $verified.result -ne 'Pass' -or $verified.output_hash -ne $golden -or (Get-DemoHash $outputFile) -ne $golden) { throw 'Fixed demonstration result drifted' }
  if ($label -eq '02-word' -and @($verified.findings | Where-Object capability -eq OLE).Count -ne 3) { throw 'Expected exactly three independently removed OLE objects' }
  Write-Output "$label : rebuild and actual-file verification Pass"
}

$tampered = Join-Path $script:demoRun '03-tampered.docx'
Copy-Item -LiteralPath $wordOutput -Destination $tampered
$zip = [IO.Compression.ZipFile]::Open($tampered, [IO.Compression.ZipArchiveMode]::Update)
try {
  $entry = $zip.GetEntry('word/document.xml')
  $reader = [IO.StreamReader]::new($entry.Open(), [Text.Encoding]::UTF8)
  try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
  $marker = 'Between objects 中文 1'
  if (-not $text.Contains($marker)) { throw 'Pinned ordinary-text tampering marker missing' }
  $entry.Delete()
  $replacement = $zip.CreateEntry('word/document.xml')
  $writer = [IO.StreamWriter]::new($replacement.Open(), [Text.UTF8Encoding]::new($false))
  try { $writer.Write($text.Replace($marker, 'TAMPERED ordinary text')) } finally { $writer.Dispose() }
} finally { $zip.Dispose() }
$null = Invoke-DemoCli '03-tamper-rejected' @('verify', $tampered, '--original', $wordInput, '--receipt', (Join-Path $script:demoRun '02-word.receipt.json'), '--receipt-format', 'v2') 2
Write-Output '03-tamper : expected integrity rejection Pass (exit 2)'

$unsupportedOutput = Join-Path $script:demoRun '04-must-not-exist.docx'
$unsupportedReceipt = Join-Path $script:demoRun '04-must-not-exist.receipt.json'
$null = Invoke-DemoCli '04-unsupported-rejected' @('rebuild', (Join-Path $demoBundle 'inputs/unsupported.docx'), '-o', $unsupportedOutput, '--receipt', $unsupportedReceipt, '--receipt-format', 'v2') 3
if ((Test-Path -LiteralPath $unsupportedOutput) -or (Test-Path -LiteralPath $unsupportedReceipt)) { throw 'Unsupported input produced a success pair' }
Write-Output '04-unsupported : expected refusal with no successful files Pass (exit 3)'

[ordered]@{
  schema = 'partsieve.acceptance-demo-result.v1'; tool = $demoManifest.tool
  source_revision = $demoManifest.source_revision; source_worktree_dirty = $demoManifest.source_worktree_dirty; source_kind = $demoManifest.source_kind
  result = 'Pass'; commands = $script:demoCommands
  checks = @('spreadsheet rebuild and verify', 'three-OLE saved-plan rebuild and verify', 'tampered ordinary text rejected', 'unsupported input refused without output pair')
  independent_validation = 'NotChecked by this runner'; wps_validation = 'NotChecked'
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $script:demoRun 'demo-result.json') -Encoding utf8
@"
# 验收演示结果

- 模块：$($demoManifest.tool)
- 来源类型：$($demoManifest.source_kind)；Git源码：$($demoManifest.source_revision)，准备时存在未提交修改：$($demoManifest.source_worktree_dirty)。注册表/源码包无Git元数据时留空，以模块版本和文件摘要记录。
- 报表去宏与实际文件核验：通过；输出 01-report.xlsx。
- Word三个独立OLE移除、保存计划执行及实际文件核验：通过；输出 02-word.docx。
- 普通正文被篡改：按预期拒绝，退出码2；03-tampered.docx仅作拒绝演示。
- 不支持输入：按预期拒绝，退出码3；没有生成成功文件对。
- 完整命令、报告、摘要与错误输出保存在本目录。哈希绑定文件，不提供真实性签名。
- 本运行器没有执行独立格式或WPS检查；多对象WPS验证仍待补齐。OLE内容及专属预览已删除。
- 再次运行演示包中的 run-demo.ps1 会新建 runs 子目录，不覆盖本次产物。
"@ | Set-Content -LiteralPath (Join-Path $script:demoRun '结果摘要.md') -Encoding utf8
Write-Output "Demo bundle: $demoBundle"
Write-Output "Demo results: $script:demoRun"
exit 0
