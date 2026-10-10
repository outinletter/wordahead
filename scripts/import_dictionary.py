"""Build offline English and Korean-gloss dictionaries from Kaikki/Wiktionary.

Usage: python3 scripts/import_dictionary.py --work /path/to/scratch
Data remains CC BY-SA 4.0; see dictionary/NOTICE.md.
"""
import argparse
import gzip
import hashlib
import json
import sqlite3
from pathlib import Path
from urllib.request import Request, urlopen

SOURCES = {
    'ko': 'https://kaikki.org/kowiktionary/raw-wiktextract-data.jsonl.gz',
    'en': 'https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl',
}
parser = argparse.ArgumentParser()
parser.add_argument('--work', type=Path, required=True)
args = parser.parse_args()
args.work.mkdir(parents=True, exist_ok=True)
output = Path(__file__).resolve().parents[1] / 'dictionary'
output.mkdir(exist_ok=True)
db = sqlite3.connect(args.work / 'entries.sqlite')
db.execute('CREATE TABLE IF NOT EXISTS entries (lang TEXT, word TEXT, value TEXT, shard TEXT, PRIMARY KEY(lang,word))')
digests = {}
for language, url in SOURCES.items():
    marker = args.work / (language + '.done')
    if marker.exists():
        digests[language] = json.loads(marker.read_text())
        continue
    print('Downloading and extracting', language, url, flush=True)
    digest = hashlib.sha256()
    count = 0
    with urlopen(Request(url, headers={'Accept-Encoding': 'gzip'}), timeout=90) as response:
        stream = gzip.GzipFile(fileobj=response) if url.endswith('.gz') or response.headers.get('Content-Encoding') == 'gzip' else response
        for line in stream:
            digest.update(line)
            entry = json.loads(line)
            if entry.get('lang_code') != 'en':
                continue
            word = entry.get('word', '').strip().lower()
            if not word:
                continue
            glosses = list(dict.fromkeys(g for sense in entry.get('senses', []) for g in sense.get('glosses', []) if g))[:6]
            if not glosses:
                continue
            ipa = next((s['ipa'] for s in entry.get('sounds', []) if s.get('ipa')), '')
            value = [ipa, entry.get('pos', 'word').upper(), '; '.join(glosses)]
            shard = hashlib.sha256(word.encode()).hexdigest()[:2]
            old = db.execute('SELECT value FROM entries WHERE lang=? AND word=?', (language, word)).fetchone()
            if old:
                previous = json.loads(old[0])
                meanings = list(dict.fromkeys((previous[2] + '; ' + value[2]).split('; ')))[:12]
                value = [previous[0] or ipa, previous[1] if value[1] in previous[1].split(' / ') else previous[1] + ' / ' + value[1], '; '.join(meanings)]
            db.execute('INSERT OR REPLACE INTO entries VALUES(?,?,?,?)', (language, word, json.dumps(value, ensure_ascii=False), shard))
            count += 1
            if count % 10000 == 0:
                db.commit()
                print(language, count, 'entries processed', flush=True)
    db.commit()
    digests[language] = {'source': url, 'sha256Uncompressed': digest.hexdigest()}
    marker.write_text(json.dumps(digests[language]))

db.execute('CREATE INDEX IF NOT EXISTS entries_shard ON entries(shard)')
db.commit()
for index in range(256):
    shard = f'{index:02x}'
    entries = {}
    for lang, word, value in db.execute('SELECT lang,word,value FROM entries WHERE shard=? ORDER BY lang', (shard,)):
        data = json.loads(value)
        if word in entries and lang == 'ko':
            data[0] = data[0] or entries[word][0]
            if data[1] in ('UNKNOWN', 'WORD'):
                data[1] = entries[word][1]
        if lang == 'ko':
            data.append('ko')
        entries[word] = data
    # English is loaded first, so Korean definitions override where available.
    payload = json.dumps(entries, ensure_ascii=False, separators=(',', ':'))
    (output / (shard + '.js')).write_text('WordAheadDictionary.install(' + json.dumps(shard) + ',' + payload + ');\n')
unique = db.execute('SELECT COUNT(DISTINCT word) FROM entries').fetchone()[0]
korean = db.execute("SELECT COUNT(*) FROM entries WHERE lang='ko'").fetchone()[0]
manifest = {'entries': unique, 'koreanEntries': korean, 'shards': 256, 'license': 'CC-BY-SA-4.0', 'sources': digests}
(output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(manifest, ensure_ascii=False), flush=True)
