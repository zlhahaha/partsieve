"""Independent ZIP/XML preservation check: no MoonBit or PartSieve imports."""
from pathlib import Path
import hashlib, json, sys, zipfile
import xml.etree.ElementTree as E
from jsonschema import Draft202012Validator

ROOT=Path(__file__).resolve().parents[1]
DEST=Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'tests/generated/business-v3'
W='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
REL='http://schemas.openxmlformats.org/package/2006/relationships'
reports=[]
for name,suffix in [('report-1900','.xlsx'),('report-1904','.xlsx'),('report-inline','.xlsx'),('document-layout','.docx'),('document-template','.docx')]:
    source=ROOT/'tests/fixtures/business'/(name+('.xlsm' if suffix=='.xlsx' else '.docm'))
    output=DEST/(name+suffix)
    saved=json.loads(output.with_suffix('.receipt.json').read_text(encoding='utf8'))
    Draft202012Validator(json.loads((ROOT/'docs/receipt-v2.schema.json').read_text(encoding='utf8'))).validate(saved)
    with zipfile.ZipFile(source) as z,zipfile.ZipFile(output) as out:
        assert z.testzip() is None and out.testzip() is None
        before={n:z.read(n) for n in z.namelist()};after={n:out.read(n) for n in out.namelist()}
    prefix='xl' if suffix=='.xlsx' else 'word'
    removed={prefix+'/vbaProject.bin'}
    metadata={'[Content_Types].xml',prefix+'/_rels/'+('workbook' if suffix=='.xlsx' else 'document')+'.xml.rels'}
    changed={'word/settings.xml','word/_rels/settings.xml.rels'} if name=='document-template' else set()
    assert set(after)==set(before)-removed
    for part in before.keys()-removed-metadata-changed:assert before[part]==after[part],part
    for part,data in after.items():
        if part.endswith(('.xml','.rels')):
            node=E.fromstring(data)
            if part.endswith('.rels'):
                assert all(r.attrib['TargetMode']=='Internal' if 'TargetMode' in r.attrib else True for r in node)
                assert all('vbaProject' not in r.attrib['Type'] and 'attachedTemplate' not in r.attrib['Type'] for r in node)
    for part in metadata-{'[Content_Types].xml'}:
        wanted=[r.attrib for r in E.fromstring(before[part]) if not r.attrib['Type'].endswith('/vbaProject')]
        assert [r.attrib for r in E.fromstring(after[part])]==wanted
    types=E.fromstring(after['[Content_Types].xml'])
    assert all('macroEnabled' not in t.attrib['ContentType'] and 'vbaProject' not in t.attrib['ContentType'] for t in types)
    if name=='document-template':
        original=E.fromstring(before['word/settings.xml']);actual=E.fromstring(after['word/settings.xml'])
        for node in list(original):
            if node.tag=='{'+W+'}attachedTemplate':original.remove(node)
        assert E.tostring(original)==E.tostring(actual)
        assert len(E.fromstring(after['word/_rels/settings.xml.rels']))==0
    reports.append({'name':name,'status':'Pass','sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'preserved':len(before)-len(removed|metadata|changed)})
print(json.dumps({'tool':'CPython zipfile + ElementTree; independent of SDK','reports':reports},indent=2))
