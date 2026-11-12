"""Independent ZIP/XML preservation check: no MoonBit or PartSieve imports."""
from pathlib import Path
import hashlib, json, sys, zipfile, argparse, posixpath
import xml.etree.ElementTree as E
from datetime import date, timedelta
from jsonschema import Draft202012Validator

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('directory',nargs='?',type=Path,default=ROOT/'tests/generated/business-v3')
parser.add_argument('--next',dest='next_dir',type=Path)
parser.add_argument('--word-modern',type=Path)
options=parser.parse_args()
DEST=options.directory
W='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
REL='http://schemas.openxmlformats.org/package/2006/relationships'
S='http://schemas.openxmlformats.org/spreadsheetml/2006/main'
R='http://schemas.openxmlformats.org/officeDocument/2006/relationships'
NS={'s':S,'w':W,'a':'http://schemas.openxmlformats.org/drawingml/2006/main'}

def related_part(parts, owner, relation_id, kind):
    """Resolve in the owning part's relationship scope, not by global rId."""
    rels=posixpath.join(posixpath.dirname(owner),'_rels',posixpath.basename(owner)+'.rels')
    matches=[r for r in E.fromstring(parts[rels]) if r.attrib['Id']==relation_id]
    assert len(matches)==1,(owner,relation_id)
    rel=matches[0]
    assert rel.attrib['Type']==R+'/'+kind and rel.attrib.get('TargetMode','Internal')=='Internal'
    target=rel.attrib['Target']
    resolved=posixpath.normpath(target.lstrip('/') if target.startswith('/') else posixpath.join(posixpath.dirname(owner),target))
    assert resolved in parts,(owner,resolved)
    return resolved

def spreadsheet_features(parts, name):
    """Fixed fixture expectations prevent an empty input/output pair passing."""
    book=E.fromstring(parts['xl/workbook.xml'])
    sheets=book.findall('s:sheets/s:sheet',NS)
    assert [s.attrib['name'] for s in sheets]==['销售明细','部门汇总','交付说明']
    system=book.find('s:workbookPr',NS).attrib.get('date1904','0')
    assert system==('1' if name=='report-1904' else '0')
    strings=[]
    if name!='report-inline':
        strings=[''.join(si.itertext()) for si in E.fromstring(parts['xl/sharedStrings.xml'])]
    styles=E.fromstring(parts['xl/styles.xml'])
    formats={n.attrib['numFmtId']:n.attrib['formatCode'] for n in styles.findall('s:numFmts/s:numFmt',NS)}
    xfs=styles.findall('s:cellXfs/s:xf',NS)
    fonts=styles.findall('s:fonts/s:font',NS)
    fills=styles.findall('s:fills/s:fill',NS)
    borders=styles.findall('s:borders/s:border',NS)
    observed=[]
    for index,sheet in enumerate(sheets):
        path=related_part(parts,'xl/workbook.xml',sheet.attrib['{'+R+'}id'],'worksheet')
        tree=E.fromstring(parts[path])
        cells={c.attrib['r']:c for c in tree.findall('s:sheetData/s:row/s:c',NS)}
        def text(ref):
            c=cells[ref]
            assert c.attrib['t']==('inlineStr' if name=='report-inline' else 's')
            return ''.join(c.find('s:is',NS).itertext()) if name=='report-inline' else strings[int(c.findtext('s:v',namespaces=NS))]
        assert text('A1')==sheet.attrib['name'] and text('A2')=='项目 / Item'
        assert text('A3')==['订单 A','研发','测试用途'][index]
        assert cells['A5' if index==0 else 'A4'].attrib['t']=='b'
        assert cells['A5' if index==0 else 'A4'].findtext('s:v',namespaces=NS)=='1'
        serial=int(cells['B3'].findtext('s:v',namespaces=NS))
        # These fixtures use modern dates, beyond Excel's fictitious 1900-02-29.
        actual_date=(date(1904,1,1) if system=='1' else date(1899,12,30))+timedelta(days=serial)
        assert actual_date==date(2026,10,22)
        assert formats[xfs[int(cells['B3'].attrib['s'])].attrib['numFmtId']]=='yyyy-mm-dd'
        assert cells['C3'].findtext('s:v',namespaces=NS)==['1234.5','1214.25','0'][index]
        assert formats[xfs[int(cells['C3'].attrib['s'])].attrib['numFmtId']]=='#,##0.00'
        heading=xfs[int(cells['A1'].attrib['s'])]
        assert fonts[int(heading.attrib['fontId'])].find('s:b',NS) is not None
        assert fonts[int(heading.attrib['fontId'])].find('s:color',NS).attrib['rgb']=='FFFFFFFF'
        assert fills[int(heading.attrib['fillId'])].find('s:patternFill/s:fgColor',NS).attrib['rgb']=='FF25476A'
        assert heading.find('s:alignment',NS).attrib['horizontal']=='center'
        body=xfs[int(cells['A3'].attrib['s'])]
        assert borders[int(body.attrib['borderId'])].find('s:left',NS).attrib['style']=='thin'
        assert body.find('s:alignment',NS).attrib['wrapText']=='1'
        assert [m.attrib['ref'] for m in tree.findall('s:mergeCells/s:mergeCell',NS)]==['A1:C1']
        observed.append({'name':sheet.attrib['name'],'date':actual_date.isoformat(),'date_serial':serial})
    return {'sheets':observed,'date_system':'1904' if system=='1' else '1900',
            'text_storage':'inline' if name=='report-inline' else 'shared',
            'checked':['Chinese/English text','numeric amounts','booleans','date format','font/color/fill','border/alignment/wrap','merged cells']}

