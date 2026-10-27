"""Build a bundled Korean-only supplement; keep Wiktionary and MPL data separate.
Usage: python3 scripts/package_offline_dictionary.py /path/to/kengdic.tsv
Source revision and license details are recorded in dictionary/NOTICE.md.
"""
import csv, hashlib, json, re, sys
from collections import Counter, defaultdict
from pathlib import Path
root=Path(__file__).resolve().parent.parent/'dictionary'
source=Path(sys.argv[1])
if hashlib.sha256(source.read_bytes()).hexdigest()!='d23236d5676f506514721e605534647ba4735a85bbb76b9e12d1ec067b8cfdb4': raise SystemExit('Use kengdic.tsv from pinned revision 793de2369c9a98b944154eb4695d26854d2de59b')
core=json.loads((root/'core-ko.json').read_text())
core={k:v for k,v in core.items() if len(v)>3 and v[3]=='ko' and re.search('[가-힣]',v[2]) and not re.search(r'뜻풀이를?\s*추가|이\s*틀|rfdety|한국어 뜻풀이가 필요|사전Name|번역을 추가|정의가 필요|뜻을 확인하는|불러오는 중|사전에서 뜻',v[2],re.I)}
(root/'core-ko.json').write_text(json.dumps(core,ensure_ascii=False,separators=(',',':'))+'\n')
entries=defaultdict(set); rejected=Counter()
# Known source errors: do not introduce these senses as offline definitions.
blocked={'uptime': 'The source gloss contains an incorrect Korean translation.'}
for row in csv.DictReader(source.open(encoding='utf-8'),delimiter='\t'):
    en=row['gloss'].strip(); ko=re.sub(r'\s+',' ',row['surface']).strip()
    if not re.fullmatch(r"[a-z]+(?:['-][a-z]+)*",en) or len(en)>60:
        rejected['phrase_name_or_nonword']+=1; continue
    if en in core: rejected['existing_wiktionary_preferred']+=1; continue
    if en in blocked: rejected['known_source_error']+=1; continue
    if not re.search('[가-힣]',ko) or re.search(r'[A-Za-z<>{}\\\[\]]',ko) or len(ko)>140:
        rejected['invalid_or_mixed_definition']+=1; continue
    if en!='white' and ko=='흰색': rejected['known_source_error']+=1; continue
    entries[en].add(ko)
supplement={word:['','','; '.join(sorted(meanings,key=lambda s:(len(s),s))[:4]),'ko','kengdic'] for word,meanings in sorted(entries.items())}
def write(name,value):
    (root/name).write_text(json.dumps(value,ensure_ascii=False,separators=(',',':'))+'\n')
write('kengdic-ko.json',supplement)
files={name:{'sha256':hashlib.sha256((root/name).read_bytes()).hexdigest(),'bytes':(root/name).stat().st_size} for name in ['core-ko.json','kengdic-ko.json']}
version=hashlib.sha256(json.dumps(files,sort_keys=True).encode()).hexdigest()
write('offline-manifest.json',{'version':version,'entries':len(core)+len(supplement),'coreEntries':len(core),'supplementEntries':len(supplement),'files':files,'sources':{'kengdic':{'revision':'793de2369c9a98b944154eb4695d26854d2de59b','sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'license':'MPL-2.0'}},'excludedRows':dict(rejected)})
print(json.dumps({'core':len(core),'additional':len(supplement),'total':len(core)+len(supplement),'bytes':sum(f['bytes'] for f in files.values()),'excludedRows':dict(rejected)},ensure_ascii=False))

previous=json.loads((root/'manifest.json').read_text())
sources=previous.get('sources',{})
wiktionary=sources.get('wiktionary') or {k:v for k,v in sources.items() if k in ('ko','en')}
write('manifest.json',{'entries':len(core)+len(supplement),'koreanEntries':len(core)+len(supplement),'coreEntries':len(core),'supplementEntries':len(supplement),'shards':0,'bytes':sum(f['bytes'] for f in files.values()),'licenses':{'core-ko.json':'CC-BY-SA-4.0','kengdic-ko.json':'MPL-2.0'},'sources':{'wiktionary':wiktionary,'kengdic':{'source':'https://github.com/garfieldnate/kengdic','revision':'793de2369c9a98b944154eb4695d26854d2de59b','sha256':hashlib.sha256(source.read_bytes()).hexdigest()}}})
