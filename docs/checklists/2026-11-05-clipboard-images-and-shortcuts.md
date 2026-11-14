# 클립보드 이미지·파일과 단축어 (2026-11-05)

UTM 기능 대조(`2026-11-05-utm-feature-parity.md`) 8번과 18번. 프로토콜은 `docs/protocol.md`의
"Clipboard Image", "Clipboard Files", "Host controls"가 기준이다.

## 클립보드

- [x] `clipboard.image.set`: PNG만, 8 MiB·한 변 16,384px·32M 픽셀 상한, SHA-256으로 에코와 반복 차단,
      텍스트와 같은 시퀀스 공간. 양쪽 모두 서명·IHDR·길이·해시가 맞아야 디코더에 넘긴다.
- [x] 호스트 WebSocket 수신 상한을 1 MiB(URLSession 기본값)에서 32 MiB로 올림. 그대로 두면 큰 이미지
      한 번에 이벤트 스트림이 끊기고 재연결한다.
- [x] 게스트는 Windows 클립보드 시퀀스 번호가 바뀔 때만 이미지를 다시 읽는다(500 ms 폴링마다 수 MB를
      읽지 않도록). `PNG` 형식을 우선 읽고 없으면 `CF_DIB`를 PNG로 변환, 쓸 때는 `PNG`와 `CF_DIB`를 함께 둔다.
- [x] Finder 파일 → Windows: ⌘V 시점에 선택한 일반 파일만 `/Volumes/VeilShared/Veil Clipboard/<batch>/`로
      복사하고 상대 경로만 보낸다. 게스트는 `C:\VeilShared\Veil Clipboard\` 밖, `..`, `:`, 장치 이름,
      재분석 지점을 거부하고 `CF_HDROP`(복사 효과)으로 올린다. 최신 배치 3개만 남긴다.
- [x] 사용자 제어: 앱스 메뉴 "Windows와 클립보드 공유"(기본 켬, 끄면 양방향 모두 중지)와
      "붙여넣을 때 파일을 Windows로 복사"(기본 켬).
- [x] 게스트 → Mac 반영은 Veil이 활성 앱일 때만. 백그라운드 Windows 앱이 Mac에서 방금 복사한 내용을
      덮어쓰는 놀람을 막는다. 비활성 중 업데이트는 버린다(대기열에 두지 않음).

### 설계 판단

- 파일 바이트를 제어 채널로 보내지 않는다. 공유 폴더(게스트 SMB 서버, Mac은 클라이언트)를 경유하면
  호스트 폴더를 Windows에 노출하지 않고, 사용자가 붙여넣은 파일만 게스트에 들어간다.
- Windows → Mac 파일 복사는 하지 않는다. 게스트가 Mac 페이스트보드의 파일 URL을 고르게 되면 Finder가
  호스트 파일에 작용하게 만들 수 있다. 사용자는 공유 폴더에서 직접 가져온다.
- 폴더 복사는 v1에서 제외. 재귀 복사는 심볼릭 링크와 패키지 번들로 사용자가 고른 것보다 많이 옮긴다.
- 이미지를 지원하지 않는 구버전 에이전트에 이미지 붙여넣기를 하면 실패로 안내하고 Ctrl+V를 보내지 않는다.
  텍스트와 달리 `.skipped`로 두면 Windows의 예전 클립보드가 붙여넣어진다.

## 단축어(App Intents)

- [x] Windows 시작(일시 중단 세션이면 재개), 종료, 일시 중단, 재개, Windows 앱 열기(앱 엔티티)와
      App Shortcuts 5개, 한국어 문구(`ko.lproj/AppShortcuts.strings`, `Localizable.strings`).
- [x] 종료는 메뉴와 같은 조건(열린 Windows 앱 창 또는 대기 중 실행)에서 확인을 묻는다. 재개는 저장된
      세션이 없으면 실패하고 새로 부팅하지 않는다. 어떤 동작도 메인 창을 앞으로 가져오지 않는다.
- [x] 메타데이터: `swift build`는 모든 Swift 파일의 `.swiftconstvalues`를 만들지만 Xcode의
      "Extract App Intents Metadata" 단계는 실행하지 않는다. `script/extract_app_intents_metadata.sh`가
      Xcode의 `appintentsmetadataprocessor`를 직접 실행해 `Contents/Resources/Metadata.appintents`를 만든다.
      `build_and_run.sh`는 실패 시 경고, `release_macos.sh`는 실패 시 중단. debug·release 구성 모두에서
      `extract.actionsdata`에 인텐트 5개, 엔티티 1개, 자동 단축어 5개가 들어가는 것을 확인했다.
      Xcode가 설치되어 있어야 한다(명령줄 도구만으로는 프로세서가 없다).

## 검증하지 못한 것

- 실제 Windows 게스트와의 이미지·파일 왕복. 호스트 단위 테스트와 프로토콜 픽스처만 확인했다.
- 게스트 C# 코드는 이 Mac에 .NET SDK가 없어 로컬에서 컴파일하지 않았다. Windows CI(`dotnet test`)에서
  빌드와 새 테스트가 돈다. GDI+ 변환과 `CF_HDROP` 테스트는 Windows에서만 실행된다.
- 단축어 앱에 동작이 실제로 나타나는지. 앱 번들을 다시 빌드하면 `build_and_run.sh`가 실행 중인 Veil을
  종료하므로 사용자 세션 중에는 실행하지 않았다.
- AppleScript 사전(sdef)은 추가하지 않았다. 단축어가 AppleScript의 "run shortcut"으로도 호출되므로
  자동화 경로는 App Intents 하나로 둔다.
