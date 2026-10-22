# Business workflow demonstration

Run from the repository root after the Native build:

```powershell
moon run examples/business --target native
```

This trusted-fixture SDK example processes five supported inputs and one
unsupported DOCX. Each accepted case prepares a plan, executes it and verifies
the actual output; unsupported input receives a reason without rebuilt bytes.
It does not execute macros, fetch resources or upload documents. Fixtures are
synthetic and are not an external user's adoption.

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
python tests/independent_business.py
dotnet run --project tests/OpenXmlValidation -- tests/generated/business-v3/document-template.docx tests/generated/business-v3/report-1900.xlsx
```

Use only verified macro-free outputs for Office client checks. A successful
schema test does not establish visual equivalence. WPS save/reopen observations
are recorded separately from SDK preservation; the current WPS Word client
introduces three style-order errors in its saved copies.
