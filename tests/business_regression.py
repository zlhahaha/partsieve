"""Public-host integration and adversarial tests for the business profiles.

Fixtures are synthetic integration documents with explicit provenance. These
checks are not third-party adoption or claims of arbitrary Office support.
"""
from copy import deepcopy
import hashlib, json, subprocess, sys, zipfile
from pathlib import Path
import xml.etree.ElementTree as E
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tests/fixtures/business'
DEST = ROOT / 'tests/generated/business-v3'
DEST.mkdir(parents=True, exist_ok=True)
CLI = ROOT / 'tools/partsieve.py'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
S = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
A = 'http://schemas.openxmlformats.org/drawingml/2006/main'
checks, outputs = [], []
validator = Draft202012Validator(json.loads((ROOT/'docs/receipt-v2.schema.json').read_text(encoding='utf-8')))

def call(command, path, *args):
    process = subprocess.run([sys.executable, str(CLI), command, str(path), *map(str,args)],
                             capture_output=True, text=True, cwd=ROOT, timeout=90)
    try: report=json.loads(process.stdout)
    except ValueError: raise AssertionError((process.returncode,process.stdout,process.stderr))
    return process.returncode,report
def parts(path):
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
        return {n:archive.read(n) for n in archive.namelist()}
def write(name, data):
    path=DEST/(name+'.zip')
    with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED) as z:
        for n,b in data.items():z.writestr(n,b)
    return path
def check(name): checks.append({'name':name,'status':'Pass'})
def rebuild(name,path,suffix,prepared=True):
    out,receipt=DEST/(name+suffix),DEST/(name+'.receipt.json')
    out.unlink(missing_ok=True);receipt.unlink(missing_ok=True)
    args=[]
    if prepared:
        code,plan=call('prepare',path);assert code==0,(name,plan)
        saved=DEST/(name+'.plan.json');saved.write_text(json.dumps(plan),encoding='utf-8');args=['--plan',saved]
    code,report=call('rebuild',path,'--receipt-format','v2','-o',out,'--receipt',receipt,*args)
    assert code==0 and report['result']=='Pass',(name,report)
    validator.validate(json.loads(receipt.read_text(encoding='utf-8')))
    assert call('verify',out,'--original',path,'--receipt',receipt,'--receipt-format','v2')==(0,report)
    original,actual=parts(path),parts(out)
    assert len(report['dispositions'])==len(original)
    assert not report['output_findings']
    for d in report['dispositions']:
        if d['classification']=='BytePreserved':assert actual[d['part']]==original[d['part']]
    check(name+' saved-plan rebuild, actual file verification and all-part preservation')
    return out,report
def refused(name,data):
    path=write(name,data);out=DEST/(name+'.docx');receipt=DEST/(name+'.receipt.json')
    out.unlink(missing_ok=True);receipt.unlink(missing_ok=True)
    code,report=call('rebuild',path,'-o',out,'--receipt',receipt,'--receipt-format','v2')
    assert code in (2,3) and not out.exists() and not receipt.exists(),(name,code,report)
    check(name+' refuses with no successful output pair')

manifest=json.loads((SOURCE/'provenance.json').read_text(encoding='utf-8'))
for name,expected in manifest['files'].items():assert hashlib.sha256((SOURCE/name).read_bytes()).hexdigest()==expected
check('pinned business fixture hashes and declared provenance')

