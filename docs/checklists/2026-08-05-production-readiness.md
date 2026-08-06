# Veil Production Readiness Checklist — 2026-08-05

이 문서는 “패러럴즈급”이라는 표현을 기능별 검증 항목으로 쪼개서 관리하는 출시 체크리스트다. 자동화된 테스트 통과만으로 실제 Windows VM 동작을 완료 처리하지 않는다.

## 판정 규칙

- **PASS**: 현재 실행에서 명령 출력 또는 실제 VM 관찰 증거가 남아 있음.
- **PARTIAL**: 코드/하네스는 있으나 실제 VM 또는 배포 환경 증거가 없음.
- **BLOCKED**: 필요한 SDK, 권한, 인증서, 사용자 동의, 실제 VM 상태가 없어 실행할 수 없음.
- P0 항목이 하나라도 PARTIAL/BLOCKED이면 프로덕션 출시 판정을 내리지 않는다.

## 현재 기준선

- 기준 커밋: `005c0b3` (`develop`, 다음 변경은 이 기준에서 검증)
- 제품 범위: Windows 11 Arm VM에서 Windows 앱을 macOS 네이티브 창처럼 여는 런타임
- 전체 Windows 데스크톱: 기본 제품 흐름에 포함되지 않으며, 별도 데스크톱 표시 모드가 필요함
- 금지 사항: Windows 이미지·제품 키·Parallels 자산을 저장소에 포함하지 않음

## P0 — 반드시 실제 출시 전에 닫을 항목

### A. 설치와 첫 실행

- [x] Microsoft Windows 11 Arm64 ISO 자동 다운로드 경로가 공식 URL에서 동작한다.
- [x] 다운로드 취소 후 불완전 ISO가 남지 않는다.
- [x] SHA-256 검증 완료 후에만 준비 단계가 열린다.
- [x] Windows 및 Guest Tools 약관을 한 번에 명시적으로 동의받는다.
- [x] 설치·교체·삭제·재설치 수명주기에서 사용자 지원 데이터가 보존된다.
- [ ] 실제 새 VM에서 Windows OOBE 완료 후 첫 실행이 앱 홈으로 복귀한다.
- [ ] 잘못된 ISO, 쓰기 불가 디스크, 권한 거부를 사용자 행동으로 복구할 수 있다.

### B. 게스트 도구·에이전트·재연결

- [x] 게스트 에이전트 health/app-list/window/input/clipboard 프로토콜과 fake-agent가 있다.
- [x] 에이전트 미연결 시 앱 실행 요청이 중복 실행되지 않고 대기 큐로 보존된다.
- [x] VM 재연결 후 저장된 Windows 창 복구 및 추가 창 실행 경로가 있다.
- [ ] 실제 VM에서 Guest Tools를 설치하고 정상 재부팅한다.
- [ ] 재부팅 후 게스트 에이전트가 자동으로 재연결된다.
- [ ] 에이전트 재연결 실패 시 재시도·복구·중단 이유가 사용자에게 보인다.
- [x] UAC 승인 또는 거부를 실제 화면에서 확인하고 잘못된 성공 판정을 하지 않는다. 2026-08-06 QEMU VNC에서 한국어 UAC를 캡처하고 승인 입력 후 데스크톱 복귀를 확인했으며, 에이전트 health가 없을 때 성공으로 판정하지 않았다.

### C. 화면·해상도·입력

- [x] RFB 초기 연결 거부를 재시도하고 마지막 정상 프레임을 유지한다.
- [x] DesktopSize 변경 시 검은 화면 플래시 없이 프레임을 유지한다.
- [x] 레터박스를 제외한 aspect-fit 영역으로 포인터를 매핑한다.
- [x] 여러 HWND를 별도 macOS 창으로 표시하고 런처를 숨긴다.
- [ ] 실제 Guest Tools 설치 후 framebuffer가 `800×600`에서 프로필 목표 `1440×900`으로 변경된다.
- [ ] 해상도 변경 후 가로 잘림·하단 가림·비율 왜곡이 실제 앱에서 재현되지 않는다.
- [ ] 창을 숨겼다 다시 열거나 VM이 재연결되어도 창 크기가 작게 리셋되지 않는다.
- [ ] 실제 Notepad/Calculator/Paint에서 클릭·키보드·Cmd+C/Cmd+V를 확인한다.

