# Veil Production Readiness Checklist — 2026-08-05

이 문서는 “패러럴즈급”이라는 표현을 기능별 검증 항목으로 쪼개서 관리하는 출시 체크리스트다. 자동화된 테스트 통과만으로 실제 Windows VM 동작을 완료 처리하지 않는다.

## 판정 규칙

- **PASS**: 현재 실행에서 명령 출력 또는 실제 VM 관찰 증거가 남아 있음.
- **PARTIAL**: 코드/하네스는 있으나 실제 VM 또는 배포 환경 증거가 없음.
- **BLOCKED**: 필요한 SDK, 권한, 인증서, 사용자 동의, 실제 VM 상태가 없어 실행할 수 없음.
- P0 항목이 하나라도 PARTIAL/BLOCKED이면 프로덕션 출시 판정을 내리지 않는다.

## 현재 기준선

- 기준 커밋: `ca7cde7` (`develop`)
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

- [x] Swift host 테스트 467개/29 suites가 최근 실행에서 통과했다.
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
- 현재 실제 framebuffer: `800×600`; QEMU launch plan 목표 `1440×900`과 불일치. Guest Tools 설치/재부팅 전까지 해상도 P0는 미완료.
- 최신 미디어에 win-arm64 `VeilAgent.exe`와 수정된 설치 스크립트를 패키징: 통과.
- UAC 감지/승인 자동화: 한국어 보안 모달을 `modalPrompt`로 감지하고 tap/key 전송: 통과.
- 권한 상승 및 Windows Firewall 단계: `firewallRulesReady` 확인.
- 에이전트 최종 health/reconnect: 미통과. QEMU host-forward TCP는 열리지만 WebSocket health가 응답하지 않아 P0를 닫지 않음.
- 반복 설치 안전성: `start-$PID.log`, `agent.stdout-$PID.log`, `agent.stderr-$PID.log`로 실행별 로그 격리. Windows 계약 테스트에 회귀 검증 추가.

## 최근 자동 검증 기록 — 2026-08-06

- `npm --prefix harness/regression-gate test`: 4/4 통과.
- `./script/test_all.sh`: 전체 게이트 통과. PATH에 없는 Veil 관리 .NET 8 SDK를 자동 발견했다.
- Windows Agent: Release 구성 72/72 통과, 실패 0, 건너뜀 0.
- `git diff --check`: 통과.
- 실제 VM 최적화/Guest Tools/해상도 변경 증거는 이 자동 검증에 포함되지 않으며 여전히 별도 P0 게이트다.
- `./script/test_all.sh`: 전체 게이트 통과. Swift host, Node 패키지 25개, Windows Agent 계약 27개, macOS bundle/launch, 설치·교체·삭제·재설치 lifecycle 통과.
- `git diff --check`: 통과.
- `./script/production_readiness.sh --run-automated --json`: `automatedGate=passed`이며 P0 15개가 미완료라 `blocked`, `releaseReady=false`, 종료 코드 `2`를 반환했다.
