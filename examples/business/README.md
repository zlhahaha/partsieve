# Business workflow demonstration

Run from the repository root after the Native build:

```powershell
moon run examples/business --target native
```

This SDK example uses bounded native reads for five supported inputs and one
unsupported DOCX. Each case calls `clean_document` once. An `Ok` already contains
the actual rebuilt bytes and verified receipt; an `Err` carries a stable code,
operation and human-readable reason without rebuilt bytes. This main-branch
API is not yet included in the published 0.8.0 package.
It does not execute macros, fetch resources or upload documents. Fixtures are
synthetic and are not an external user's adoption.

For prepare/execute and archive verification paths, run
`moon run examples/workflows --target native --deny-warn`. That example shares
one work budget across plan preparation/execution and demonstrates a typed
cancellation branch. See [SDK integration](../../docs/sdk.md) for error-code
semantics and compatibility with the existing throwing APIs.

The checked-in previews are the verified macro-free
[Word document](preview/document-template.docx) and
[Excel workbook](preview/report-1900.xlsx). Use them for Office client checks.
Rebuild from the original fixtures with the CLI and verify each output against
its original and receipt. Choose a fresh output directory for each run.

```powershell
New-Item -ItemType Directory -Force tests/generated/business-demo | Out-Null
# Report delivery: Chinese text, dates, three sheets and styles.
moon run cmd/main --target native -- rebuild tests/fixtures/business/report-1900.xlsm -o tests/generated/business-demo/report-1900.xlsx --receipt tests/generated/business-demo/report-1900.json --receipt-format v2
moon run cmd/main --target native -- verify tests/generated/business-demo/report-1900.xlsx --original tests/fixtures/business/report-1900.xlsm --receipt tests/generated/business-demo/report-1900.json --receipt-format v2
# Document intake: table, PNG/JPEG, section headers/footers and remote template.
moon run cmd/main --target native -- rebuild tests/fixtures/business/document-template.docm -o tests/generated/business-demo/document-template.docx --receipt tests/generated/business-demo/document-template.json --receipt-format v2
moon run cmd/main --target native -- verify tests/generated/business-demo/document-template.docx --original tests/fixtures/business/document-template.docm --receipt tests/generated/business-demo/document-template.json --receipt-format v2
```

For independently reproducible acceptance evidence:

```powershell
.\tools\check.ps1
# Use the current RUN directory printed by check.ps1:
python tests/independent_business.py tests/generated/check-runs/RUN/business --next tests/generated/check-runs/RUN/next
dotnet run --project tests/OpenXmlValidation -- tests/generated/check-runs/RUN/business/document-template.docx tests/generated/check-runs/RUN/business/report-1900.xlsx
```

Use only verified macro-free outputs for Office client checks. A successful
schema test does not establish visual equivalence. WPS save/reopen observations
are recorded separately from SDK preservation; the current WPS Word client
introduces three style-order errors in its saved copies.
