# 장난감 물류창고 (Godot 4.7)

3D 1인칭 인크리멘털 게임. 설계는 `GDD.md`, 진행 상황은 `PROGRESS.md`를 먼저 읽는다.

## 실행·검증
- Godot 실행 파일: `D:\game_\Godot4.7\Godot_v4.7-stable_win64_console.exe`
- 임포트: `<godot> --headless --path . --import`
- 오류 확인(헤드리스 120프레임): `<godot> --headless --path . --quit-after 120`
- 실제 플레이: `<godot> --path .`

## 구조
- `scripts/autoload/`: `EventBus`(시그널), `GameState`(수치), `SaveManager`(저장)
- `scripts/entities/`: 플레이어 등 씬에 붙는 스크립트
- `scenes/`: 씬 파일. `main.tscn`이 메인 씬
- `data/`: 밸런스용 `Resource`(.tres), `assets/`: 모델·사운드

## 규칙
- GDScript, 타입 명시(`var x: int`, `-> void`)
- 장난감 1,000만 개는 숫자로만 관리한다. 화면에는 일부만 그린다
- 시스템 간 통신은 `EventBus` 시그널로 한다
- 입력 액션은 `player.gd`의 `ACTIONS`에서 런타임 등록한다 (`project.godot`에 없음)
- 단계가 끝나면 `PROGRESS.md`를 갱신한다
