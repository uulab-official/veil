# Windows 단일 캔버스 UI 체크리스트

Date: 2026-08-03

목적: Veil 창 안에 별도 모니터와 제어판이 다시 들어간 것처럼 보이는 중첩 UI를 제거한다.

## 완료

- [x] 메인 Windows 영역의 바깥 여백과 카드형 외곽선을 제거한다.
- [x] 설치·Windows 화면이 헤더 아래 남은 공간 전체를 직접 사용한다.
- [x] 별도 대형 `Windows Apps` 패널을 제거한다.
- [x] 설치 후 앱 목록을 Windows 캔버스 위의 하단 앱 Dock으로 통합한다.
- [x] 앱 타일을 작은 아이콘·이름·실행 창 배지 형태로 축소한다.
- [x] 데스크톱 전환, 설정, 복구 메뉴는 우측 상단 캡슐 도구로 정리한다.
- [x] 실제 Windows 캡처와 Apple Virtualization 화면의 둥근 모니터 프레임을 제거한다.
- [x] 불필요해진 상태 카드 및 증거 표시 계산 코드를 제거한다.
- [x] 앱 Dock에 접근성 컨테이너 이름과 각 앱 실행 레이블을 유지한다.
- [x] `RuntimeDisplaySelectionTests` 3개가 통과한다.
- [x] 전체 Swift 테스트 380개 / 25 suites가 통과한다.
- [x] `./script/build_and_run.sh --verify` 앱 번들 검증이 통과한다.
- [x] 빌드된 앱에서 설치 화면이 단일 전체 폭 캔버스로 표시됨을 확인한다.

## 남은 실기 게이트

- [ ] guest agent가 연결된 실제 설치 완료 상태에서 앱 Dock의 Notepad·Calculator·Paint 실행을 확인한다.
- [ ] 실제 QEMU/VNC Windows 화면에서 상단 도구와 하단 앱 Dock이 입력 영역을 방해하지 않는지 확인한다.
- [ ] 작은 창 크기에서 앱 Dock 가로 스크롤과 상태 배지가 잘리지 않는지 확인한다.