def word_features(parts):
    document=E.fromstring(parts['word/document.xml'])
    tables=document.findall('.//w:tbl',NS)
    assert len(tables)==1 and len(tables[0].findall('w:tr',NS))==4
    assert tables[0].find('.//w:gridSpan',NS).attrib['{'+W+'}val']=='3'
    assert '保留表格和图片' in ''.join(tables[0].itertext())
    sections=document.findall('.//w:sectPr',NS)
    assert len(sections)==2
    owners=['word/document.xml']
    for index,section in enumerate(sections,1):
        for kind,label in [('header','页眉'),('footer','页脚')]:
            refs=section.findall('w:'+kind+'Reference',NS)
            assert len(refs)==1
            part=related_part(parts,'word/document.xml',refs[0].attrib['{'+R+'}id'],kind)
            owners.append(part)
            assert ''.join(E.fromstring(parts[part]).itertext())==label+' / '+kind+str(index)
    assert len(set(owners))==5
    images=[]
    for owner in owners:
        blips=E.fromstring(parts[owner]).findall('.//a:blip',NS)
        assert len(blips)==1,(owner,'expected inline image')
        part=related_part(parts,owner,blips[0].attrib['{'+R+'}embed'],'image')
        data=parts[part]
        assert data.startswith(b'\x89PNG\r\n\x1a\n') or data.startswith(b'\xff\xd8\xff')
        images.append({'owner':owner,'part':part,'sha256':hashlib.sha256(data).hexdigest()})
    assert {posixpath.splitext(i['part'])[1] for i in images}=={'.png','.jpg'}
    return {'tables':1,'table_rows':4,'merged_columns':3,'sections':2,'headers':2,'footers':2,'image_references':images}

