# 전체 회귀 게이트 체크리스트

Date: 2026-08-03

목적: 일부 테스트만 통과하거나 필수 도구가 없어 실행되지 않은 상태를 전체 성공으로 오인하지 않는다.

## 완료

- [x] Swift host, Windows agent, 프로토콜·하네스, macOS 앱 실행 계약을 한 명령으로 묶는다.
- [x] 테스트 시작 전에 `swift`, `node`, `npm`, `dotnet` 필수 도구를 모두 확인한다.
- [x] 필수 도구가 없으면 어떤 테스트도 시작하지 않고 복구 방법을 표시한다.
- [x] Windows agent와 앱 검증 생략은 명시적인 옵션으로만 허용한다.
- [x] `package-lock.json`이 있는 Node 패키지는 테스트 전에 `npm ci`를 실행한다.
- [x] `node_modules`를 제외하고 테스트 스크립트가 있는 패키지를 자동 탐색한다.
- [x] 테스트 패키지가 0개로 탐색되면 성공하지 않고 실패한다.
- [x] `--list`로 도구 설치 없이 전체 검증 범위를 확인할 수 있다.

## 환경 확인

- [x] Swift host 테스트 385개 / 26 suites가 통과한다.
- [x] Node 프로토콜·하네스 24개 패키지가 의존성 설치 후 통과한다.
- [x] `./script/test_all.sh --skip-windows-agent`로 Swift·Node·macOS 앱 게이트가 한 번에 통과한다.
- [ ] 이 Mac에는 .NET 8 SDK가 없어 Windows agent 단위 테스트를 실행하지 못했다.
- [ ] .NET 8 SDK가 있는 환경에서 옵션 없는 `./script/test_all.sh` 전체 실행을 통과시킨다.
