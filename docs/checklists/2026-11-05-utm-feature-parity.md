# UTM 기능 대조 (2026-11-05)

UTM(https://github.com/utmapp/UTM)의 기능을 Veil 코드 기준으로 대조한 표다. 경로는 `apps/mac-host/Sources/` 기준이다.
`docs/project-brief.md`의 v1 범위(Windows 11 Arm 전용, USB 패스스루 제외)를 넘는 항목은 "범위 결정 필요"로 표시했다.

| # | 기능 | 상태 | 근거 | 할 일 |
|---|---|---|---|---|
| 1 | 여러 VM 관리(생성·복제·삭제·이름 변경) | 있음 | `VeilHostCore/VMLibrary.swift`, 사이드바 목록, `docs/vm-library.md` | 동시 실행은 한 번에 하나 |
| 2 | VM 가져오기/내보내기, vhdx·vmdk·qcow2 변환 | 있음 | `VMLibrary+Bundle.swift`의 `.veilvm` 번들과 `qemu-img convert` | 번들 런타임에 `qemu-img` 포함(별도 작업) |
| 3 | 디스크 추가·크기 조정·qcow2·압축 | 일부 | raw sparse 디스크 1개 | qcow2 기본값, 크기 조정, 압축 |
| 4 | 스냅샷 | 일부 | `QEMUVMSnapshots.swift`는 CLI 전용, qcow2 필요 | 3번 후 설정 창 UI |
| 5 | 일시 중단/재개 | 있음 | `QEMUVMSuspension.swift` | — |
| 6 | 실행 중 ISO 교체 | 없음 | ISO는 부팅 시에만 연결 | QMP `blockdev-change-medium` |
| 7 | 공유 폴더 | 있음 | `QEMUWindowsSharedFolder.swift`(SMB) | — |
| 8 | 클립보드 공유 | 일부 | 텍스트만 | 이미지·파일 |
| 9 | 동적 해상도·HiDPI·전체 화면 | 있음 | `RFBDesktopResize.swift` | — |
| 10 | 게스트 드라이버 자동 설치 | 있음 | `VirtioWinDriverMedia.swift` | 실측 진행 중 |
| 11 | 네트워크 모드·포트 포워딩 UI | 일부 | user NAT만, NIC는 환경 변수 | vmnet bridged/host-only, 포워딩 UI |
| 12 | USB 패스스루 | 없음 | `QEMUDevicePassthrough.swift` 진단만 | 범위 결정 필요(v1 제외 항목) |
| 13 | 사운드 입출력(마이크) | 일부 | 출력 장치만, 마이크 권한 키 없음 | `NSMicrophoneUsageDescription`과 입력 장치 |
| 14 | TPM·Secure Boot | 있음 | swtpm, 자체 EDK2 | — |
| 15 | VM 설정 UI(CPU·메모리·장치 편집) | 일부 | 설정 창은 표시만 | CPU·메모리 편집 |
| 16 | 시리얼 콘솔·QEMU 모니터·사용자 인자 | 일부 | 내부 소켓만 | 진단 탭의 콘솔, 고급 인자 |
| 17 | 입력 캡처·Cmd↔Ctrl 매핑 옵션 | 일부 | Cmd와 Ctrl 모두 ctrl 고정 | 매핑 선택 |
| 18 | 헤드리스·CLI·AppleScript/단축어 | 일부 | `veil-vmctl` | App Intents |
| 19 | VM 갤러리·ISO 다운로드 | 일부 | Windows 11 ISO 다운로드 | — (Windows 전용이라 갤러리 불필요) |
| 20 | 다른 게스트 OS, x86 에뮬레이션 | 없음 | aarch64 `virt` + HVF 전용 | 범위 결정 필요(v1 제외 항목) |
| 21 | 디스플레이 장치 선택·GPU 가속 | 일부 | ramfb + virtio-gpu 고정 | 장치 선택; virgl은 Windows 드라이버 없음 |
| 22 | 자동 시작·종료 시 동작 | 일부 | `autoStart`/`suspendOnQuit`을 읽는 코드 없음 | 설정 연결 |

## 진행

- [x] 15, 22: 설정 창에서 CPU·메모리 편집, 앱 실행 시 자동 시작, 종료 시 일시 중단 연결
- [ ] 6: 실행 중 ISO 교체
- [ ] 3, 4: qcow2 디스크와 스냅샷 UI
- [x] 1, 2: VM 라이브러리, 가져오기/내보내기 (`docs/vm-library.md`)
- [ ] 11: 포트 포워딩 UI, vmnet
- [ ] 8, 13, 16, 17, 18, 21
- [ ] 12, 20: 범위 결정 후
