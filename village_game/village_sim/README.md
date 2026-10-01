# village_sim — 마을 운영 시뮬레이션 모듈

게임 전체가 이 폴더 하나에 들어 있다. 규칙 코드(`scripts/core`)는 사건 내용을 모르고, 사건·엔딩·수치는 모두 `data/`의 JSON에 있다.
**사건을 추가하거나 수치를 조정할 때 코드는 고치지 않는다.**

## 폴더 구조

```
village_sim/
├─ data/                        ← 밸런싱·사건 추가는 여기만 고친다
│  ├─ config/game_config.json   최대 턴, 상태 초기값, 효과 배율, 추첨 규칙
│  ├─ events/                   사건 (하위 폴더 포함 모든 .json을 자동으로 읽음)
│  │  └─ base/                  기본 사건 묶음: 주제별 파일 + state.json(위기·턴·높은 상태)
│  └─ endings/endings.json      붕괴 엔딩 4개 + 임기 종료 엔딩
├─ scripts/
│  ├─ core/                     게임 규칙 (노드·UI와 무관)
│  │  ├─ game_state.gd          한 판의 상태 (상태값, 플래그와 켜진 턴, 본 사건)
│  │  ├─ game_session.gd        턴 흐름. UI와 시뮬레이터가 함께 쓴다
│  │  ├─ event_manager.gd       다음 사건 고르기 (조건부 우선 → 일반)
│  │  ├─ condition_evaluator.gd 조건 판정 (사건·엔딩 공용)
│  │  ├─ effect_manager.gd      효과 적용, 힌트 계산
│  │  └─ ending_resolver.gd     엔딩 판정
│  ├─ data/                     JSON 읽기와 검증
│  └─ game/                     화면 (1차 프로토타입용 최소 UI)
├─ scenes/                      main / game / ending
└─ tools/                       개발용 도구 (게임에는 포함되지 않음)
```

## 한 턴의 흐름

사건 카드 → 카드 왼쪽/오른쪽을 눌러 선택지 미리 보기 (영향받는 상태에 ●, 반대쪽을 누르면 바뀜)
→ 같은 쪽을 한 번 더 눌러 결정 → 결과 카드 (결과 문구 + 상태별 ▲/▼) → 아무 곳이나 눌러 다음 사건 (또는 엔딩)

키보드: ← / → 로 같은 동작, Enter / Space 로 결정·다음. 상태 게이지는 오른쪽 위.

## 배포용 실행 파일 만들기

`village_game/build_exe.ps1`을 실행하면 데이터를 검사한 뒤 `build/마을운영.exe` 한 파일을 만든다.
받는 사람은 설치 없이 더블클릭으로 실행한다. (서명하지 않은 파일이라 처음에 Windows 경고가 뜨면 "추가 정보 → 실행")
Godot은 `coding/tools/godot/`의 휴대용 버전을 쓰며, 내보내기 템플릿도 그 폴더 안에 있다.

## 웹 버전 올리기

`village_game/publish_web.ps1`을 실행하면 데이터를 검사한 뒤 웹 버전을 만들어 `gh-pages` 브랜치에 올린다.
몇 분 뒤 https://erinis4522.github.io/school/ 에 반영된다. (만들기만 하려면 `-NoPublish`)

- 웹 버전은 서버 설정이 필요 없는 "스레드 미사용" 방식으로 내보낸다. (GitHub Pages에서 그대로 동작)
- 브라우저는 컴퓨터에 깔린 글꼴을 쓸 수 없어서, 한글 글꼴(`assets/fonts/NotoSansKR-Regular.otf`, OFL 라이선스)을 게임에 넣어 두었다. exe도 같은 글꼴을 쓴다.
- 처음 접속하면 약 40MB를 받으므로 몇 초 걸린다. 그다음부터는 브라우저에 저장되어 빨라진다.

## 도구

프로젝트 폴더(`project.godot`가 있는 곳)에서 실행한다. `godot`은 `../tools/godot/Godot_v4.7.2-stable_win64_console.exe`로 바꾼다.

| 목적 | 명령 |
|---|---|
| 데이터 검사 | `godot --headless --script res://village_sim/tools/validate_data.gd` |
| 밸런스 시뮬레이션 | `godot --headless --script res://village_sim/tools/balance_sim.gd -- --runs=1000` |
| 화면 흐름 점검 | `godot --headless --script res://village_sim/tools/ui_smoke_test.gd` |

- 데이터 검사는 게임을 켤 때도 자동으로 돌아 출력 창에 결과가 나온다.
- 시뮬레이션 보고서는 `balance_reports/`에 마크다운으로 저장된다. 수정 전후 보고서를 비교하면 된다.

## 밸런싱 순서

1. 수치를 고친다 (아래 "조절 손잡이")
2. 데이터 검사 → 오류 0개 확인
3. 시뮬레이션 → 보고서 확인
   - **임기 완주율**: random이 너무 높으면 쉽고, careful이 낮으면 어렵다
   - **엔딩 분포**: 한 상태의 붕괴만 몰려 있으면 그 상태의 증감 폭을 본다
   - **정답 의심 사건**: careful이 한쪽만 고르는 사건. 지연 사건으로 균형을 맞춘 사건이면 두어도 된다
   - **조건부 사건 등장률**: 지연 사건이 너무 드물거나 잦은지
4. 직접 플레이해 보고 체감 확인

### 조절 손잡이

