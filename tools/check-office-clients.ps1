param(
  [Parameter(Mandatory)][string]$Cli,
  [Parameter(Mandatory)][string]$OutputDirectory,
  [string]$WordLinkInput
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$cliPath = (Resolve-Path -LiteralPath $Cli).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $output | Out-Null
$original = Join-Path $output 'original'
$clean = Join-Path $output 'partsieve'
$saved = Join-Path $output 'client'
New-Item -ItemType Directory -Path $original,$clean,$saved | Out-Null
$cases = @(
  @{name='document-template'; extension='docm'; fixture=(Join-Path $root 'tests/fixtures/business/document-template.docm')},
  @{name='document-notes-lists'; extension='docm'; fixture=(Join-Path $root 'tests/fixtures/business/document-notes-lists.docm')},
  @{name='report-1900'; extension='xlsm'; fixture=(Join-Path $root 'tests/fixtures/business/report-1900.xlsm')},
  @{name='report-1904'; extension='xlsm'; fixture=(Join-Path $root 'tests/fixtures/business/report-1904.xlsm')}
)
if ($WordLinkInput) {
  $cases += @{name='word-links'; extension='docm'; fixture=(Resolve-Path -LiteralPath $WordLinkInput).Path}
}
function Hash([string]$Path) {
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
foreach ($case in $cases) {
  $case.kind = if ($case.extension -eq 'docm') { 'Word' } else { 'Excel' }
  $suffix = if ($case.kind -eq 'Word') { 'docx' } else { 'xlsx' }
  $case.source = Join-Path $original "$($case.name).$($case.extension)"
  $case.clean = Join-Path $clean "$($case.name).$suffix"
  $receipt = $case.clean + '.json'
  Copy-Item -LiteralPath $case.fixture -Destination $case.source
  & $cliPath rebuild $case.source -o $case.clean --receipt $receipt --receipt-format v2 | Out-Null
  if ($LASTEXITCODE) { throw "Rebuild failed for $($case.name)" }
  & $cliPath verify $case.clean --original $case.source --receipt $receipt --receipt-format v2 | Out-Null
  if ($LASTEXITCODE) { throw "Verification failed for $($case.name)" }
}
function WordState($document) {
  $headers = @(foreach ($section in $document.Sections) {
    $header = $section.Headers.Item(1).Range
    $footer = $section.Footers.Item(1).Range
    [ordered]@{ header = $header.Text; footer = $footer.Text; header_images = $header.InlineShapes.Count; footer_images = $footer.InlineShapes.Count }
  })
  $notes = @(foreach ($note in $document.Footnotes) { $note.Range.Text })
  $endnotes = @(foreach ($note in $document.Endnotes) { $note.Range.Text })
  $list = @(foreach ($paragraph in $document.Paragraphs) {
    if ($paragraph.Range.ListFormat.ListType -ne 0) { $paragraph.Range.ListFormat.ListString }
  })
  [ordered]@{
    text = $document.Content.Text; tables = $document.Tables.Count
    images = $document.InlineShapes.Count; sections = $headers
    notes = $notes; endnotes = $endnotes; numbering = $list
    link_targets = @(foreach ($link in $document.Hyperlinks) { $link.Address })
    hyperlink_fields = @(foreach ($field in $document.Fields) {
      if ($field.Type -eq 88) { $field.Code.Text }
    })
    first_paragraph_style = $document.Paragraphs.Item(1).Range.Style.NameLocal
  }
}
function ExcelState($book) {
  $sheet = $book.Worksheets.Item(1)
  [ordered]@{
    sheet_names = @(foreach ($s in $book.Worksheets) { $s.Name })
    label = $sheet.Range('A3').Text; date = $sheet.Range('B3').Text
    date_serial = $sheet.Range('B3').Value2; amount = $sheet.Range('C3').Value2
    amount_format = $sheet.Range('C3').NumberFormat
    merged = $sheet.Range('A1').MergeArea.Address(); bold = $sheet.Range('A1').Font.Bold
    fill = $sheet.Range('A1').Interior.Color
  }
}
$rows = [Collections.Generic.List[object]]::new()
$marker = 'PartSieve client edit'
foreach ($client in @(
  @{id='Word.Application'; kind='Word'; name='Microsoft Word'},
  @{id='Excel.Application'; kind='Excel'; name='Microsoft Excel'},
  @{id='KWPS.Application'; kind='Word'; name='WPS Writer'},
  @{id='KET.Application'; kind='Excel'; name='WPS Spreadsheets'}
)) {
  $app = $null
  try {
    $app = New-Object -ComObject $client.id
    $app.AutomationSecurity = 3
    if ($app.AutomationSecurity -ne 3) { throw 'Client did not disable macros' }
    $app.DisplayAlerts = 0
    if ($client.kind -eq 'Word') { $app.Options.UpdateLinksAtOpen = $false }
    foreach ($case in $cases | Where-Object kind -eq $client.kind) {
      foreach ($stage in @('source','clean')) {
        $source = $case[$stage]
        $save = Join-Path $saved "$($client.id)-$($case.name)-$stage$([IO.Path]::GetExtension($case.clean))"
        $row = [ordered]@{
          client = $client.name; version = [string]$app.Version; build = [string]$app.Build
          case = $case.name; stage = $stage; before_sha256 = Hash $source
        }
        $rows.Add($row)
        $document = $null
        try {
          if ($client.kind -eq 'Word') {
            $document = $app.Documents.Open($source, $false, $true, $false)
            $row.before = WordState $document
            $end = $document.Content.End - 1
            $document.Range($end, $end).InsertAfter($marker)
            $document.SaveAs($save, 12)
            $document.Close($false)
            $document = $app.Documents.Open($save, $false, $true, $false)
            $row.after = WordState $document
            $row.edit_persisted = $row.after.text.Contains($marker)
            $row.after.text = $row.after.text.Replace($marker, '')
          } else {
            $document = $app.Workbooks.Open($source, 0, $true)
            $row.before = ExcelState $document
            $document.Worksheets.Item(1).Range('A7').Value2 = $marker
            $document.SaveAs($save, 51)
            $document.Close($false)
            $document = $app.Workbooks.Open($save, 0, $true)
            $row.after = ExcelState $document
            $row.edit_persisted = $document.Worksheets.Item(1).Range('A7').Text -eq $marker
          }
          $row.saved_sha256 = Hash $save
          $row.fields_changed_on_save = @($row.before.Keys | Where-Object {
            (ConvertTo-Json -InputObject $row.before[$_] -Compress -Depth 8) -cne
            (ConvertTo-Json -InputObject $row.after[$_] -Compress -Depth 8)
          })
          $row.result = if ($row.edit_persisted -and !$row.fields_changed_on_save) { 'Pass' } else { 'Difference' }
        } catch {
          $row.result = 'Error'
          $row.error = $_.Exception.Message
        } finally {
          if ($document) { $document.Close($false) }
          $rows.ToArray() | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $output 'progress.json')
        }
      }
    }
  } catch {
    $rows.Add([ordered]@{client = $client.name; result = 'Unavailable'; error = $_.Exception.Message})
  } finally {
    if ($app -and $client.id -in @('Word.Application','Excel.Application')) { $app.Quit() }
  }
}
foreach ($row in $rows | Where-Object { $_.stage -eq 'clean' -and $_.before }) {
  $source = $rows | Where-Object { $_.client -eq $row.client -and $_.case -eq $row.case -and $_.stage -eq 'source' }
  if ($source.before) {
    $row.fields_changed_on_rebuild = @($row.before.Keys | Where-Object {
      (ConvertTo-Json -InputObject $source.before[$_] -Compress -Depth 8) -cne
      (ConvertTo-Json -InputObject $row.before[$_] -Compress -Depth 8)
    })
  }
}
[ordered]@{platform = [Environment]::OSVersion.VersionString; rows = $rows.ToArray()} |
  ConvertTo-Json -Depth 12 | Set-Content (Join-Path $output 'client-matrix.json')
