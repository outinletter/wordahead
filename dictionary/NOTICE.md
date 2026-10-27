# Offline dictionary attribution

The app bundles two separate Korean-meaning datasets. English-only definitions,
audio files and the legacy optional English dictionary shards are not distributed
with the app or downloaded by the current runtime. Speech uses system text-to-speech.

## Wiktionary: core-ko.json (CC BY-SA 4.0)

Korean meanings and IPA are adapted from English and Korean Wiktionary contributors
via Kaikki.org/Wiktextract. Existing usable Korean definitions take precedence.
Legacy entries without Korean meanings (punctuation or Latin-only text) and editorial placeholders were removed.

- Korean source: https://ko.wiktionary.org/
- English source (including IPA): https://en.wiktionary.org/
- Extracts: https://kaikki.org/kowiktionary/rawdata.html and https://kaikki.org/dictionary/English/
- License: https://creativecommons.org/licenses/by-sa/4.0/
- License text: https://creativecommons.org/licenses/by-sa/4.0/legalcode

Changes: lowercase keys; merged senses; limited gloss counts; omitted examples,
audio, images and categories; retained only Korean-meaning entries. The data file
remains CC BY-SA 4.0, separately from the app and Kengdic data.

## Kengdic: kengdic-ko.json (MPL 2.0)

Original dictionary: Joe Speigle, maintained by garfieldnate and contributors.
We select the upstream MPL 2.0 license option (upstream also offers LGPL 2.0 or later).
The modified data file remains MPL 2.0. Full license text: [MPL-2.0.txt](MPL-2.0.txt).

- Repository and original licensing notice: https://github.com/garfieldnate/kengdic
- Pinned source: https://github.com/garfieldnate/kengdic/blob/793de2369c9a98b944154eb4695d26854d2de59b/kengdic.tsv
- Source form of this modified JSON file and build script: https://github.com/outinletter/wordahead
- Rebuild: `python3 scripts/package_offline_dictionary.py /path/to/kengdic.tsv`

Changes: invert single lowercase English glosses to Korean surfaces; exclude
existing Wiktionary headwords, phrases, uppercase names, non-word keys, mixed
Latin/Korean definitions and known source errors; normalize whitespace, deduplicate
and retain up to four Korean senses per word. These filters are automated; this is
not a claim that every translation was manually verified. Original data quality
limitations are documented in the upstream README. Known incorrect "uptime"
and mismatched "white" senses are excluded.

Counts, checksums and source revision are recorded in manifest.json and
offline-manifest.json. The two data files are a collection with separate licenses;
no Kengdic text has been merged into the CC BY-SA core file.

## Basic vocabulary recommendation filter

`basic-vocabulary.js` is adapted from the New General Service List (NGSL) 1.2
by Charles Browne, Brent Culligan, and Joseph Phillips, under CC BY-SA 4.0.
It contains 2,809 headwords and their published inflected forms, plus the
supplementary number, month and weekday list. These are used only as a string
exclusion filter, not as definitions or a proficiency assessment.

- Official project: https://www.newgeneralservicelist.com/new-general-service-list
- Source: https://www.newgeneralservicelist.com/s/NGSL_12_lemmatized_for_research.csv
- Supplement: https://www.newgeneralservicelist.com/s/SUP_lemmatized.csv
- License: https://creativecommons.org/licenses/by-sa/4.0/

Changes: removed comments and blank fields; lowercased, deduplicated and sorted
word forms; packaged as a JavaScript Set. The derived word list retains
CC BY-SA 4.0. NGSL is a general English vocabulary list, not an official Korean
high-school grade-1 curriculum list. It serves as an approximate baseline for
excluding basic vocabulary in this app. All list data is bundled for offline use.

## Extended basic vocabulary exclusion (4,000 frequency headwords)

`extended-basic.js` uses the NGSL Project's **NGSL 1.2 plus statistics and
frequencies to 31K for research purposes**, by Charles Browne, Brent Culligan,
and Joseph Phillips, licensed CC BY-SA 4.0.

- Source: https://www.newgeneralservicelist.com/s/NGSLwithSFI-31K.xlsx
- Official page: https://www.newgeneralservicelist.com/new-general-service-list
- License: https://creativecommons.org/licenses/by-sa/4.0/

Adaptation: select 4,000 unique alphabetic lemmas by raw frequency (column G),
highest first, with alphabetical tie-breaking. Include dictionary-attested
regular forms and explicitly identified inflections. This supplements the
existing NGSL exclusion list; it is a frequency filter, not a school-grade
assessment. Source hash and selection details: `frequency-4000-source.json`.
Rebuild: `python3 scripts/build_frequency_filter.py /path/to/NGSLwithSFI-31K.xlsx`.
The adapted list retains CC BY-SA 4.0. Inflection data also uses the Wiktionary
sources and attribution described above.
