# Offline dictionary attribution

Definitions and IPA are adapted from English and Korean Wiktionary contributors,
via Kaikki.org and Wiktextract. The generated dictionary files are available under
Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0).

- English source: https://en.wiktionary.org/
- Korean source: https://ko.wiktionary.org/
- English extract: https://kaikki.org/dictionary/English/
- Korean extract: https://kaikki.org/kowiktionary/rawdata.html
- License: https://creativecommons.org/licenses/by-sa/4.0/
- License text: https://creativecommons.org/licenses/by-sa/4.0/legalcode

Changes: lowercase keys; merged duplicate headwords and parts of speech;
up to six glosses per source entry and twelve merged glosses; omitted examples,
audio recordings, images, and categories; grouped into 256 offline shards.
Korean definitions take precedence where available. Original English definitions
are provided for entries that do not have a Korean definition. No machine-generated
definitions are included. Exact source checksums and entry counts are in manifest.json.

Each word sheet links to the original Wiktionary entry and its contributor history.
The dictionary data license is separate from the application source code.

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
