# Parallels식 셸 재구성 체크리스트

Date: 2026-11-04

목적: 한 화면에 상태·앱 목록·설치 안내·엔진 안내가 겹쳐 있던 메인 창을 Parallels Desktop의 구조(Control Center, Installation Assistant, 머신 툴바, Configuration, Actions 메뉴)로 나눈다. 런타임·게스트 에이전트·프로토콜 동작은 바꾸지 않는다.

이 문서는 `2026-08-03-single-canvas-ui.md`의 하단 앱 Dock·우측 상단 캡슐 도구·`⇧⌘A` 전환을 대체한다.

## 완료

- [x] 메인 창을 `NavigationSplitView`로 바꾸고, 사이드바를 Control Center로 둔다: `Virtual Machines`(마지막 화면 썸네일과 상태)와 `Windows Applications`(앱 아이콘, 열린 창 배지).
- [x] 사이드바에서 앱을 누르면 기존 one-click 실행(`runOneClickAppLaunch`)을 그대로 쓴다. Windows가 꺼져 있으면 시작·재개와 에이전트 재연결도 그 경로가 맡는다.
- [x] 커스텀 헤더와 앱 런처 바(`WindowsAppLauncherBar`)를 제거하고, 네이티브 창 제목·부제(머신 이름, 상태)와 툴바로 바꾼다.
- [x] 툴바: 시작/재개, 일시 중단(세션 저장을 지원할 때만), 종료(열린 앱 창이나 대기 중인 실행이 있으면 확인), 보기 모드, Windows 앱 메뉴, 구성.
- [x] 보기 모드(`앱을 Mac 창으로` / `Windows 데스크톱`)를 `ShellNavigation` 한곳에서 소유한다. 툴바, View 메뉴(`⌘1`/`⌘2`), 런타임 화면이 같은 상태를 쓴다.
- [x] Windows 설치 전(미구성·정지·실패·미지원)에는 3단계 Installation Assistant를 보여 준다: Windows 받기 → 이 Mac 준비 → Windows 설치. 설치 프로그램 파일 접근 권한을 잃은 경우에는 1단계로 돌아간다.
- [x] 1단계의 기본 동작은 `Download and Install Windows 11` 한 번이다. 기존 자동 다운로드(Microsoft 공식 Arm64 ISO 자동화, SHA-256 검증)를 마법사 안에 그대로 넣고, 검증이 끝나면 VM 준비와 Windows Setup 시작까지 이어진다. ISO 직접 선택은 보조 링크로만 둔다.
- [x] 다운로드 화면은 ISO가 자리 잡으면 닫히고, 나중에 1단계로 돌아와도 다운로드를 저절로 다시 시작하지 않는다.
- [x] Windows Setup이 시작되면(시작 중·실행 중·일시 중단) 기존 Windows 화면이 마법사 자리를 넘겨받는다.
- [x] 설치된 머신이 꺼져 있으면 마지막 화면을 흐리게 깔고 재생 버튼만 보여 준다. 준비 타임라인과 진행 막대는 Windows가 올라오는 동안에만 표시한다.
- [x] 라이브 Windows 화면 위 캡슐 도구를 제거하고, 같은 기능을 툴바와 Actions 메뉴로 옮긴다.
- [x] 설정 시트를 탭 구성(General / Hardware / Installation / Mac Integration / Diagnostics)으로 나눈다. 리소스 잠금 안내는 리소스를 바꾸는 탭에서만 보여 준다.
- [x] 메뉴를 View(보기 모드, 별도 창 데스크톱, 화면 새로 고침, 새로 고침) · Actions(시작/재개, 일시 중단, 종료, 구성 `⇧⌘,`, 연결 복구, 설치 완료 표시, 앱 확인, 리뷰 증거) · Apps(선택 앱 열기 `⌘↩`, 앱 목록, 앱 창 앞으로 가져오기/모두 닫기)로 재배치한다.
- [x] 툴바·메뉴의 일시 중단은 실패해도 종료로 넘어가지 않고 오류를 알린다. 종료로 넘어가는 동작은 유휴 정책(`quietWindowsWhenIdle`)에만 남긴다.
- [x] `ShellNavigationTests` 7개: 마법사 단계 판정, 머신 상태 문구, 전원 버튼 구성, 구성 탭 열기, 보기 모드 동기화.
- [x] 전체 회귀 게이트(`--skip-app-verify --skip-node-install --skip-windows-agent`)가 통과한다: Swift 207 + 703개, Node 하네스 30개 패키지.
- [x] `./script/build_and_run.sh --verify` 실행 계약 검증이 통과한다.
- [x] 빌드된 앱에서 미설치 상태의 Control Center, Installation Assistant 1단계, 구성 시트 General 탭을 직접 확인한다.

## 남은 실기 게이트

- [x] 마법사 안에서 실제 Microsoft 자동 다운로드 → SHA-256 검증 → VM 준비 → VM 시작까지 클릭 한 번으로 이어진다(2026-11-04, `Windows11_Client_arm64_ko-kr_26300_9457.iso`, 8,482,547,712바이트, 약 3시간).
- [ ] QEMU가 없는 Mac에서는 VM이 Apple Virtualization으로 시작되지만 화면이 검은색에서 넘어가지 않는다. `2026-08-04-live-shared-folder.md`의 기록대로 Virtualization.framework는 Windows 게스트를 실행하지 않으므로, 마법사가 Install 전에 QEMU를 요구하거나 준비하도록 바꾸고 엔진 안내의 "Without QEMU, Veil can install and run the full Windows desktop" 문구를 고친다.
- [ ] 라이브 화면 하단의 이전 상태 줄(`Windows is open` · Settings · Stop Windows · More)과 VM 시작 시 자동으로 뜨는 별도 디스플레이 창을 툴바 구조에 맞게 정리한다.
- [ ] 실제 Windows 11 Arm 설치 완료 상태에서 사이드바 앱 실행, 툴바 일시 중단/재개, 종료 확인 대화상자를 확인한다.
- [ ] QEMU/VNC 라이브 화면에서 툴바 아래 Windows 화면의 입력 좌표가 어긋나지 않는지 확인한다.
- [ ] `820×560` 최소 창에서 사이드바와 툴바 항목이 잘리지 않는지 확인한다.
- [ ] 라이트 모드 시스템에서 메인 창이 어두운 화면으로 일관되게 보이는지 확인한다(`preferredColorScheme(.dark)`).