| 무엇을 | 어디서 |
|---|---|
| 최대 턴 | `game_config.json` → `max_turns` |
| 상태 초기값 | `game_config.json` → `stats[].initial` |
| 한 상태의 증감을 한꺼번에 키우거나 줄이기 | `game_config.json` → `effect_scale` (예: 재정 감소를 20% 줄이려면 `"finance": {"gain": 1.0, "loss": 0.8}`) |
| 비슷한 주제 연속 등장 억제 | `game_config.json` → `selection.recent_tag_window`(최근 몇 사건), `recent_tag_weight`(겹칠 때 가중치 배율) |
| 사건 하나의 효과 | 해당 사건 JSON의 `effects` |
| 사건이 자주/드물게 나오게 | 사건의 `weight` (기본 10) |
| 조건부 사건끼리 순서 | 사건의 `priority` (위기 100, 지연 50, 턴 40, 높은 상태 30) |
| 지연 사건이 나오는 시점 | 지연 사건 조건의 `min_age` |
| 지연 사건이 이어질 확률 | 원래 사건 선택지의 `set_flags` → `chance` |
| 위기 사건 기준 | `events/base/state.json`의 위기 사건 조건 값 (기본 20) |
| 붕괴 기준 | `endings/endings.json`의 붕괴 엔딩 조건 값 (기본 0) |

## 사건 추가

`data/events/` 아래 아무 .json 파일에 추가하거나 새 파일을 만든다. 파일에는 사건 하나(객체) 또는 여러 개(배열)를 넣을 수 있다.
새 사건 묶음은 `data/events/<묶음 이름>/` 폴더를 만들어 넣으면 자동으로 읽힌다.

```json
{
	"id": "factory_offer",
	"category": "general",
	"tags": ["industry"],
	"title": "새로운 공장",
	"description": "한 기업이 마을 외곽에 큰 공장을 짓고 싶다고 제안했습니다.",
	"left_choice": {
		"text": "허가하지 않는다",
		"effects": { "finance": -4, "residents": -3 },
		"set_flags": [{ "flag": "factory_refused", "chance": 0.6 }]
	},
	"right_choice": {
		"text": "공장 건설을 허가한다",
		"effects": { "finance": 12, "environment": -10, "residents": 4 },
		"set_flags": ["factory_built"]
	}
}
```

| 필드 | 설명 |
|---|---|
| `id` | 전체에서 겹치면 안 됨 |
| `category` | `general`(조건 없음) / `state`(상태·턴 조건) / `delayed`(선택 후 N턴 뒤) |
| `tags` | 주제. 같은 태그가 연달아 나오지 않게 하는 데 쓰임 |
| `weight` | 선택. 추첨 가중치 (기본 10) |
| `priority` | 선택. 조건부 사건끼리 겹칠 때 높은 것이 먼저 (기본: delayed 50, state 30) |
| `conditions` | 조건부 사건만. 모두 만족해야 등장 |
| `text` | 선택지 버튼 문구 |
| `result` | 선택 후 결과 화면에 나오는 문구. 뒤에 지연 사건이 이어지는 선택이면 "나중에 무슨 일이 생길지 모른다"는 느낌을 담는다 (검사 도구가 해당 사건 목록을 알려 줌) |
| `effects` | 상태 id: 변화량. 상태 id는 `residents` `finance` `environment` `safety` |
| `set_flags` | 켤 플래그. `"이름"` 또는 `{"flag": "이름", "chance": 0.5}` |
| `clear_flags` | 끌 플래그 |

### 조건 종류

```json
{ "type": "stat", "stat": "finance", "op": "<=", "value": 20 }
{ "type": "turn", "op": ">=", "value": 15 }
{ "type": "flag", "flag": "factory_built", "min_age": 3 }
{ "type": "no_flag", "flag": "factory_settled" }
```

- `op`: `<` `<=` `>` `>=` `==` `!=`
- `flag`의 `min_age`는 "켜진 지 몇 턴 이상", `max_age`는 "몇 턴 이하"
- **지연 사건**은 `flag` + `min_age` 조건이 반드시 있어야 한다 (검사 도구가 확인)
- 같은 지연 사건 둘 중 하나만 나오게 하려면: 둘 다 같은 플래그를 켜고, 둘 다 `no_flag`로 그 플래그를 조건에 넣는다 (예: `factory_noise` / `factory_jobs`)

### 작성 규칙 (검사 도구가 경고로 알려 줌)

- 한 선택지는 1~3개 상태만 건드린다
- 좌/우 선택지가 건드리는 상태 조합이 같지 않게 한다 (힌트로 구별되도록)
- 효과 하나가 15를 넘지 않게 한다

## 확장

- **새 조건 종류**: `condition_evaluator.gd`의 `REQUIRED_FIELDS`에 등록하고 `check()`에 판정을 추가한다.
- **임기 종료 엔딩 분기**: `endings.json`에 `"type": "term_end"`, 조건, 더 높은 `priority`를 가진 엔딩을 추가한다. 조건 없는 기본 엔딩은 남겨 둔다.
- **다른 시작 마을**: `data/`와 같은 구조의 폴더를 만들고 `DataLoader.load_all("res://.../그 폴더")`로 읽는다.

## 주의

- **내보내기(export)**: JSON은 Godot 리소스가 아니라서 기본 설정으로는 빠진다. `export_presets.cfg`에 `*.json` 포함 설정이 이미 들어 있으니 지우지 않는다.
- **모듈 폴더 이름을 바꿀 때**: 스크립트의 `preload("res://village_sim/...")` 경로를 함께 바꾼다. (JSON 데이터 경로는 자동 계산)
- UI는 1차 프로토타입용 최소 화면이다. 최종 UI는 VISUAL_SPEC.md 이후 `scripts/game/`과 `scenes/`만 새로 만들면 된다. 규칙 코드는 그대로 쓴다.