### D. 앱 런타임 UX

- [x] 설치 전/설치 중/설치 완료/에이전트 대기 상태가 서로 다른 상태로 표시된다.
- [x] 사용자가 따라갈 단일 primary action과 현재 단계가 있다.
- [x] 실패한 후속 실행이 이전 성공 실행 결과를 재사용하지 않는다.
- [x] `Open New Window`, focus, close, restore 경로가 상태에 따라 활성화된다.
- [ ] 첫 화면에서 실제 VM 시작부터 앱 창 표시까지 터미널 없이 완료된다.
- [ ] 앱 창 표시 중 런처와 미러 창이 겹치거나 “창 안의 창”으로 보이지 않는다.
- [ ] 창 크기·해상도·메뉴바/도크 동작을 실제 장시간 사용으로 확인한다.

### E. 자동화·릴리스 게이트

- [x] Swift host 테스트 471개/29 suites가 최근 실행에서 통과했다.
- [x] Node harness 및 macOS 설치 lifecycle이 최근 실행에서 통과했다.
- [x] 회귀 게이트가 PATH 밖의 Veil 설치 .NET 8 SDK를 자동 탐색한다.
- [x] `script/test_all.sh`를 skip 없이 실행해 Windows Agent 테스트까지 통과한다. 2026-08-05 실행: Windows Agent 72/72, Node 패키지 25개, macOS app bundle/launch, 설치·교체·삭제·재설치 lifecycle 통과.
- [ ] Release 빌드의 bundle identity·entitlements·codesign 검증이 통과한다.
- [ ] Developer ID 서명·notarization·staple을 실제 배포 자격 증명으로 확인한다.
- [ ] 깨끗한 macOS 사용자 계정에서 설치·첫 실행·삭제·재설치를 확인한다.
- [x] P0 미완료 상태에서 `script/production_readiness.sh`가 `releaseReady=false`와 종료 코드 `2`를 반환한다.

## 자동 검증 명령

```bash
npm --prefix harness/regression-gate test
./script/test_all.sh
./script/test_macos_lifecycle.sh --skip-build
./script/production_readiness.sh --run-automated --json
```

현재 환경에서 Veil 설치 도구체인을 자동 발견하지 못하는 경우에만 다음처럼 명시한다.

```bash
VEIL_DOTNET_BIN="$HOME/Library/Application Support/Veil/Toolchains/dotnet8/dotnet" ./script/test_all.sh
```

## 출시 판정

- 현재 판정: **프로덕션 출시 불가 — P0 실제 VM 증거 미완료**
- 가장 먼저 닫을 증거: Guest Tools 동의 → 재부팅 → 에이전트 재연결 → framebuffer 크기 변경 → 실제 앱 입력/클립보드
- 전체 Windows 데스크톱을 요구하는 경우: 현재 앱 미러링 모드와 별도로 데스크톱 표시 모드를 제품 요구사항으로 추가하고, 별도 설계·테스트 계획을 만든다.

## 최근 실제 VM 검증 기록 — 2026-08-06

