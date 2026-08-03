# Veil 미비 기능 진행 체크리스트

Date: 2026-08-02

목적: Notepad MVP 증명 상태에서 실제 Developer Preview 사용 경로까지 닫는다.

## P0 — 빌드와 기본 실행 경로

- [x] Swift host 패키지가 컴파일된다.
  - 확인: `swift test --disable-sandbox` 빌드 단계 통과.
- [x] Swift 테스트 전체 통과.
  - 확인: clean `develop` 기준 `swift test --disable-sandbox` — 332 tests / 18 suites.
- [ ] Windows agent `dotnet test` 통과.
- [x] protocol 및 주요 harness 테스트 통과.
  - 확인: bundled Node로 protocol/harness 626 tests 통과; fake-agent 24개와 fake-host 8개 포함.
- [ ] 기본 셸에서 `VM 시작 → agent 연결/복구 → 앱 실행 → mirrored window 표시`를 터미널 없이 완료.
- [ ] Windows desktop이 일반 사용 경로에 노출되지 않고 recovery 때만 표시된다.
- [ ] Secure Boot firmware와 virtio driver가 없는 경우 사용자가 다음 조치를 알 수 있다.

## P0 — 기본 화면 UX 정리 (2026-08-03)

- [x] 메인 화면의 동일한 실행 CTA 중복 노출을 제거한다.
- [x] 앱 선택, 실행, 현재 창 상태만 기본 화면에 남긴다.
- [x] 진단·프린터·복구·릴리스 검증 정보는 `More` 경로로 이동한다.
- [x] 화면 단순화 후 Swift 테스트와 앱 번들 실행 검증을 다시 통과한다.
- [x] 실행 중인 VM에 실제 display surface가 있으면 런처 대신 Windows 화면을 기본으로 연다.
- [x] 드롭다운 앱 선택을 앱 아이콘 타일 중심의 즉시 실행 런처로 바꾼다.
- [x] Windows가 설치되지 않은 상태에서는 앱 실행보다 설치 동작을 우선한다.
- [x] 설치 전에는 앱 카탈로그와 중복 CTA를 숨기고 Windows 설정 화면 하나만 표시한다.
- [x] 일반 실행에서 자동 데모 fallback을 제거하고 `--demo` 또는 `VEIL_DEMO_MODE=1`로만 명시적으로 허용한다.
- [x] 커밋되지 않은 Retina scale API 참조를 제거해 `develop` 기본 Swift 빌드를 복구한다.
  - 확인: `./script/build_and_run.sh --verify-keep-running` 통과; agent가 없는 기본 화면에 데모 앱 타일이 표시되지 않음.
- [ ] VM 설정을 별도 설정 시트로 분리한다.
- [ ] Windows ISO로 VM을 준비하고 QEMU/HVF 또는 Apple Virtualization으로 실제 Windows desktop 표시를 검증한다.

## P0 — Parallels급 기본 사용 루프

- [ ] 첫 실행에서 Windows 11 Arm ISO 선택부터 VM 생성·설치 시작까지 한 화면에서 완료한다.
- [ ] 앱 셸에서 `Windows 시작 → guest agent 연결/복구 → 선택 앱 실행 → macOS 창 표시`를 터미널 없이 완료한다.
- [ ] Windows 부팅 중에는 라이브 display surface와 명확한 부팅 상태를 함께 표시한다.
- [ ] Windows 설치 후에는 설정 화면보다 앱 타일 런처가 기본 화면이 된다.
- [ ] Developer ID 서명과 notarization으로 다른 Mac에서도 “손상됨” 없이 실행한다.

## P1 — 실기 검증이 필요한 기능

- [ ] Notepad 실제 VM에서 binary frame channel 렌더링 확인.
- [ ] dirty-rect tile 렌더링이 JSON full-frame과 동일한지 확인.
- [ ] frame pipeline 측정: typing, idle, scrolling, 동시 3창.
- [ ] tile drop 후 periodic key frame 복구 확인.
- [ ] Shared Folder 실제 생성, macOS mount, 양방향 read/write 확인.
- [ ] suspend/resume 후 unsaved Notepad text 보존 확인.
- [ ] qcow2 snapshot create/restore/delete 실제 확인.
- [ ] 한국어/IME 입력 실제 확인.
- [ ] Windows audio playback 실제 확인.
- [ ] Windows notification consent 및 macOS Notification Center 전달 확인.
- [ ] Calculator/Paint 및 동일 앱 복수 창의 독립 입력 확인.

## P1 — 프로토콜 신뢰성

- [ ] fire-and-forget input/clipboard/frame-control 메시지에 bounded acknowledgement 또는 오류 수신 경로 추가.
- [x] `window_not_tracked`를 닫힌 창으로 처리하고 재실행 루프를 막는다.
- [ ] guest의 `false` 반환이 protocol error로 변환된다.
- [x] `type-text`가 `input.text`를 사용해 Unicode를 허용한다.
- [x] clipboard write 실패 시 `Cmd+V`를 중단하고 사용자에게 알린다.

## P2 — 제품 완성도와 제한사항

- [ ] mirrored window에 Windows app icon/proxy icon을 표시한다.
- [ ] 파일 drop을 Shared Folder 경로로 전환해 50MB base64 병목을 제거한다.
- [ ] guest event rate limit 및 sequence 검증을 live 확인한다.
- [ ] USB passthrough/bridged networking은 unavailable 상태와 대안을 계속 명시한다.
- [ ] README, MVP, roadmap의 live evidence 상태를 단일 기준으로 정리한다.

## 진행 규칙

1. 한 번에 한 단계만 구현하고 가장 좁은 검증을 실행한다.
2. protocol message shape가 바뀌면 `docs/protocol.md`, fixture, validator를 함께 갱신한다.
3. 실기 검증 전에는 기능을 shipped로 표현하지 않는다.
4. Windows image, product key, signing private key, Parallels asset은 저장소에 추가하지 않는다.

## 현재 증거

- [x] QEMU/HVF 기반 Notepad health, HWND, PNG frame, mouse, keyboard, host-to-guest clipboard proof가 문서에 기록되어 있다.
- [x] 현재 작업 트리 전체가 clean하지 않다. 기존 변경사항은 보존했다.
- [ ] 새 기능들의 host/guest 실기 검증 증거가 부족하다.

## 실행 환경 메모

- Swift 테스트는 macOS 테스트 번들 서명 정책 때문에 기본 `swift test` 대신 `swift test --disable-sandbox`로 실행해야 한다. 이 현상은 소스 손상이 아니라 테스트 실행 정책 오류였다.
- 현재 실행 환경에 `dotnet` SDK가 없어 Windows agent `dotnet test`는 아직 실행하지 못했다.
