param(
  [Parameter(Mandatory)][string]$OutputDirectory,
  [string]$Version = '0.9.2'
)
$ErrorActionPreference = 'Stop'
$output = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $output | Out-Null
Push-Location -LiteralPath $output
try {
  @'
name = "consumer/partsieve-check"
version = "0.1.0"
preferred_target = "native"
'@ | Set-Content moon.mod
  'pkgtype(kind: "executable")' | Set-Content moon.pkg
  'fn main { println("registry dependency synchronized") }' | Set-Content main.mbt
  moon add "zlhahaha/partsieve@$Version"
  if ($LASTEXITCODE) { throw 'Registry dependency could not be added' }
  moon check --target native --deny-warn
  if ($LASTEXITCODE) { throw 'Registry dependency could not be checked' }
  $package = Join-Path $output '.mooncakes/zlhahaha/partsieve'
  $manifest = Get-Content -Raw -LiteralPath "$package/moon.mod"
  if ($manifest -notmatch ('(?m)^version\s*=\s*"' + [regex]::Escape($Version) + '"')) {
    throw 'Unexpected installed package version'
  }
  @'
import {
  "zlhahaha/partsieve" @sieve,
  "zlhahaha/partsieve/native_host" @host,
}
pkgtype(kind: "executable")
'@ | Set-Content moon.pkg
  foreach ($example in @('workflows','authorization')) {
    New-Item -ItemType Directory $example | Out-Null
    Copy-Item -LiteralPath "$package/examples/$example/main.mbt" -Destination "$example/main.mbt"
    Copy-Item -LiteralPath moon.pkg -Destination "$example/moon.pkg"
  }
  New-Item -ItemType Directory 'tests' | Out-Null
  Copy-Item -LiteralPath "$package/tests/fixtures" -Destination 'tests/fixtures' -Recurse
  @'
///|
fn[T] value(result : Result[T, @sieve.SdkFailure]) -> T raise {
  match result {
    Ok(ok) => ok
    Err(error) => fail(error.to_json().stringify())
  }
}

///|
fn main raise {
  let source = @host.read_bounded("tests/fixtures/business/document-template.docm", 33554432)
  let audit = @sieve.audit(source)
  assert_eq(audit.format, "DOCM")
  let preview = value(@sieve.preview_document(source))
  let approval = value(@sieve.authorize_document(preview, @sieve.RemovalPermissions::all_supported()))
  let result = value(@sieve.execute_authorized_document(source, approval))
  @host.write_new("delivered.docx", result.bytes)
  let saved = @host.read_bounded("delivered.docx", 67108864)
  assert_eq(value(@sieve.verify_document(saved, source)), result.receipt)
  let unsupported = @host.read_bounded("tests/fixtures/business/document-fields.docx", 33554432)
  match @sieve.preview_document(unsupported) {
    Err(error) => {
      assert_eq(error.code, @sieve.UnsupportedDocument)
      println(error.to_json().stringify())
    }
    Ok(_) => fail("unexpected preview success")
  }
  println("Registry SDK verified the actual saved document and returned a typed refusal")
}
'@ | Set-Content main.mbt
  foreach ($example in @('workflows','authorization','.')) {
    moon run $example --target native --deny-warn
    if ($LASTEXITCODE) { throw "Registry consumer failed: $example" }
  }
} finally {
  Pop-Location
}