- QEMU/HVF Windows 11 Arm 부팅 및 실제 데스크톱 프레임 캡처: 통과.
- 이전 실행의 framebuffer는 `800×600`이었고, 최신 실행은 `1024×768` 데스크톱까지 올라왔지만 QEMU launch plan 목표 `1440×900`과 여전히 불일치한다. Guest Tools 설치/재부팅 후 목표 해상도 전환이 실제로 확인되기 전까지 해상도 P0는 미완료다.
- 최신 미디어에 win-arm64 `VeilAgent.exe`와 수정된 설치 스크립트를 패키징: 통과.
- UAC 감지/승인 자동화: 한국어 보안 모달을 `modalPrompt`로 감지하고 tap/key 전송: 통과.
- 권한 상승 및 Windows Firewall 단계: `firewallRulesReady` 확인.
- 에이전트 최종 health/reconnect: 미통과. QEMU host-forward TCP는 열리지만 WebSocket health가 응답하지 않아 P0를 닫지 않음.
- 반복 설치 안전성: `start-$PID.log`, `agent.stdout-$PID.log`, `agent.stderr-$PID.log`로 실행별 로그 격리. Windows 계약 테스트에 회귀 검증 추가.
- `veil-vmctl qemu-start` CLI 수명 회귀를 실제로 확인하고 수정했다. 분리 실행 후 CLI가 반환되어도 QEMU PID가 PPID 1로 남고 VNC `127.0.0.1:5900` 및 QMP가 계속 열리는 것을 확인했다.
- Guest Tools ISO를 네트워크 드라이버 ISO로 오인해 `virtio-net-pci`를 선택하던 계획 버그를 수정했다. UTM Guest Tools 경로는 `usb-net`을 유지하고, 파일명이 `virtio-win`인 드라이버 미디어만 VirtIO 설치 경로로 인식한다. 실제 Windows 디스크에서 VirtIO NIC 자동 선택이 UEFI에 멈추는 것을 재현했으므로, 드라이버 ISO가 있어도 자동 부팅 NIC는 검증된 `usb-net`으로 유지하며 VirtIO는 `VEIL_QEMU_NETWORK_DEVICE=virtio-net-pci` 명시 실험에서만 사용한다.
- 수정된 `usb-net` 구성으로 실제 Windows 바탕화면까지 부팅했지만 framebuffer는 `800×600`이었다.
- 실제 `Optimize.cmd` 실행에서 UTM Guest Tools 한국어 UAC 승인까지 통과했다. 이후 정상 재부팅 뒤 VNC framebuffer가 완전 검은 화면이 되었고, `guest-agent-wait`는 `tcpOpen`만 확인하고 WebSocket health는 시간 초과했다. Guest Tools 설치·재연결·1440×900은 실패 증거로 유지한다.
- 최적화 완료 판정 결함을 수정했다. 재부팅 후 에이전트만 연결된 경우에도 완료하지 않고, 새 데스크톱 캡처가 다시 보일 때까지 검증한다. 검은 화면은 재시도 가능한 실패로 남는다.
- UAC가 Guest Tools 설치와 에이전트 복구에서 두 번 발생하던 자동화 결함을 수정했다. `Optimize-VeilWindows.ps1`가 한 번의 관리자 승인 안에서 Guest Tools 설치와 `Repair-VeilAgentConnectivity.ps1 -Elevated`를 순서대로 실행하도록 자동 설치 미디어에 포함됐다.
- 수정 미디어를 2026-08-06에 재생성했다. `VeilAutoInstall.iso`에 `Optimize-VeilWindows.ps1`, `Repair-VeilAgentConnectivity.ps1`, win-arm64 `VeilAgent.exe`가 실제 포함된 것을 read-only 마운트로 확인했다.
- 새 미디어를 붙인 QEMU/HVF PID 25924가 `usb-net`, `virtio-gpu-pci,xres=1440,yres=900`, 최신 `VeilAutoInstall.iso`로 시작됐지만, 실제 캡처는 800×600 Windows Boot Manager/부팅 로고에 머물렀고 데스크톱·에이전트 health에 도달하지 못했다. 정상 종료는 성공했으며 Guest Tools/재연결/1440×900 P0는 여전히 미완료다.
- `ramfb`와 `virtio-gpu-pci`를 동시에 붙이던 QEMU 계획을 제거하고 virtio 단일 디스플레이 헤드로 제한했다. TDD 회귀 테스트를 추가했고, 실제 Windows 디스크 PID 40961이 검은 화면/부팅 정지 없이 `desktop` 프레임을 반환했다. 최신 실제 framebuffer는 `1024×768`이므로 1440×900 P0는 아직 닫지 않았다.
- 실제 Optimize 복구 경로에서 한 번의 한국어 UAC 승인 뒤 `guestAgentHealthSucceeded=True`와 loopback/게스트 IPv4 health 증거가 Windows 콘솔에 남았다. 그러나 macOS에서 직접 HTTP/WebSocket 핸드셰이크를 재검증한 결과 `18444`는 TCP 연결만 수락하고 5초 동안 응답 바이트가 없어 host-forward WebSocket P0는 미완료다. `usb-net`에서 `e1000e`로 바꾼 격리 재현도 동일해 NIC 단일 변경으로 해결됐다고 판정하지 않았다.
- Run 대화상자에 드라이브 전체 경로를 긴 문자열로 입력하면 실제 화면에서 명령이 잘리는 결함을 재현했다. 자동 설치 미디어에 루트 `V.cmd`, `O.cmd`, `P.cmd` 짧은 진입점을 추가하고 자동화 명령을 축약했으며, QEMU/미디어 빌더 회귀 테스트가 이를 검증한다. 새 미디어 포맷 버전 마커가 없는 기존 ISO는 다음 미디어 준비 단계에서 재생성되어야 한다.
- 2026-08-06에 `qemu-start`가 설치된 VM의 기존 Windows 디스크를 교체하지 않고 `VEIL_AUTO` 지원 ISO를 먼저 재생성하는 경로를 추가했다. 포맷 마커 `2`와 루트 `V.cmd`의 실제 내용(`Veil Guest Agent\\V.cmd`)을 read-only 마운트로 확인했고, 잘못된 `\\(target)` 리터럴을 TDD 회귀로 수정했다.
- 공식 Fedora VirtIO 최신 ISO를 외부 다운로드 폴더에 받아 SHA-256 `e14cf2b94492c3e925f0070ba7fdfedeb2048c91eea9c5a5afb30232a3976331`로 기록했다. 저장소에는 포함하지 않았다. Windows 콘솔에서 수정된 `Repair-VeilAgentConnectivity.ps1`가 `networkDriverInstalled succeeded=True`와 VirtIO NetKVM Windows 11 ARM64 설치 완료를 실제 표시했다.
- 동일한 설치 후 네트워크 장치 대조 결과: `virtio-net-pci`는 UEFI `Start boot option` 화면에 머물러 데스크톱에 도달하지 못했고, `virtio-net-device`는 `1024×768` 데스크톱까지 부팅되지만 `ipconfig`에 어댑터가 나타나지 않았다. 따라서 VirtIO 드라이버 설치 성공만으로 연결 P0를 닫지 않는다.
- `VEIL_QEMU_NETWORK_DEVICE=usb-net`에서는 `1024×768` 실제 Windows 데스크톱까지 부팅했지만, macOS `guest-agent-wait`는 `tcpOpen` 뒤 WebSocket 응답 시간 초과를 반환했다. Windows 내부 수동 복구는 `guestAgentHealthSucceeded=True`를 남겼으므로 현재 미해결 경계는 게스트 NIC/IP 또는 QEMU host-forward 전달이다.
- 자동 `qemu-install-agent`의 새 Enter 우선 경로를 실제 실행했다. Run 대화상자에서 `V.cmd` 실행, 한국어 UAC 감지, `left + ret` 승인, Windows 복구 콘솔 캡처까지 통과했지만 macOS WebSocket health는 여전히 미통과다.

