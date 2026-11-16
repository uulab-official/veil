# UTM 기능 대조 (2026-11-05)

UTM(https://github.com/utmapp/UTM)의 기능을 Veil 코드 기준으로 대조한 표다. 경로는 `apps/mac-host/Sources/` 기준이다.
`docs/project-brief.md`의 v1 범위(Windows 11 Arm 전용)를 넘는 항목은 "범위 결정 필요"로 표시했다. USB 패스스루는 2026-11-05에 범위에 넣었다.

| # | 기능 | 상태 | 근거 | 할 일 |
|---|---|---|---|---|
| 1 | 여러 VM 관리(생성·복제·삭제·이름 변경) | 있음 | `VeilHostCore/VMLibrary.swift`, 사이드바 목록, `docs/vm-library.md` | 동시 실행은 한 번에 하나 |
| 2 | VM 가져오기/내보내기, vhdx·vmdk·qcow2 변환 | 있음 | `VMLibrary+Bundle.swift`의 `.veilvm` 번들과 `qemu-img convert` | — (번들 런타임의 `qemu-img`를 사용) |
| 3 | 디스크 추가·크기 조정·qcow2·압축 | 일부 | 새 디스크 qcow2(`QEMUDiskImage.swift`), 설정 창 디스크 탭에서 크기 늘리기·raw→qcow2 변환 | 디스크 추가, 압축 |
| 4 | 스냅샷 | 있음 | 설정 창 디스크 탭(`DiskSettingsPanels.swift`): 실행 중은 QMP 스냅샷 작업, 종료 상태는 `qemu-img snapshot` | — |
| 5 | 일시 중단/재개 | 있음 | `QEMUVMSuspension.swift` | — |
| 6 | 실행 중 ISO 교체 | 있음 | `VMDeviceSettings.swift` 빈 `ide-cd`(전용 `ich9-ahci`), QMP `blockdev-change-medium`/`eject`, 하드웨어 탭 CD/DVD 패널 | 실제 Windows에서 드라이브 인식 실측 |
| 7 | 공유 폴더 | 있음 | `QEMUWindowsSharedFolder.swift`(SMB) | — |
| 8 | 클립보드 공유 | 있음 | 텍스트·PNG 이미지 양방향, Finder 파일 → Windows(공유 폴더 경유) | 실제 게스트 실측; Windows → Mac 파일은 의도적으로 제외 |
| 9 | 동적 해상도·HiDPI·전체 화면 | 있음 | `RFBDesktopResize.swift` | — |
| 10 | 게스트 드라이버 자동 설치 | 있음 | `VirtioWinDriverMedia.swift` | 실측 진행 중 |
| 11 | 네트워크 모드·포트 포워딩 UI | 일부 | 하드웨어 탭 포트 포워딩(기본 127.0.0.1, 0.0.0.0은 경고, Veil 포트 18444·18445·게스트 445 금지, 다음 시작 때 반영) | vmnet은 entitlement 필요(아래) |
| 12 | USB 패스스루 | 있음 | `QEMUUSBPassthrough.swift`, 설정 > USB 장치 | macOS 드라이버가 잡은 장치는 `com.apple.vm.device-access` 필요(실물 장치 실측 전) |
| 13 | 사운드 입출력(마이크) | 일부 | `hda-duplex`가 입력도 제공, `NSMicrophoneUsageDescription`·QEMU `audio-input` entitlement 추가 | 서명된 앱에서 Windows 녹음 실측 |
| 14 | TPM·Secure Boot | 있음 | swtpm, 자체 EDK2 | — |
| 15 | VM 설정 UI(CPU·메모리·장치 편집) | 있음 | 하드웨어 탭 프로세서·메모리(`MachineSettingsPanels.swift`), 디스크·USB·포트 포워딩 탭 | — |
| 16 | 시리얼 콘솔·QEMU 모니터·사용자 인자 | 일부 | 내부 소켓만 | 미착수: 읽기 전용 시리얼 로그, 위험 명령 경고가 있는 모니터 입력, 기본 비활성 사용자 인자 |
| 17 | 입력 캡처·Cmd↔Ctrl 매핑 옵션 | 있음 | Mac 통합 탭 키보드: Cmd를 Ctrl 또는 Windows 키로(데스크톱 화면만, 앱 창은 Ctrl 유지) | Cmd 단독 누름(시작 메뉴)은 아직 안 보냄 |
| 18 | 헤드리스·CLI·AppleScript/단축어 | 있음 | `veil-vmctl`, App Intents(`VeilHostShell/App/VeilAppIntents.swift`) | 단축어 앱 실측; AppleScript 사전은 없음 |
| 19 | VM 갤러리·ISO 다운로드 | 일부 | Windows 11 ISO 다운로드 | — (Windows 전용이라 갤러리 불필요) |
| 20 | 다른 게스트 OS, x86 에뮬레이션 | 있음 | `VMGuestOS.swift`, `QEMUGuestBootPlan.swift`, `GuestVMLauncher.swift`, 파일 > 새 가상 머신 | Linux Arm64·x86_64(TCG) 설치 화면까지 실측, `docs/architecture.md` |
| 21 | 디스플레이 장치 선택·GPU 가속 | 일부 | ramfb + virtio-gpu 고정 | 미착수: 장치 선택. GPU 가속은 아래 근거로 보류 |
| 22 | 자동 시작·종료 시 동작 | 있음 | 일반 탭 시작 및 종료(`StartupBehaviorPolicy.swift`) | — |

## 진행

- [x] 15, 22: 설정 창에서 CPU·메모리 편집, 앱 실행 시 자동 시작, 종료 시 일시 중단 연결
- [x] 6: 실행 중 ISO 교체(QMP, 임시 QEMU 실측)
- [x] 3, 4: qcow2 디스크와 스냅샷 UI (디스크 추가·압축은 남음)
- [x] 1, 2: VM 라이브러리, 가져오기/내보내기 (`docs/vm-library.md`)
- [x] 11: 포트 포워딩 UI
- [ ] 11: vmnet bridged/host-only(entitlement 신청 필요)
- [x] 17: Cmd 키 매핑 선택
- [x] 13: 마이크 권한 키와 QEMU entitlement(실측 전)
- [x] 8, 18: 클립보드 이미지·파일 붙여넣기, App Intents(`docs/checklists/2026-11-05-clipboard-images-and-shortcuts.md`)
- [ ] 16, 21: 시리얼·모니터 콘솔, 디스플레이 장치 선택
- [x] 12: USB 장치 연결·분리(QMP `device_add usb-host`/`device_del`), 종료·일시 중단 전 자동 분리. 드라이버 없는 장치만 권한 없이 동작
- [x] 20: 범위에 넣음(2026-11-05, `docs/project-brief.md`). Linux Arm64(HVF)와 x86_64(TCG) 게스트 생성·부팅, x86_64 에뮬레이터 번들(+29.4 MB)

## 장치·입력 설정 메모 (6, 11, 13, 17, 21)

- **6 CD/DVD**: 모든 계획에 빈 `ide-cd`(id `veil-cd0`)를 전용 `ich9-ahci`(id `veil-cd-ahci`)에 붙인다. `usb-storage`는 매체 없이 시작할 수 없고, Windows는 AHCI 받은편지함 드라이버가 있다(설치 ISO의 AHCI 사본으로 이미 쓰는 경로). 임시 QEMU(`-machine virt -nodefaults`, 번들 QEMU)로 `blockdev-change-medium`(경로에 쉼표·공백 포함, Swift가 `\/`로 이스케이프한 JSON)과 `eject force=true`, `info block veil-cd` 출력을 확인했다. 디스크를 연 뒤 첫 줄은 `veil-cd (#block173): <경로> (raw, read-only)` 형태다. 장치가 추가되어 이전 버전에서 저장한 일시 중단 세션 지문은 맞지 않게 된다. 이전 Veil로 시작한 Windows는 재시작 전까지 드라이브가 없다고 안내한다. 실제 Windows에서 드라이브가 보이는지는 실측하지 않았다.
- **11 포트 포워딩**: 규칙은 하나뿐인 `-netdev user`에 `hostfwd`로 붙는다(임시 QEMU `info usernet`으로 TCP·UDP 확인). `hostfwd`는 일시 중단 지문에서 제외되므로 규칙 변경이 세션을 깨지 않는다. 시작 시 이미 쓰는 호스트 포트는 빼고 경고한다. 게스트 18444(인증 없는 에이전트 제어 채널)와 445는 다시 전달할 수 없다.
- **11 vmnet**: bridged/host-only는 vmnet.framework가 필요하고, root 없이 쓰려면 `com.apple.vm.networking` entitlement가 있어야 한다. Apple 문서는 이 entitlement를 가상화 소프트웨어 개발자에게만 주며 Apple 담당자에게 요청하라고 한다: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.vm.networking . 프로비저닝 프로필에 묶이므로(포럼: https://developer.apple.com/forums/thread/656411) 소스 배포나 ad-hoc 서명 빌드에서는 쓸 수 없다. 신청 전까지 user NAT만 둔다.
- **13 마이크**: `intel-hda` + `hda-duplex`는 입력 코덱도 노출하고 `coreaudio` audiodev가 Mac 기본 입력을 쓴다. QEMU는 Veil이 띄운 자식이라 TCC 요청은 Veil 앱 이름으로 뜨므로 앱 Info.plist에 `NSMicrophoneUsageDescription`(한국어는 `ko.lproj/InfoPlist.strings`)을 넣었다. 하드닝 런타임으로 서명한 QEMU는 `com.apple.security.device.audio-input`이 없으면 입력을 받지 못하므로 `script/qemu-runtime.entitlements`에 추가했다. Windows에서 실제 녹음은 실측하지 않았다.
- **17 키보드**: RFB 경로가 Windows 키를 keysym `Meta_L`(0xffe7)로 보냈는데, QEMU `en-us` 키맵에서 `Meta_L`은 `0x38 shift`(Shift-Alt)이고 Windows 키는 `Super_L 0xdb`다(번들 `share/qemu/keymaps/en-us`). `Super_L`(0xffeb)로 고쳤다.
- **21 디스플레이**: virtio-win에는 Windows 11 ARM64용 디스플레이 전용 드라이버 `viogpudo`가 있다는 보고가 있다(https://virtio-win.github.io/Knowledge-Base/Windows-arm64-vm-using-qemu , https://forum.radxa.com/t/setup-virtio-gpu-for-arm-windows-guest-via-qemu-on-orion-o6/29990). 3D 가속용 `viogpu3d`는 virtio-win 저장소의 미병합 PR이라 직접 빌드해야 하고, macOS 호스트는 `virtio-gpu-gl`에 필요한 virgl/ANGLE 빌드가 Homebrew QEMU에 없다. 그래서 GPU 가속은 보류하고, 장치 선택(ramfb만 / ramfb+virtio-gpu)은 다음 작업으로 둔다.