for name in ['report-1900','report-1904','report-inline']:
    path=SOURCE/(name+'.xlsm');out,report=rebuild(name,path,'.xlsx');outputs.append(out)
    data=parts(out);book=E.fromstring(data['xl/workbook.xml'])
    assert [n.attrib['name'] for n in book.find('{'+S+'}sheets')]==['销售明细','部门汇总','交付说明']
    assert book.find('{'+S+'}workbookPr').attrib.get('date1904','0')==('1' if name=='report-1904' else '0')
    sheet=E.fromstring(data['xl/worksheets/sheet1.xml']);cells={n.attrib['r']:n for n in sheet.findall('.//{'+S+'}c')}
    assert float(cells['C3'].find('{'+S+'}v').text)==1234.5
    assert cells['B3'].find('{'+S+'}v').text==('44855' if name=='report-1904' else '46317')
    if name=='report-inline':assert cells['A3'].find('.//{'+S+'}t').text=='订单 A'
    else:
        strings=E.fromstring(data['xl/sharedStrings.xml']);index=int(cells['A3'].find('{'+S+'}v').text)
        assert ''.join(strings[index].itertext())=='订单 A'
    styles=E.fromstring(data['xl/styles.xml']);formats=styles.find('{'+S+'}numFmts')
    assert any(n.attrib['formatCode']=='yyyy-mm-dd' for n in formats)
    assert any(n.attrib['formatCode']=='#,##0.00' for n in formats)
    check(name+' Chinese text, amounts, date system, three sheets and custom formats')
    rebuild(name+'-clean',out,'.xlsx')

for name in ['document-layout','document-template']:
    path=SOURCE/(name+'.docm');out,report=rebuild(name,path,'.docx');outputs.append(out)
    data=parts(out);document=E.fromstring(data['word/document.xml'])
    assert len(document.findall('.//{'+W+'}tbl'))==1
    assert len(document.findall('.//{'+W+'}gridSpan'))==1
    assert len(document.findall('.//{'+W+'}headerReference'))==2
    assert len(document.findall('.//{'+W+'}footerReference'))==2
    assert len(document.findall('.//{'+A+'}blip'))==1
    assert b'https://example.invalid' not in b''.join(data.values())
    if name=='document-template':
        settings=E.fromstring(data['word/settings.xml'])
        assert [n.tag for n in settings]==['{'+W+'}zoom','{'+W+'}defaultTabStop']
        assert settings[0].attrib['{'+W+'}percent']=='100'
        assert settings[1].attrib['{'+W+'}val']=='720'
        assert any(d['part']=='word/settings.xml' and d['classification']=='SemanticallyRewritten' for d in report['dispositions'])
        assert any(f['capability']=='RemoteTemplate' and f['rebuild_support']=='Supported' for f in report['findings'])
    check(name+' tables, merged cells, PNG/JPEG, two section-local headers/footers and template policy')
    rebuild(name+'-clean',out,'.docx')

base=parts(SOURCE/'report-1900.xlsm')
changed=deepcopy(base);changed['xl/_rels/workbook.xml.rels']=changed['xl/_rels/workbook.xml.rels'].replace(b'Target="worksheets/sheet2.xml"',b'Target="worksheets/sheet1.xml"');refused('duplicate-worksheet-target',changed)
for name,part,old,new in [
    ('bad-string-index','xl/worksheets/sheet1.xml',b'<v>0</v>',b'<v>999999</v>'),
    ('bad-style-index','xl/worksheets/sheet1.xml',b's="1"',b's="999999"'),
    ('formula-still-refused','xl/worksheets/sheet1.xml',b'<v>1234.5</v>',b'<f>1+1</f><v>2</v>'),
]:
    changed=deepcopy(base);assert old in changed[part];changed[part]=changed[part].replace(old,new);refused(name,changed)

base=parts(SOURCE/'document-layout.docm')
for name,part,old,new in [
    ('image-wrong-source-id','word/header1.xml',b'rLogo',b'missing'),
    ('header-wrong-kind','word/_rels/document.xml.rels',b'/header"',b'/image"'),
    ('image-external-link','word/document.xml',b'r:embed=',b'r:link='),
    ('image-no-reference','word/document.xml',b'r:embed="rImage"',b''),
    ('svg-not-opened','word/document.xml',b'xmlns:a="'+A.encode()+b'"',b'xmlns:a="urn:unsupported"'),
    ('bad-image-signature','word/media/logo.png',b'\x89PNG',b'BAD!'),
    ('word-field-still-refused','word/document.xml',b'<w:t>',b'<w:fldChar w:fldCharType="begin"/><w:t>'),
]:
    changed=deepcopy(base);assert old in changed[part];changed[part]=changed[part].replace(old,new);refused(name,changed)