## 최근 자동 검증 기록 — 2026-08-06

- `npm --prefix harness/regression-gate test`: 4/4 통과.
- `./script/test_all.sh`: 전체 게이트 통과. PATH에 없는 Veil 관리 .NET 8 SDK를 자동 발견했다.
- Windows Agent: Release 구성 72/72 통과, 실패 0, 건너뜀 0.
- `git diff --check`: 통과.
- 실제 VM 최적화/Guest Tools/해상도 변경 증거는 이 자동 검증에 포함되지 않으며 여전히 별도 P0 게이트다.
- `./script/test_all.sh`: 전체 게이트 통과. Swift host, Node 패키지 25개, Windows Agent 계약 27개, macOS bundle/launch, 설치·교체·삭제·재설치 lifecycle 통과.
- `git diff --check`: 통과.
- `./script/production_readiness.sh --run-automated --json`: `automatedGate=passed`이며 P0 15개가 미완료라 `blocked`, `releaseReady=false`, 종료 코드 `2`를 반환했다.

## 2026-08-06 follow-up verification

- `npm --prefix harness/windows-agent-contract test`: 27/27 통과. 복구 상태의 `networkDriverInstalled` 중간 성공을 최종 성공으로 오인하지 않는 계약 검증을 포함한다.
- 실제 `qemu-start` 재검증: VirtIO ISO가 프로필에 붙어 있어도 기본 계획이 `usb-net,netdev=net0`을 선택했고, Windows 데스크톱 캡처가 `1024×768`, `visualState=desktop`으로 통과했다. 같은 실행의 `guest-agent-wait`는 `tcpOpen` 후 WebSocket health 시간 초과로 미통과했다.
- 실제 `qemu-install-agent --wait-seconds 90` 재검증: Windows 내부 `repair-status.json`을 직접 화면으로 확인한 결과 `guestAgentHealthSucceeded=true`까지 도달했고 표준 사용자 작업 시작도 완료됐다. 그러나 같은 VM에서 `ipconfig`와 `Get-NetAdapter`가 비어 있어 비루프백 IPv4가 없었고, macOS host health는 `tcpOpen` 후 WebSocket 시간 초과로 남았다.
- 위 증거에 따라 복구 스크립트는 `Start-VeilAgent.ps1 -RequireGuestIPv4`를 사용하도록 강화했다. 이제 loopback-only 상태를 최종 성공으로 기록하지 않는다. `usb-net`과 `e1000e`는 데스크톱까지 부팅했지만 어댑터가 없었고, `e1000`, `rtl8139`, `virtio-net-pci`는 현재 관리 ARM 디스크에서 bounded compatibility probe를 통과하지 못했다. 게스트 NIC/IP 및 host WebSocket P0는 미완료다.
- fresh 전체 회귀 게이트: `VEIL_DOTNET_BIN=.../dotnet ./script/test_all.sh`가 종료 코드 0으로 완료됐다. Swift host 472개/29 suites, Windows Agent 계약 27/27, Node 패키지 25개, macOS bundle/launch, 설치·교체·삭제·재설치 lifecycle을 포함한다.
- fresh production readiness: `./script/production_readiness.sh --run-automated --json` → `{"status":"blocked","releaseReady":false,"p0Total":37,"passingP0Count":22,"unresolvedP0Count":15,"automatedGate":"passed"}`, 종료 코드 `2`.
- 변경 커밋: `441bacc` (`fix(runtime): keep boot-safe NIC and repair stage state`). `develop` 푸시는 HTTPS 원격 인증 오류(`could not read Username for 'https://github.com': Device not configured`)로 완료하지 못했다.
- `swift test --disable-sandbox --package-path apps/mac-host --filter 'WindowsOptimizationCoordinatorTests|QEMUWindowsBootPlanTests|VMProfileStoreTests'`: 135개 통과.
- `swift test --disable-sandbox --package-path apps/mac-host --filter 'QEMUWindowsBootPlanTests|VMProfileStoreTests'`: 123개/2 suites 통과. virtio 단일 디스플레이 헤드와 짧은 `VEIL_AUTO` 진입점 회귀를 포함한다.
- `./script/test_all.sh`: Swift 471개/29 suites, Windows Agent 72개, Node 패키지 25개, 설치·교체·삭제·재설치 lifecycle 통과.
- 현재 변경 기준 focused Swift 151개/3 suites(`QEMUWindowsBootPlanTests|VMProfileStoreTests|WindowsDownloadPolicyTests`)와 Windows Agent 계약 27개가 통과했다.
- 현재 변경 기준 전체 `VEIL_DOTNET_BIN=.../dotnet ./script/test_all.sh` 회귀 게이트가 통과했다. production readiness는 `P0 37개 중 22개 통과, 15개 미완료, automatedGate=passed, releaseReady=false`를 재확인했다.

