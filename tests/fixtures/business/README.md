# Business integration fixtures

These are author-generated synthetic documents for testing; they are not
third-party adoption or a claim to support arbitrary Office documents.

- `report-1900.xlsm`: shared strings, Chinese/English text, serial dates using
  the 1900 system, three sheets, currency formats, borders, fonts and merges.
- `report-1904.xlsm`: the same visible dates using the 1904 system.
- `report-inline.xlsm`: inline strings rather than the shared-string table.
- `document-layout.docm`: a table, merged cells, inline PNG/JPEG, two sections,
  separate headers/footers and header/footer images.
- `document-template.docm`: the layout above with a settings-local HTTP(S)
  attached-template reference pointing to `example.invalid`, never fetched.

New content/layout/images: PartSieve authors, Apache-2.0. Generated with
XlsxWriter 3.2.9 and CPython XML/Pillow; no Office reader/writer implementation
was copied into the MoonBit library. Hashes are pinned in `provenance.json`.

VBA bytes are copied unchanged from the already pinned test fixtures:

- Spreadsheet: `../upstream/macro01.xlsm`, BSD-2-Clause; its license is
  `../upstream/LICENSE.txt`.
- Word: `../poi/SimpleMacro.docm`, Apache-2.0; its LICENSE/NOTICE and provenance
  are retained in `../poi/`.

Do not open these macro-bearing inputs in Office. Tests never execute VBA;
client checks open only verified macro-free outputs. Run
`python tests/business_regression.py` after the Native build, then
`python tests/independent_business.py` for independent ZIP/XML checks.