base=parts(SOURCE/'document-template.docm')
for name,old,new in [
    ('template-unknown-id',b'r:id="rRemote"',b'r:id="unknown"'),
    ('template-no-id',b'r:id="rRemote"',b'w:val="https://example.invalid/evil"'),
    ('template-wrong-placement',b'<w:attachedTemplate',b'<w:other'),
]:
    changed=deepcopy(base);changed['word/settings.xml']=changed['word/settings.xml'].replace(old,new);refused(name,changed)
changed=deepcopy(base);changed['word/_rels/settings.xml.rels']=changed['word/_rels/settings.xml.rels'].replace(b'https://example.invalid/template.dotm',b'file:///C:/template.dotm');refused('template-file-scheme',changed)
changed=deepcopy(base);changed['word/settings.xml']=changed['word/settings.xml'].replace(b'<w:attachedTemplate r:id="rRemote" />',b'<w:attachedTemplate r:id="rRemote"></w:attachedTemplate>')
rebuild('template-explicit-end',write('template-explicit-end',changed),'.docx')
changed=deepcopy(base);changed['word/settings.xml']=changed['word/settings.xml'].replace(b'<w:attachedTemplate',b'<z:attachedTemplate xmlns:z="'+W.encode()+b'"');rebuild('template-alternate-prefix',write('template-alternate-prefix',changed),'.docx')
changed=deepcopy(base)
changed.pop('word/vbaProject.bin')
changed['word/_rels/document.xml.rels']=changed['word/_rels/document.xml.rels'].replace(b'<Relationship Id="rVba" Type="http://schemas.microsoft.com/office/2006/relationships/vbaProject" Target="vbaProject.bin" />',b'')
changed['[Content_Types].xml']=changed['[Content_Types].xml'].replace(b'application/vnd.ms-word.document.macroEnabled.main+xml',b'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml').replace(b'<Override PartName="/word/vbaProject.bin" ContentType="application/vnd.ms-office.vbaProject" />',b'')
rebuild('template-only-docx',write('template-only-docx',changed),'.docx')
changed=deepcopy(base);changed['word/settings.xml']=changed['word/settings.xml'].replace(b'<w:zoom',b'<!-- keep -->\n<w:zoom')
rebuild('template-comment-whitespace',write('template-comment-whitespace',changed),'.docx')
changed=parts(outputs[-1]);changed['word/media/logo.jpg']+=b'TAMPER'
tampered=write('tampered-image-output',changed)
code,report=call('verify',tampered,'--original',SOURCE/'document-template.docm','--receipt-format','v2')
assert code==2,(code,report);check('changed preserved image output fails independent verification')
changed=parts(outputs[-1]);changed['word/settings.xml']=changed['word/settings.xml'].replace(b'100',b'101')
code,report=call('verify',write('tampered-settings-output',changed),'--original',SOURCE/'document-template.docm','--receipt-format','v2')
assert code==2,(code,report);check('changed unrelated settings fail source XML preservation verification')
legacy_out,legacy_receipt=DEST/'template-legacy.docx',DEST/'template-legacy.receipt.json'
legacy_out.unlink(missing_ok=True);legacy_receipt.unlink(missing_ok=True)
code,legacy=call('rebuild',SOURCE/'document-template.docm','-o',legacy_out,'--receipt',legacy_receipt)
assert code==0,legacy
Draft202012Validator(json.loads((ROOT/'docs/word-receipt.schema.json').read_text(encoding='utf-8'))).validate(json.loads(legacy_receipt.read_text(encoding='utf-8')))
assert call('verify',legacy_out,'--original',SOURCE/'document-template.docm','--receipt',legacy_receipt)==(0,legacy)
check('legacy Word report schema and recomputation support the accepted template rewrite')
summary={'status':'Pass','checks':checks,'outputs':[str(p.relative_to(ROOT)) for p in outputs],'scope':'Synthetic combination fixtures; native SDK/host and independent byte assertions, client/schema checks recorded separately.'}
(ROOT/'docs/evidence/business-regression.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'status':'Pass','business_assertions':len(checks),'outputs':len(outputs)}))