## 2026-08-06 network-device follow-up

- 최신 `VeilAutoInstall.iso`와 republished win-arm64 agent bundle로 `qemu-install-agent --wait-seconds 90`을 다시 실행했다. Windows 복구 콘솔에 `networkDeviceRescan succeeded=False`와 `pnputil /scan-devices exit code 0. Hardware network adapters visible after rescan: none.`가 남았고, 최종 상태는 loopback `agent.health.response` 실패였다.
- 이 결과로 “VirtIO 드라이버 설치 뒤 PnP 재검색 누락” 가설은 반증됐다. 재검색 명령은 성공했지만 Windows 장치 목록에 하드웨어 NIC가 생성되지 않았다. 복구 스크립트는 이제 PnP 명령 성공만으로 네트워크 단계를 성공 처리하지 않는다.
- `VEIL_QEMU_NETWORK_DEVICE=vmxnet3` bounded probe도 UEFI `Start boot option`에 머물러 현재 관리 ARM 디스크의 production fallback 후보에서 제외했다. 기존 `usb-net`/`e1000e`는 데스크톱까지 부팅하지만 어댑터가 없고, `e1000`/`rtl8139`/`virtio-net-pci`도 현재 디스크에서 첫 앱 루프를 통과하지 못했다.
- 결론: 현재 남은 P0는 설치 스크립트나 단순 PnP 재검색이 아니라, 이 Windows ARM 디스크에서 실제 게스트 NIC를 노출하는 QEMU/Windows 호환성 또는 네트워크 없는 게스트-호스트 전송 경계다. Notepad/HWND/입력/클립보드 P0는 계속 미완료다.