reports=[]
def word_note_features(parts):
    document=E.fromstring(parts['word/document.xml'])
    descriptions={}
    for plural,singular,nid,text in [('footnotes','footnote','2','脚注：订单金额按原始值保留。'),('endnotes','endnote','3','尾注：本文件用于可复现验收。')]:
        assert [r.attrib['{'+W+'}id'] for r in document.findall('.//w:'+singular+'Reference',NS)]==[nid]
        definition_nodes=list(E.fromstring(parts['word/'+plural+'.xml']))
        assert len(definition_nodes)==3
        defs={n.attrib['{'+W+'}id']:n for n in definition_nodes}
        assert set(defs)=={'-1','0',nid}
        assert defs['-1'].attrib['{'+W+'}type']=='separator'
        assert defs['0'].attrib['{'+W+'}type']=='continuationSeparator'
        assert ''.join(defs[nid].itertext())==text
        assert defs[nid].find('.//w:'+singular+'Ref',NS) is not None
        descriptions[plural]={'normal_id':nid,'text':text,'separator_ids':['-1','0']}
    num=E.fromstring(parts['word/numbering.xml'])
    abstract=num.find('w:abstractNum',NS)
    assert len(num.findall('w:abstractNum',NS))==len(num.findall('w:num',NS))==1
    assert abstract.attrib['{'+W+'}abstractNumId']=='0'
    assert [n.attrib['{'+W+'}ilvl'] for n in abstract.findall('w:lvl',NS)]==['0','1']
    assert [n.find('w:numFmt',NS).attrib['{'+W+'}val'] for n in abstract.findall('w:lvl',NS)]==['decimal','decimal']
    assert [n.find('w:lvlText',NS).attrib['{'+W+'}val'] for n in abstract.findall('w:lvl',NS)]==['%1.','%1.%2.']
    instance=num.find('w:num',NS)
    assert instance.attrib['{'+W+'}numId']=='7'
    assert instance.find('w:abstractNumId',NS).attrib['{'+W+'}val']=='0'
    assert instance.find('w:lvlOverride/w:startOverride',NS).attrib['{'+W+'}val']=='3'
    assert instance.find('w:lvlOverride',NS).attrib['{'+W+'}ilvl']=='0'
    refs=document.findall('.//w:numPr',NS)
    assert [r.find('w:numId',NS).attrib['{'+W+'}val'] for r in refs]==['7','7']
    assert [r.find('w:ilvl',NS).attrib['{'+W+'}val'] for r in refs]==['0','1']
    assert '订单 A：1234.50' in ''.join(document.itertext())
    style=E.fromstring(parts['word/styles.xml']).find('w:style',NS)
    assert style.attrib['{'+W+'}styleId']=='Heading1'
    assert style.find('w:pPr/w:outlineLvl',NS).attrib['{'+W+'}val']=='0'
    descriptions['numbering']={'num_id':'7','abstract_id':'0','levels':['0','1'],'start_override':3}
    return descriptions

