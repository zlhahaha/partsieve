"""Independent ZIP/XML preservation check: no MoonBit or PartSieve imports."""
from pathlib import Path
import hashlib, json, sys, zipfile, argparse, posixpath
import xml.etree.ElementTree as E
from jsonschema import Draft202012Validator

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('directory',nargs='?',type=Path,default=ROOT/'tests/generated/business-v3')
parser.add_argument('--next',dest='next_dir',type=Path)
options=parser.parse_args()
DEST=options.directory
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
if options.next_dir:
    def remove_keep_tail(parent,node):
        items=list(parent);index=items.index(node);tail=node.tail
        parent.remove(node)
        if tail:
            if index:items[index-1].tail=(items[index-1].tail or '')+tail
            else:parent.text=(parent.text or '')+tail
    for name,suffix in [('word-links','.docx'),('sheet-links','.xlsx'),('word-ole-png','.docx'),('word-ole-emf','.docx'),('word-ole-clean','.docx'),('word-ole-only','.docx'),('word-ole-multi2','.docx'),('word-ole-multi3','.docx'),('word-ole-multi32','.docx'),('word-ole-multi-clean','.docx')]:
        folder=options.next_dir
        sources=list(folder.glob(name+'.input.*'))
        assert len(sources)==1,(name,'ambiguous original file')
        source=sources[0]
        output=folder/(name+suffix)
        with zipfile.ZipFile(source) as a,zipfile.ZipFile(output) as b:
            assert a.testzip() is None and b.testzip() is None
            before={n:a.read(n) for n in a.namelist()};after={n:b.read(n) for n in b.namelist()}
        is_word=suffix=='.docx';main='word/document.xml' if is_word else 'xl/workbook.xml'
        vba=('word' if is_word else 'xl')+'/vbaProject.bin'
        removed={vba} if vba in before else set()
        has_ole=name.startswith('word-ole')
        preview_ids=set();ole_payloads=set();object_count=0
        if has_ole:
            original_rels={r.attrib['Id']:r.attrib for r in E.fromstring(before['word/_rels/document.xml.rels'])}
            used_ids=set()
            for obj in E.fromstring(before[main]).iter('{'+W+'}object'):
                ole=list(obj.iter('{urn:schemas-microsoft-com:office:office}OLEObject'))
                preview=list(obj.iter('{urn:schemas-microsoft-com:vml}imagedata'))
                assert len(ole)==len(preview)==1 and ole[0].attrib['Type']=='Embed'
                for node,kind in [(ole[0],'oleObject'),(preview[0],'image')]:
                    rel_id=node.attrib['{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id']
                    assert rel_id not in used_ids
                    used_ids.add(rel_id)
                    rel=original_rels[rel_id]
                    assert rel['Type'].endswith('/'+kind) and rel.get('TargetMode','Internal')=='Internal'
                    target=rel['Target']
                    path=posixpath.normpath(target.lstrip('/') if target.startswith('/') else posixpath.join('word',target))
                    assert path in before and path not in removed
                    removed.add(path)
                    if kind=='image':preview_ids.add(rel_id)
                    else:ole_payloads.add(path)
                object_count+=1
            expected_objects={'word-ole-multi2':2,'word-ole-multi3':3,'word-ole-multi32':32,'word-ole-multi-clean':3}.get(name,1)
            assert object_count==expected_objects
        assert set(after)==set(before)-removed,(name,'part set')
        changed={'[Content_Types].xml'} if removed else set()
        for part,data in before.items():
            if not part.endswith('.rels') or part in removed:continue
            original=E.fromstring(data)
            wanted=[dict(r.attrib) for r in original if not r.attrib['Type'].endswith(('/vbaProject','/attachedTemplate','/oleObject')) and not (part=='word/_rels/document.xml.rels' and r.attrib['Id'] in preview_ids)]
            actual=[dict(r.attrib) for r in E.fromstring(after[part])]
            assert actual==wanted,(name,part,'relation set')
            if len(wanted)!=len(original):changed.add(part)
        expected_main='application/vnd.openxmlformats-officedocument.'+('wordprocessingml.document' if is_word else 'spreadsheetml.sheet')+'.main+xml'
        types=E.fromstring(after['[Content_Types].xml'])
        assert any(t.attrib.get('PartName')=='/'+main and t.attrib['ContentType']==expected_main for t in types)
        assert all('macroEnabled' not in t.attrib['ContentType'] and 'vbaProject' not in t.attrib['ContentType'] and 'oleObject' not in t.attrib['ContentType'] and t.attrib.get('PartName','')[1:] not in removed for t in types)
        if is_word:
            for part,local in [('word/settings.xml','attachedTemplate'),('word/document.xml','object')]:
                original=E.fromstring(before[part]);actual=E.fromstring(after[part])
                deleted=False
                for parent in original.iter():
                    for node in list(parent):
                        if node.tag=='{'+W+'}'+local:
                            remove_keep_tail(parent,node);deleted=True
                assert E.tostring(original)==E.tostring(actual),(name,part,'unrelated semantics')
                if deleted:changed.add(part)
        for part in before.keys()-removed-changed:assert before[part]==after[part],(name,part,'preservation')
        clicks=[]
        for part,data in after.items():
            if not part.endswith('.rels'):continue
            for r in E.fromstring(data):
                if r.attrib['Type'].endswith('/hyperlink'):
                    assert r.attrib.get('TargetMode')=='External'
                    assert r.attrib['Target'].lower().startswith(('http://','https://'))
                    clicks.append(r.attrib['Target'])
        assert len(clicks)==(0 if name=='word-ole-only' else 3 if is_word else 1)
        saved=json.loads((folder/(name+'.receipt.json')).read_text(encoding='utf8'))
        Draft202012Validator(json.loads((ROOT/'docs/receipt-v2.schema.json').read_text(encoding='utf8'))).validate(saved)
        legacy=json.loads((folder/(name+'.legacy.receipt.json')).read_text(encoding='utf8'))
        legacy_schema='word-receipt.schema.json' if is_word else 'receipt.schema.json'
        Draft202012Validator(json.loads((ROOT/'docs'/legacy_schema).read_text(encoding='utf8'))).validate(legacy)
        receipt=saved['receipt']
        assert receipt['input_hash']==hashlib.sha256(source.read_bytes()).hexdigest()
        assert legacy['receipt']['input_hash']==receipt['input_hash'] and legacy['receipt']['output_hash']==receipt['output_hash']
        assert receipt['output_hash']==hashlib.sha256(output.read_bytes()).hexdigest()
        assert sorted(f['part'] for f in receipt['allowed_capabilities'])==sorted(clicks)
        assert {f['part'] for f in receipt['findings'] if f['capability']=='OLE'}==ole_payloads
        assert {d['part'] for d in receipt['dispositions'] if d['classification']=='RemovedByPolicy'}==removed
        assert not receipt['output_findings'] and receipt['independent_validation']=='NotChecked'
        reports.append({'name':name,'status':'Pass','sha256':receipt['output_hash'],'click_links':len(clicks),'ole_objects':object_count,'removed_parts':sorted(removed)})
print(json.dumps({'tool':'CPython zipfile + ElementTree + JSON Schema; independent of SDK','reports':reports},indent=2))