## 2026-08-06 no-IP transport architecture gate

현재 NIC 경로가 닫히지 않았으므로, 네트워크 없는 전송을 “구현된 기능”으로 표시하지 않고 별도 P0 feasibility gate로 관리한다.

- [x] QEMU가 `virtio-serial-pci`와 `virtserialport` 장치를 제공하는지 호스트에서 확인한다.
- [x] 공식 VirtIO ISO에 Windows 11 Arm64용 `vioser` 드라이버가 포함되는지 확인한다.
- [x] `vioser`의 실제 사용자 공간 계약을 확인한다. 게스트는 포트 이름을 기준으로 장치 인터페이스를 열고 `ReadFile`/`WriteFile`을 사용해야 하며, TCP health의 대체 경로로 간주하지 않는다.
- [x] 현재 VirtIO ISO에서 Arm64 `viosock` 드라이버가 제공되지 않는 것을 확인한다. 따라서 vsock을 이미 지원된 대체 경로처럼 문서화하지 않는다.
- [ ] 깨끗한 Windows Arm VM에서 `virtio-serial-pci` 장치와 `vioser`를 함께 설치하고 `org.veil.agent` 포트가 실제로 열리는지 확인한다.
- [ ] macOS host가 Unix socket으로 QEMU chardev 연결을 수락하고, 게스트 health 요청과 응답을 왕복한다.
- [ ] 기존 protocol 메시지를 보존한 프레임 규칙, 최대 메시지 크기, partial read/write, 재연결, timeout, 종료 처리를 계약 테스트로 고정한다.
- [ ] TCP/WebSocket 경로가 실패할 때만 no-IP 경로를 선택하며, health 왕복 전에는 Notepad/HWND/input/clipboard P0를 완료 처리하지 않는다.
- [ ] no-IP health 왕복 후 실제 Notepad frame, 키보드 입력, clipboard를 같은 경로에서 확인한다.

현재 판정: **BLOCKED — 장치와 Arm64 드라이버의 존재는 확인했지만, host socket부터 guest `vioser` 사용자 공간까지의 실제 왕복 증거가 없다.**

