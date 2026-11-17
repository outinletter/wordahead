# WordAhead

영어 자막을 읽으며 단어 뜻과 발음을 확인하고 개인 단어장으로 복습하는 앱입니다. 한국어 안내를 사용하는 영어 학습자를 대상으로 합니다.

## 실행과 빌드
정적 HTTP 서버로 프로젝트 루트를 제공하거나 `ios/WordAhead.xcodeproj`를 Xcode에서 엽니다. iOS 학습 화면은 SwiftUI와 네이티브 텍스트 선택 UI로 구현합니다. WKWebView는 공식 YouTube 플레이어와 최초 기존 localStorage 데이터 이전에만 사용합니다. 웹 버전은 별도로 유지하며 iOS 번들에 웹 학습 화면을 포함하지 않습니다. Bundle ID: com.addvalue.wordahead. iOS 16 이상, iPhone 대상입니다. 서명 팀과 배포 설정은 실제 계정을 확인하세요.

## 기능
- 예시 자막 및 직접 입력한 영어 자막 읽기
- 단어 뜻, 음성 합성, 단어 저장·복습·삭제
- 알고 있는 어휘 체크와 JSON 백업·불러오기 (전체 데이터 백업 아님)
- 기기 내부 기록을 이용한 규칙 기반 추천, 읽기 위치·글자 크기 저장
- 전체 학습 데이터 삭제
- YouTube 영어 자막 요청: iOS는 기기에서 직접 요청, 웹은 Cloudflare Worker 사용
- Wiktionary 온라인 조회 및 Kaikki/Wiktextract 기반 내장 사전

## 제한과 제출
YouTube 자막 요청은 비공개 player 엔드포인트에 의존하므로 접근 제한·서비스 변경·지역에 따라 실패할 수 있습니다. 자동 수집을 항상 가능하다고 광고하지 마세요. 실패하면 직접 입력으로 학습할 수 있습니다. 공식 YouTube IFrame 플레이어로 앱 안에서 재생하며 자막 시간 버튼은 seekTo로 연결됩니다. iOS 플레이어는 별도 WKWebView와 앱 식별자 baseURL을 사용합니다. 영상 파일 추출·다운로드·광고 차단·재생목록 수집·회원가입·공개 공유 기능은 없습니다. 연간 Plus 구독은 StoreKit 2를 사용합니다. 예시 자막은 실제 영상 자막이 아닙니다.

사전 출처와 CC BY-SA 4.0 안내는 dictionary/NOTICE.md에 있습니다. 제3자 영상·자막에 대한 권한을 증명하는 문서는 저장소에서 확인되지 않았습니다. 공개 접근 가능 여부는 사용 허가 증명이 아닙니다.

심사 대응 문서는 docs/app-review에 있습니다. 실제 제출 빌드의 물리 기기 검증과 영상 촬영, App Store Connect 입력은 개발자가 완료해야 합니다. 소스 수정은 기존 제출 바이너리에 자동 반영되지 않습니다.

## Korean-only offline dictionary
The app bundles 49,527 Korean-meaning headwords (15,265 Wiktionary core entries
and 34,262 Kengdic additions), about 3.45 MB of JSON data. Existing valid
Wiktionary entries take priority. Kengdic is kept in a separate MPL 2.0 data
file; see dictionary/NOTICE.md and dictionary/MPL-2.0.txt. Filtering is automated,
not full manual translation verification.

Rebuild with `python3 scripts/package_offline_dictionary.py /path/to/kengdic.tsv`
using the pinned Kengdic revision in NOTICE.md. `import_dictionary.py` and legacy
shards are source archives for historical rebuild/filter tooling; they are not
bundled, fetched or required by the current app. No dictionary download is needed.
The native loader verifies both bundled files before deleting generated legacy
English shard caches. User vocabulary and lookup caches are preserved.

## Native iOS storage and verification
On first native launch, the existing WebKit localStorage is copied to
`Library/Application Support/WordAheadNative/learning.json` with atomic writes.
Saved video metadata, transcripts, cue timings, words, known words, profiles and
Korean meaning caches are retained. The original snapshot is preserved until
explicit learning-data deletion. Later launches use the native JSON store;
corrupt native files are not replaced automatically with stale legacy data.

Run `DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer python3 scripts/check_native_learning.py`
on macOS for migration, offline sentence/timing, Korean lookup, word persistence,
backup, basic-vocabulary exclusion and corrupt-file checks. Native UI translations
reuse `i18n.js`; regenerate them with `node scripts/build_native_localizations.cjs`.
Use `DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer bash scripts/ios-release.sh archive`
to archive, then `install DEVICE_ID` to update a connected iPhone without deleting
its data. `upload` is a separate explicit operation, not part of archive/install.

Build 43 was prepared for local device installation only. App Store upload and
review submission are intentionally deferred. Subscription product availability
and sandbox purchase/restore remain separate release checks.
