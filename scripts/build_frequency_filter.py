"""Build supplementary exclusions from the official NGSL 31K workbook.
Usage: python3 scripts/build_frequency_filter.py /path/to/NGSLwithSFI-31K.xlsx
The existing NGSL headwords and forms remain excluded.
"""
import hashlib,json,re,sys,zipfile,xml.etree.ElementTree as ET
from pathlib import Path
root=Path(__file__).resolve().parents[1]
workbook=Path(sys.argv[1]);ns={'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
with zipfile.ZipFile(workbook) as archive:
 strings=[''.join(x.itertext()) for x in ET.fromstring(archive.read('xl/sharedStrings.xml')).findall('s:si',ns)]
 ranked=[]
 for row in ET.fromstring(archive.read('xl/worksheets/sheet1.xml')).findall('s:sheetData/s:row',ns)[1:]:
  cells={}
  for cell in row.findall('s:c',ns):
   node=cell.find('s:v',ns);value=node.text if node is not None else ''
   cells[re.sub('[0-9]','',cell.attrib['r'])]=strings[int(value)] if cell.attrib.get('t')=='s' and value else value
  word=cells.get('A','').strip().lower()
  if re.fullmatch('[a-z]+',word) and cells.get('G','').isdigit():ranked.append((int(cells['G']),word))
heads=[]
for frequency,word in sorted(ranked,key=lambda x:(-x[0],x[1])):
 if word not in heads:heads.append(word)
 if len(heads)==4000:break
assert len(heads)==4000
forms=set(heads)
for word in heads:
 if len(word)<3:continue
 forms.add(word+'s')
 if word.endswith(('s','x','z','ch','sh')):forms.add(word+'es')
 if word.endswith('y') and word[-2] not in 'aeiou':forms.update([word[:-1]+'ies',word[:-1]+'ied'])
 if word.endswith('e'):forms.update([word+'d',word[:-1]+'ing'])
 else:forms.update([word+'ed',word+'ing'])
 if word.endswith('ie'):forms.add(word[:-2]+'ying')
# Use attested inflections when the dictionary explicitly identifies their base.
headset=set(heads)
pattern=re.compile(r'^(?:plural|simple past(?: tense)?(?: and past participle)?|past participle|present participle|third-person singular simple present(?: indicative)?|comparative|superlative) (?:form )?of ([a-z]+)\b',re.I)
for path in sorted((root/'dictionary').glob('??.js')):
 text=path.read_text();entries=json.loads(text[text.index('{'):text.rfind('}')+1])
 for word,entry in entries.items():
  if not re.fullmatch('[a-z]+',word):continue
  match=pattern.match(entry[2])
  if match and match.group(1).lower() in headset:forms.add(word)
# Remove generated spellings that never occur in the dictionary; retain headwords.
attested=set()
for path in sorted((root/'dictionary').glob('??.js')):
 text=path.read_text();attested.update(json.loads(text[text.index('{'):text.rfind('}')+1]))
forms=headset|(forms&attested)
(root/'dictionary/frequency-4000-headwords.txt').write_text('\n'.join(heads)+'\n')
(root/'dictionary/extended-basic.js').write_text('// NGSL Project 31K frequency data; raw token frequency, descending. CC BY-SA 4.0.\n// Includes 4,000 alphabetic headwords and attested inflected forms. See NOTICE.md.\nfor(const word of '+json.dumps(' '.join(sorted(forms)))+'.split(" "))WordAheadBasicVocabulary.add(word);\n')
(root/'dictionary/frequency-4000-source.json').write_text(json.dumps({'source':'https://www.newgeneralservicelist.com/s/NGSLwithSFI-31K.xlsx','sha256':hashlib.sha256(workbook.read_bytes()).hexdigest(),'ranking':'Raw frequency G descending; alphabetical tie-break; single alphabetic lemmas only','headwords':len(heads),'forms':len(forms),'license':'CC-BY-SA-4.0'},indent=2)+'\n')
print(f'{len(heads)} headwords; {len(forms)} forms')