for name,suffix in [('report-1900','.xlsx'),('report-1904','.xlsx'),('report-inline','.xlsx'),('document-layout','.docx'),('document-template','.docx'),('document-notes-lists','.docx')]:
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
    features=spreadsheet_features(after,name) if suffix=='.xlsx' else word_note_features(after) if name=='document-notes-lists' else word_features(after)
    receipt=saved['receipt']
    assert receipt['input_hash']==hashlib.sha256(source.read_bytes()).hexdigest()
    assert receipt['output_hash']==hashlib.sha256(output.read_bytes()).hexdigest()
    reports.append({'name':name,'status':'Pass','sha256':receipt['output_hash'],'preserved':len(before)-len(removed|metadata|changed),'features':features})
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
if options.word_modern:
    pinned=json.loads((ROOT/'tests/external/poi-notes-numbering-manifest.json').read_text(encoding='utf8'))
    baseline=json.loads((ROOT/'tests/external/poi-manifest.json').read_text(encoding='utf8'))
    cases=pinned['cases']+[case for case in baseline['cases']
                           if case['name'] in ('TestTableCellAlign.docx','headerPic.docx')]
    mc='{http://schemas.openxmlformats.org/markup-compatibility/2006}'
    for case in cases:
        name=case['name']
        source=ROOT/'tests/fixtures/poi/word-modern'/name
        output=options.word_modern/name
        saved=json.loads(output.with_suffix('.receipt.json').read_text(encoding='utf8'))
        Draft202012Validator(json.loads((ROOT/'docs/receipt-v2.schema.json').read_text(encoding='utf8'))).validate(saved)
        receipt=saved['receipt']
        assert hashlib.sha256(source.read_bytes()).hexdigest()==case['sha256']==receipt['input_hash']
        assert hashlib.sha256(output.read_bytes()).hexdigest()==case['sha256']==receipt['output_hash']
        with zipfile.ZipFile(source) as a, zipfile.ZipFile(output) as b:
            assert a.testzip() is None and b.testzip() is None
            before={p:a.read(p) for p in a.namelist()}
            after={p:b.read(p) for p in b.namelist()}
        assert before==after and not receipt['output_findings']
        document=E.fromstring(after['word/document.xml'])
        facts={}
        if name in ('footnotes.docx','endnotes.docx'):
            kind=name[:-6]
            refs=document.findall('.//w:'+kind+'Reference',NS)
            definitions=E.fromstring(after['word/'+kind+'s.xml'])
            ids={n.attrib['{'+W+'}id']:n for n in definitions if n.get('{'+W+'}type','normal')=='normal'}
            assert len(refs)==1 and len(ids)==1
            note=ids[refs[0].attrib['{'+W+'}id']]
            assert ''.join(note.itertext()).strip()
            facts[kind+'_references']=len(refs)
        elif name=='TestTableCellAlign.docx':
            style_id=document.find('.//w:tbl/w:tblPr/w:tblStyle',NS).attrib['{'+W+'}val']
            styles=E.fromstring(after['word/styles.xml'])
            style=next(s for s in styles.findall('w:style',NS)
                       if s.get('{'+W+'}styleId')==style_id)
            assert style.get('{'+W+'}type')=='table'
            edges=list(style.find('w:tblPr/w:tblBorders',NS))
            assert [edge.tag.rsplit('}',1)[1] for edge in edges]==[
                'top','left','bottom','right','insideH','insideV']
            assert all(edge.get('{'+W+'}val')=='single' for edge in edges)
            rows=document.findall('.//w:tbl/w:tr',NS)
            assert len(rows)==2 and all(len(row.findall('w:tc',NS))==2 for row in rows)
            facts.update(style=style_id, table_rows=len(rows), single_line_edges=len(edges))
        elif name=='headerPic.docx':
            drawing='{http://schemas.openxmlformats.org/drawingml/2006/main}'
            picture='{http://schemas.openxmlformats.org/drawingml/2006/picture}'
            relation='{http://schemas.openxmlformats.org/officeDocument/2006/relationships}'
            header=E.fromstring(after['word/header1.xml'])
            link=header.find('.//'+drawing+'blip').attrib[relation+'embed']
            rels=E.fromstring(after['word/_rels/header1.xml.rels'])
            bound=[r for r in rels if r.get('Id')==link]
            assert len(bound)==1 and bound[0].get('Type').endswith('/image')
            assert bound[0].get('TargetMode','Internal')=='Internal'
            assert bound[0].get('Target')=='media/image1.jpeg'
            image=after['word/media/image1.jpeg']
            assert image.startswith(b'\xff\xd8\xff')
            assert header.find('.//'+drawing+'srcRect').attrib=={}
            shape=header.find('.//'+picture+'spPr')
            assert shape.get('bwMode')=='auto'
            assert shape.find(drawing+'ln/'+drawing+'noFill') is not None
            facts.update(header='word/header1.xml', image_sha256=hashlib.sha256(image).hexdigest())
        else:
            number=E.fromstring(after['word/numbering.xml'])
            counts=(len(number.findall('w:abstractNum',NS)),len(number.findall('w:num',NS)),len(number.findall('.//w:lvlOverride',NS)))
            assert counts=={'Numbering.docx':(5,5,0),'NumberingWOverrides.docx':(36,37,9),'NumberingWithOutOfOrderId.docx':(1,1,0)}[name]
            facts.update(abstracts=counts[0],instances=counts[1],overrides=counts[2])
            if name=='Numbering.docx':
                alternates=list(number.iter(mc+'AlternateContent'))
                assert len(alternates)==1
                assert alternates[0].find(mc+'Choice/{'+W+'}numFmt').attrib['{'+W+'}val']=='custom'
                assert alternates[0].find(mc+'Fallback/{'+W+'}numFmt').attrib['{'+W+'}val']=='decimal'
                facts['number_format_branches']=['custom','decimal']
        reports.append({'name':name,'status':'Pass','sha256':case['sha256'],'byte_identical_parts':len(after),'features':facts})
print(json.dumps({'tool':'CPython zipfile + ElementTree + JSON Schema; independent of SDK','reports':reports},indent=2))
