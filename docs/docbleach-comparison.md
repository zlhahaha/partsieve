# DocBleach reference and PartSieve scope

Reviewed 2026-10-22; source and scope rechecked 2026-11-10. Reference: [DocBleach](https://github.com/docbleach/DocBleach),
MIT, copyright 2017 Maxime Guerreiro, source revision
[`a42309704108719dfb308783cd36ab363d185450`](https://github.com/docbleach/DocBleach/tree/a42309704108719dfb308783cd36ab363d185450).
The repository is archived. It is a functional reference, not an oracle for
document safety or a runtime dependency.

Reviewed `module/module-office/src/main/java/xyz/docbleach/module/ooxml/`
`OOXMLBleach.java`, `ContentTypes.java` and `Relations.java`. No Java code or
fixtures from that project are copied into PartSieve. The implementation uses
the existing MoonBit ZIP/XML graph and verifier; it does not invoke Java/POI.

| Concern | DocBleach source behavior | PartSieve 0.8.0-spike content profile |
| --- | --- | --- |
| VBA | Filters VBA types/relationships; remaps macro main types | Removes supported Word/spreadsheet VBA ownership sets and converts main types; verifies actual output |
| Normal content | General OPC processing through Apache POI; aims to retain ordinary content | Explicitly tested business spreadsheet content and Word tables, inline PNG/JPEG, headers/footers; other content refuses |
| External references | Whitelists hyperlink relationship type, replaces other external relations with a dummy internal object | Preserves source-bound HTTP(S) click hyperlinks; removes one settings-local HTTP(S) attached template and its XML reference; other external resources refuse; no target fetched |
| OLE/ActiveX | Blacklists types/relations and substitutes a dummy target | Removes up to 32 independent validated inline Word embedded OLE objects, exclusively owned CFB payload and PNG/JPEG/EMF preview; Excel OLE, linked/shared OLE and ActiveX still refuse |
| Formats | Includes other Office types and separate modules for other formats | DOCX/DOCM, XLSX/XLSM only; no PDF/RTF/legacy binary/PPTX |
| Unsupported input | Some invalid-format handling copies through | Explicit unsupported/incomplete result with no successful rebuilt pair |
| DDE / external data | Calls `OOXMLTagHelper.removeExternalDataTagAndDDE` during OOXML processing | Formula/DDE and external-workbook input refuses; no claim to clean these inputs |

This version focuses on the review's requested ordinary-content coverage.
Word OLE support is deliberately bounded: the object and its private preview are lost; unrelated content is checked against the original. General OLE and ActiveX remain future work. We do
not claim feature parity or equivalent security with DocBleach.

The main reference is the pinned [OOXMLBleach.java](https://github.com/docbleach/DocBleach/blob/a42309704108719dfb308783cd36ab363d185450/module/module-office/src/main/java/xyz/docbleach/module/ooxml/OOXMLBleach.java):
its relationship whitelist/blacklist, content-type mapping, external-reference
replacement and invalid-format fallback are source behavior, not results of a
head-to-head runtime benchmark. DocBleach's [design description](https://github.com/docbleach/DocBleach/wiki)
prioritizes retaining editable content and layout. PartSieve follows that product
goal within a smaller explicit profile; byte preservation does not prove visual
equivalence or make retained images safe against every client parser exploit.

See the [compatibility matrix](compatibility-matrix.md) for tested features,
validation results and client limitations.

Unreleased main-branch expansion: [bounded Word notes/numbering and common styles](word-structures.md).
This is not part of the published 0.8.0-spike profile. The unchanged initial
20-file POI corpus now supports 7 files and refuses 13. All five files in the
notes and numbering supplement pass rebuilding and Office 2013 validation.
