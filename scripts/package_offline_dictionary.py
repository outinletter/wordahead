"""Generate the small bundled dictionary and content-addressed download index.
Usage: python3 scripts/package_offline_dictionary.py <published-full-git-commit>
The published commit must contain the exact dictionary shard files being indexed.
"""
import hashlib,json,pathlib,re,sys
source=sys.argv[1]
if not re.fullmatch('[0-9a-f]{40}',source): raise SystemExit('A published full commit SHA is required')
root=pathlib.Path(__file__).resolve().parent.parent/'dictionary'
core={};shards={}
for path in sorted(root.glob('??.js')):
    raw=path.read_bytes();text=raw.decode()
    entries=json.loads(text[text.index('{'):text.rfind('}')+1])
    core.update({word:entry for word,entry in entries.items() if len(entry)>3 and entry[3]=='ko'})
    shards[path.stem]={'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw)}
assert len(shards)==256
(root/'core-ko.json').write_text(json.dumps(core,ensure_ascii=False,separators=(',',':')))
(root/'offline-manifest.json').write_text(json.dumps({'version':source,'source':f'https://raw.githubusercontent.com/outinletter/wordahead/{source}/dictionary/','shards':shards},separators=(',',':')))
print(f'{len(core)} core entries; {len(shards)} optional shards')