참고한 외부 드라이버 계약은 [virtio-win Windows guest drivers](https://github.com/virtio-win/kvm-guest-drivers-windows)와 [공식 드라이버 설치 문서](https://github.com/virtio-win/kvm-guest-drivers-windows/wiki/Driver-installation)다. 저장소에는 드라이버 바이너리나 Windows 이미지가 추가되지 않는다.

구현 진척: Windows Agent에 `VEIL_AGENT_VIRTIO_SERIAL_DIAGNOSTICS=1` 진단 모드를 추가했다. 이 모드는 기본 WebSocket 동작을 바꾸지 않고, vioser 인터페이스를 열거해 포트명·host/guest 연결 상태·장치 경로를 기록한다. 실제 VM에서 `org.veil.agent` 포트가 발견되는 실행 증거가 남기 전까지는 위 체크 항목을 PASS로 올리지 않는다.

## 최신 변경 검증

- `VeilAgent.Tests`: 75/75 통과.
- `git diff --check`: 통과.
- `script/production_readiness.sh --run-automated --json`: automated gate 통과, `P0 37개 중 22개 통과 / 15개 미완료`, `releaseReady=false`.

## 2026-08-06 diagnostic classification verification

- `swift test --disable-sandbox --package-path apps/mac-host --filter 'HostDashboardModelTests|VeilHostClientTests'`: 123개/2 suites 통과.
- `VEIL_DOTNET_BIN=.../dotnet ./script/test_all.sh`: Swift host, Windows Agent 27개 계약 테스트, Node 패키지 25개, macOS bundle/launch, 설치·교체·삭제·재설치 lifecycle 전체 통과.
- `git diff --check`: 통과.
- `./script/production_readiness.sh --run-automated --json`: `automatedGate=passed`, `P0 37개 중 22개 통과 / 15개 미완료`, `releaseReady=false`, 종료 코드 `2`.

## 2026-08-06 virtio-serial probe live evidence

- [x] 기본 WebSocket QEMU 계획으로 동일한 관리 Windows 디스크를 부팅해 대조 기준을 확보했다. `qemu-display-smoke`는 PID `77784`, `visualState=desktop`, `1024×768`을 기록했다.
- [x] `VEIL_QEMU_GUEST_TRANSPORT=virtio-serial-probe`와 `VEIL_QEMU_VIRTIO_SERIAL_SOCKET=/tmp/veil-vioserial-probe-live.sock`로 실제 QEMU를 실행했다. QEMU가 Unix socket을 생성했고 실제 인자에 `virtio-serial-pci`와 `virtserialport,name=org.veil.agent`가 포함됐다.
- [x] probe 실행은 QEMU PID `73364`까지 시작됐지만 `qemu-display-smoke`가 `visualState=modalPrompt`, `recognizedText=["start boot option"]`, `800×600`을 기록했다. Windows desktop, `vioser` 진단 출력, guest health 왕복에는 도달하지 못했다.
- [x] 같은 디스크의 기본 WebSocket 대조 실행이 desktop에 도달했으므로, 이번 probe 실패는 일반 디스크 부팅 실패가 아니라 `virtio-serial-pci`를 추가한 구성에서 재현된 호환성 차이로 기록한다.
- [x] probe QEMU는 정상 종료 요청이 30초 안에 완료되지 않아 `qemu-force-stop --i-understand-data-loss`로 종료했다. baseline QEMU는 QMP ACPI powerdown으로 정상 종료했다.
- [ ] `vioser` 장치가 실제 Windows desktop에서 발견되는지 확인한다.
- [ ] named port를 통한 health 왕복과 Notepad/input/clipboard를 확인한다.
- [x] `max_ports=1`을 임의로 적용하지 않는다. QEMU가 `virtserialport` 포트 ID를 허용하지 않아 `Out-of-range port id specified, max. allowed: 0`으로 종료되는 것을 확인했다.
- [x] 콘솔 포트와 agent 포트를 함께 허용하는 `max_ports=2` probe를 실제 Windows 디스크에서 대조했다. QEMU 인자와 chardev socket 생성은 확인됐지만 `qemu-display-smoke`가 동일하게 `visualState=modalPrompt`, `recognizedText=["start boot option"]`, `800×600`을 기록했다.
- [x] `max_ports=2` probe에서도 host Unix-socket client 연결 여부가 부팅 결과를 바꾸지 않는 것으로 확인했다. 원인은 host chardev client 부재가 아니라 현재 managed Windows ARM 디스크와 VirtIO serial 장치 구성의 호환성 차이로 좁힌다.
- [x] probe VM은 정상 powerdown이 완료되지 않아 `qemu-force-stop --i-understand-data-loss`로 프로세스만 종료했다. Windows 이미지나 디스크는 삭제하지 않았다.

현재 판정: **BLOCKED — `max_ports=1`/`max_ports=2`, host socket client 유무를 확인해도 VirtIO serial 구성은 Windows Boot Manager 단계에서 멈췄다.** 따라서 `virtio-serial`을 production fallback으로 활성화하지 않는다.

## 2026-08-06 guest-agent diagnostic classification

- [x] WebSocket health 실패와 QEMU host-forward TCP 상태를 하나의 `AgentConnectionFailureKind`로 분류한다: endpoint 미지원, host-forward 포트 불가, 게스트 에이전트 무응답, 원인 미확정.
- [x] 기존 진단 JSON에 `failureKind`가 없어도 읽을 수 있도록 optional Codable 필드로 유지한다.
- [x] TCP는 열렸지만 WebSocket health가 시간 초과되는 실제 P0 증거를 `guestAgentUnresponsive`로 표시한다. 이는 연결 성공이나 release-ready 판정으로 승격하지 않는다.
- [x] 공통 진단 패널은 분류별 제목·설명·복구 행동을 보여주고, CLI 비JSON 출력은 동일한 failure kind를 출력한다.
- [x] `VeilHostClientTests`와 `HostDashboardModelTests` 집중 suite를 통과시켰다.

현재 판정: **PARTIAL — 실패 원인과 다음 행동은 제품 표면에서 구분되지만, 실제 Windows 게스트 NIC/IP와 WebSocket health 왕복은 여전히 미해결이다.**
