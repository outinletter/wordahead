# PROGRESS — WordAhead

## 현재 상태
- 공유 확장: YouTube 링크 공유 시 버튼 없이 저장 후 앱(wordahead://open?url=) 자동 실행.
- 자막: 타임스탬프 탭=재생 위치 이동, 길게 누르기=문장 저장+클립보드 복사+햅틱+체크 토스트.
- 플레이어 없는(오프라인) 자막은 읽던 맨 위 줄을 `readLine.<videoID>`에 저장해 재진입 시 복원.
- 기기 설치·실행 확인함(화면 동작은 사용자 확인 필요). 커밋·푸시 완료.

## 다음 할 일
- [ ] 기기에서 세 기능 동작 확인 (ios/ShareExtension/ShareViewController.swift, ios/NativePlayer.swift, ios/NativeLearningViews.swift)

## 주의사항 / 결정된 사항
- 공유 확장은 responder chain의 UIApplication.open으로 앱을 연다. iOS가 막으면 앱 진입 시 pendingYouTubeURL로 처리됨.
- Xcode-Internal 경로 없음: 기본 xcode-select로 빌드.

## 최근 세션 로그
- 2026-11-26 — 공유 즉시 앱 열기, 읽은 위치 기억, 타임스탬프 탭/길게 누르기 / 기기 확인 남음
