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

To publish actual local files through the bounded CLI, choose new destinations:

```powershell
# Report delivery: Chinese text, dates, three sheets and styles.
moon run cmd/main --target native -- rebuild tests/fixtures/business/report-1900.xlsm -o report.xlsx --receipt report.json --receipt-format v2
# Document intake: table, PNG/JPEG, section headers/footers and remote template.
moon run cmd/main --target native -- rebuild tests/fixtures/business/document-template.docm -o document.docx --receipt document.json --receipt-format v2
# Archive verification: actual original/output/report, not just the Pass field.
moon run cmd/main --target native -- verify document.docx --original tests/fixtures/business/document-template.docm --receipt document.json --receipt-format v2
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
