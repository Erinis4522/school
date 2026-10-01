# village_sim — 마을 운영 시뮬레이션 모듈

게임 전체가 이 폴더 하나에 들어 있다. 규칙 코드(`scripts/core`)는 사건 내용을 모르고, 사건·엔딩·인물·수치는 모두 `data/`의 JSON에 있다.
**사건을 추가하거나 수치를 조정할 때 코드는 고치지 않는다.**

## 폴더 구조

```
village_sim/
├─ data/                        ← 밸런싱·사건 추가는 여기만 고친다
│  ├─ config/game_config.json   최대 턴, 막(1~3막), 상태 초기값, 효과 배율, 추첨 규칙
│  ├─ events/                   사건 (하위 폴더 포함 모든 .json을 자동으로 읽음)
│  │  └─ base/                  주제별 파일 + state.json(위기·턴·정책 누적) + final.json(최종 사건)
│  ├─ endings/endings.json      붕괴 엔딩 4개 + 임기 종료 엔딩 3개
│  ├─ npcs/npcs.json            인물 8명 (이름, 역할, 신경 쓰는 상태, 기본 반응 대사, 처음 만날 때 자기소개)
│  ├─ dialogue/debates.json     사건마다 왼쪽·오른쪽을 지지하는 인물과 그 한마디 (찬반 대화)
│  ├─ story/story.json          새 게임 첫 인사(루카), 10·20턴 중간 결산 문구
│  └─ visuals/                  title.json(타이틀 버튼 위치), backgrounds.json(상황별 배경 규칙), village_layers.json(겹침 레이어)
├─ assets/                      그림 (넣는 법은 assets/README.md)
│  ├─ title/ characters/ backgrounds/   타이틀, 인물 24장(8명 × 3표정), 상황별 배경 5장
│  ├─ ui/ endings/              화면 요소·엔딩 그림을 넣는 곳
│  ├─ placeholders/             임시 도트 그림. 실제 그림이 없을 때만 쓰인다
│  └─ fonts/                    한글 글꼴 (Noto Sans KR, OFL)
├─ scripts/
│  ├─ core/                     게임 규칙 (노드·UI와 무관)
│  │  ├─ game_state.gd          한 판의 상태 (상태값, 플래그와 켜진 턴, 본 사건, 올린 횟수, 회상 기록)
│  │  ├─ game_session.gd        턴 흐름, 막, 중간 결산, 인물·대사 붙이기. UI와 시뮬레이터가 함께 쓴다
│  │  ├─ event_manager.gd       다음 사건 고르기 (최종 → 조건부 → 현재 막의 일반)
│  │  ├─ condition_evaluator.gd 조건 판정 (사건·엔딩·대사·배경 공용)
│  │  ├─ effect_manager.gd      효과 적용, 힌트(방향·강도) 계산
│  │  ├─ ending_resolver.gd     엔딩 판정
│  │  └─ visual_layers.gd       (향후) 켜야 할 배경 레이어 목록 계산
│  ├─ data/                     JSON 읽기와 검증
│  └─ game/                     화면 (1차 프로토타입용 UI)
│     ├─ asset_library.gd       그림 찾기: 실제 그림 → 임시 그림 순서 (깜빡임·프레임 그림 포함)
│     ├─ portrait_view.gd       인물 초상: 얼굴 쪽 잘라 보이기, 숨쉬기, 등장, 눈 깜빡임, 반응 흔들림
│     ├─ title_screen.gd        타이틀 (새 게임 / 종료)
│     ├─ ui_style.gd            공통 색·상자 스타일 (최종 디자인 때 여기만 바꾸면 됨)
│     └─ village_backdrop.gd    상황별 배경 전환(서서히) + 겹침 레이어 켜고 끄기·미세 움직임
├─ scenes/                      main / title / game / ending
└─ tools/                       개발용 도구 (게임에는 포함되지 않음)
```

## 한 판의 흐름 (30턴)

| 막 | 턴 | 성격 |
|---|---|---|
| 임기 초반 (`early`) | 1~10 | 1~2개 상태만 건드리는 단순한 사건. 뒤에 결과가 돌아올 "씨앗" 선택이 많다. 지연 사건은 30% 확률로만 끼어든다 |
| 임기 중반 (`mid`) | 11~20 | 초반 선택의 결과(지연 사건)가 본격적으로 돌아온다 |
| 임기 후반 (`late`) | 21~30 | 여러 상태가 얽힌 사건, 과거 선택을 기억하는 인물의 대사, 한쪽 정책 누적으로 생긴 갈등. 30턴은 최종 사건 |

- 타이틀(새 게임 / 종료) → **새 게임**을 누르면 안내원 루카가 첫 인사와 짧은 안내를 한다 (`story.json`의 `opening`)
- 인물이 그 판에서 **처음 등장하면**, 그 인물의 질문 앞에 자기소개가 한 번 나온다 (`npcs.json`의 `intro`)
- 10턴과 20턴이 끝나면 **중간 결산** 카드: 마을 분위기(숫자 없이 문장)와 그 막의 주요 결정 회상
- 30턴 **최종 사건**의 선택에 따라 임기 종료 엔딩이 달라진다. 엔딩에서는 임기 동안의 주요 결정을 돌아본다
- 배경: 위험 기준(30) 이하인 상태 중 가장 낮은 상태에 맞는 배경(pollution / poor / complain / danger)으로, 없으면 normal로 서서히 바뀐다

### 한 턴 (미연시처럼: 베이지색 메인 창 가운데에 인물, 아래에 둥근 대화창)

(처음 보는 인물이면 자기소개)
→ **안건 소개**: 안건을 올린 인물이 서고, 대화창 이름표에 사건 제목, 내용에 사건 설명
→ **왼쪽 의견**: 왼쪽 선택지를 지지하는 인물의 한마디 → **오른쪽 의견**: 오른쪽을 지지하는 인물의 한마디
→ **선택**: 메인 창의 왼쪽/오른쪽을 누르면 그쪽 지지자의 **인물 카드가 메인 창 뒤에서 비스듬히 펼쳐져 나온다**
  인물 카드: 위에 인물 그림, 아래 글 칸에 이름·선택지 문구·예상 변화 [아이콘] + 화살표 (↑ 조금 / ↑↑ 크게, 초록 오름 / 빨강 내림, 숫자는 없음)
  반대쪽을 누르면 카드가 바뀌고, 같은 쪽을 한 번 더 누르면 결정
→ **반응**: 인물 카드는 들어가고, 고른 쪽 지지자가 가운데에 올라와 기뻐하며 한마디. 대화창 아래에 결과 문구.
  영향받은 상태 아이콘은 오르면 튀며 밝아지고, 내리면 흔들리며 어두워진다
→ 아무 곳이나 눌러 다음 사건

**찬반 대화 고치기**: `data/dialogue/debates.json`에서 사건마다 `left` / `right`의 `npc`(지지하는 인물)와 `line`(한마디)을 고친다.
양쪽 인물은 달라야 한다(검사 도구가 알려 줌). 대화가 없는 사건은 자기소개만 하고 바로 선택으로 간다.
반응 대사는 그 인물의 기쁜 표정 기본 대사(`npcs.json`의 `lines.happy`)에서 나온다. 고른 쪽 지지자가 사건을 올린 인물이고 선택지에 `reaction`이 있으면 그 대사가 나온다.

선택지마다 다른 인물을 세우려면 선택지에 `npc`를 적는다 (예: 왼쪽은 환경 지킴이, 오른쪽은 개발회사 대표). 없으면 사건의 인물이 양쪽 카드에 나온다.

인물의 반응은 따로 적지 않아도 자동으로 나온다. 그 인물이 신경 쓰는 상태(`npcs.json`의 `concern`)가 오르면 happy, 조금 내리면 worried, 크게 내리면 angry, 그대로면 neutral. 대사는 그 인물의 표정별 기본 대사(`lines`) 중 하나. 중요한 사건은 선택지에 `reaction` / `reaction_expression`으로 직접 적는다.

키보드: ← / → 로 같은 동작, Enter / Space 로 결정·다음. 상태 게이지는 오른쪽 위.

## 배포용 실행 파일 만들기

`village_game/build_exe.ps1`을 실행하면 데이터를 검사한 뒤 `build/마을운영.exe` 한 파일을 만든다.
받는 사람은 설치 없이 더블클릭으로 실행한다. (서명하지 않은 파일이라 처음에 Windows 경고가 뜨면 "추가 정보 → 실행")
Godot은 `coding/tools/godot/`의 휴대용 버전을 쓰며, 내보내기 템플릿도 그 폴더 안에 있다.

## 웹 버전 (최종 버전에서만)

웹 버전은 최종 버전에서, 요청이 있을 때만 올린다. 평소 수정 중에는 실행하지 않는다.
`village_game/publish_web.ps1`을 실행하면 데이터를 검사한 뒤 웹 버전을 만들어 `gh-pages` 브랜치에 올린다.
몇 분 뒤 https://erinis4522.github.io/school/ 에 반영된다. (만들기만 하려면 `-NoPublish`)

## 도구

프로젝트 폴더(`project.godot`가 있는 곳)에서 실행한다. `godot`은 `../tools/godot/Godot_v4.7.2-stable_win64_console.exe`로 바꾼다.

| 목적 | 명령 |
|---|---|
| 데이터 검사 | `godot --headless --script res://village_sim/tools/validate_data.gd` |
| 밸런스 시뮬레이션 | `godot --headless --script res://village_sim/tools/balance_sim.gd -- --runs=1000` |
| 화면 흐름 점검 | `godot --headless --script res://village_sim/tools/ui_smoke_test.gd` |
| 임시 그림 다시 만들기 | `godot --headless --script res://village_sim/tools/make_placeholders.gd` |

- 데이터 검사는 게임을 켤 때도 자동으로 돌아 출력 창에 결과가 나온다. 막별 사건 수와 선택지당 평균 상태 수, 인물별 등장 수도 알려 준다.
- 시뮬레이션 보고서는 `balance_reports/`에 마크다운으로 저장된다. 수정 전후 보고서를 비교하면 된다.

## 밸런싱 순서

1. 수치를 고친다 (아래 "조절 손잡이")
2. 데이터 검사 → 오류 0개 확인
3. 시뮬레이션 → 보고서 확인
   - **임기 완주율**: random이 너무 높으면 쉽고, careful이 낮으면 어렵다
   - **엔딩 분포**: 한 상태의 붕괴만 몰려 있으면 그 상태의 증감 폭을 본다
   - **정답 의심 사건**: careful이 한쪽만 고르는 사건. 지연 사건으로 균형을 맞춘 사건이면 두어도 된다
   - **막별로 지난 선택과 이어진 턴의 비율**: 초반은 낮고 중반·후반은 높아야 한다
4. 직접 플레이해 보고 체감 확인

### 조절 손잡이

| 무엇을 | 어디서 |
|---|---|
| 최대 턴, 막 구간 | `game_config.json` → `max_turns`, `acts[].from / to` |
| 막별로 지연 사건이 끼어드는 정도 | `game_config.json` → `acts[].follow_up_chance` (초반 0.3) |
| ↑ 와 ↑↑ 를 나누는 기준 | `game_config.json` → `strong_effect` (기본 8 이상이면 "크게") |
| 상태 초기값 | `game_config.json` → `stats[].initial` |
| 한 상태의 증감을 한꺼번에 키우거나 줄이기 | `game_config.json` → `effect_scale` (예: 재정 감소를 20% 줄이려면 `"finance": {"gain": 1.0, "loss": 0.8}`) |
| 비슷한 주제 연속 등장 억제 | `game_config.json` → `selection.recent_tag_window`, `recent_tag_weight` |
| 사건이 어느 막에 나올지 | 사건의 `phases` |
| 사건이 자주/드물게 나오게 | 사건의 `weight` (기본 10, 결과가 돌아오는 "씨앗" 사건은 18) |
| 조건부 사건끼리 순서 | 사건의 `priority` (위기 100, 지연 50, 턴 40, 정책 누적 30) |
| 지연 사건이 나오는 시점 | 지연 사건 조건의 `min_age` |
| 지연 사건이 이어질 확률 | 원래 사건 선택지의 `set_flags` → `chance` |
| 정책 누적 갈등이 나오는 기준 | `state.json`의 `trend` 조건 (그 상태를 올린 선택 횟수) |
| 위기 사건 기준 | `events/base/state.json`의 위기 사건 조건 값 (기본 20) |
| 붕괴 기준 | `endings/endings.json`의 붕괴 엔딩 조건 값 (기본 0) |
| 중간 결산 시점·문구 | `story/story.json` |

## 사건 추가

`data/events/` 아래 아무 .json 파일에 추가하거나 새 파일을 만든다. 파일에는 사건 하나(객체) 또는 여러 개(배열)를 넣을 수 있다.
새 사건 묶음은 `data/events/<묶음 이름>/` 폴더를 만들어 넣으면 자동으로 읽힌다.

```json
{
	"id": "greenbelt",
	"npc": "developer",
	"phases": ["late"],
	"description_variants": [
		{ "conditions": [{ "type": "flag", "flag": "factory_built" }], "text": "\"공장 때 믿어 주신 덕분에…\"" },
		{ "conditions": [{ "type": "flag", "flag": "factory_declined" }], "text": "\"공장 때는 거절하셨지요…\"" }
	],
	"category": "general",
	"tags": ["administration"],
	"title": "개발 제한 구역",
	"description": "개발이 금지된 땅의 주인들이 제한을 풀어 달라고 요청했습니다.",
	"left_choice": {
		"text": "제한을 푼다",
		"memory": "개발 제한 구역을 풀어 줌",
		"result": "그 땅에 건물이 들어서기 시작했고 세금도 더 걷힙니다. …",
		"effects": { "finance": 10, "environment": -9, "residents": 2 }
	},
	"right_choice": {
		"text": "제한을 유지한다",
		"result": "마을 둘레의 숲과 들판은 그대로입니다. …",
		"effects": { "environment": 3, "residents": -4 }
	}
}
```

| 필드 | 설명 |
|---|---|
| `id` | 전체에서 겹치면 안 됨 |
| `category` | `general`(조건 없음) / `state`(상태·턴 조건) / `delayed`(선택 후 N턴 뒤) / `final`(마지막 턴의 최종 사건) |
| `phases` | 일반 사건이 나올 막: `early` `mid` `late` 중 여러 개 가능. 없으면 모든 막 |
| `npc` | 등장인물 id (`npcs/npcs.json`). 카드에 "역할 · 이름"과 초상으로 보인다 |
| `npc_expression` | 사건 카드에서 인물의 표정. 기본 `neutral` (`happy` `angry` `worried`, 또는 그림 파일 이름과 같은 새 표정) |
| `description_variants` | 과거 선택에 따라 바뀌는 설명. 위에서부터 조건이 처음 맞는 문구를 쓴다. 없거나 안 맞으면 `description` |
| `tags` | 주제. 같은 태그가 연달아 나오지 않게 하는 데 쓰임 |
| `weight` | 선택. 추첨 가중치 (기본 10) |
| `priority` | 선택. 조건부·최종 사건끼리 겹칠 때 높은 것이 먼저 |
| `conditions` | 조건부·최종 사건만. 모두 만족해야 등장 |
| `text` | 선택지 문구 |
| `result` | 선택 후 결과 카드 문구. 뒤에 지연 사건이 이어지는 선택이면 "나중에 무슨 일이 생길지 모른다"는 느낌을 담는다 |
| `memory` | 선택. 중간 결산·엔딩에서 회상할 짧은 문구 (예: "공장 건설을 허가함") |
| `reaction` | 선택. 결정 직후 사건 인물의 말풍선 대사. 없으면 인물의 기본 대사 |
| `reaction_expression` | 선택. 그때 인물의 표정. 없으면 자동 (인물이 신경 쓰는 상태의 변화로 결정) |
| `effects` | 상태 id: 변화량. 상태 id는 `residents` `finance` `environment` `safety` |
| `set_flags` | 켤 플래그. `"이름"` 또는 `{"flag": "이름", "chance": 0.5}` |
| `clear_flags` | 끌 플래그 |

### 조건 종류

```json
{ "type": "stat", "stat": "finance", "op": "<=", "value": 20 }
{ "type": "turn", "op": ">=", "value": 15 }
{ "type": "flag", "flag": "factory_built", "min_age": 3 }
{ "type": "no_flag", "flag": "factory_settled" }
{ "type": "trend", "stat": "environment", "op": ">=", "value": 6 }
```

- `op`: `<` `<=` `>` `>=` `==` `!=`
- `flag`의 `min_age`는 "켜진 지 몇 턴 이상", `max_age`는 "몇 턴 이하"
- `trend`는 "그 상태를 올린 선택을 지금까지 몇 번 했는지". 한쪽 정책이 누적됐을 때의 갈등 사건에 쓴다
- **지연 사건**은 `flag` + `min_age` 조건이 반드시 있어야 한다 (검사 도구가 확인)
- 같은 지연 사건 둘 중 하나만 나오게 하려면: 둘 다 같은 플래그를 켜고, 둘 다 `no_flag`로 그 플래그를 조건에 넣는다 (예: `factory_noise` / `factory_jobs`)
- 거절한 선택도 나중에 인물이 기억하게 하려면 거절 쪽에도 플래그를 켠다 (예: `factory_declined`, `mall_declined`)

### 작성 규칙 (검사 도구가 경고로 알려 줌)

- 한 선택지는 1~3개 상태만 건드린다. 초반(`early`) 사건은 1~2개 위주
- 좌/우 선택지의 힌트(방향·강도)가 같지 않게 한다
- 효과 하나가 15를 넘지 않게 한다

## 확장

- **새 조건 종류**: `condition_evaluator.gd`의 `REQUIRED_FIELDS`에 등록하고 `check()`에 판정을 추가한다.
- **임기 종료 엔딩 분기**: `endings.json`에 `"type": "term_end"`, 조건, 더 높은 `priority`를 가진 엔딩을 추가한다. 조건 없는 기본 엔딩은 남겨 둔다.
- **그림 교체**: `assets/README.md`의 이름대로 `assets/` 아래에 그림을 넣으면 임시 그림 대신 쓰인다. 코드는 고치지 않는다.
- **마을 배경 변화**: `data/visuals/`에 레이어(id + 조건)가 정의되어 있고, 조건이 맞으면 `assets/backgrounds/layers/<id>` 그림이 서서히 나타난다. 레이어를 늘리려면 정의를 추가하고 같은 이름의 그림을 넣는다.
- **다른 시작 마을**: `data/`와 같은 구조의 폴더를 만들고 `DataLoader.load_all("res://.../그 폴더")`로 읽는다.

## 주의

- **내보내기(export)**: JSON은 Godot 리소스가 아니라서 기본 설정으로는 빠진다. `export_presets.cfg`에 `*.json` 포함 설정이 이미 들어 있으니 지우지 않는다.
- **모듈 폴더 이름을 바꿀 때**: 스크립트의 `preload("res://village_sim/...")` 경로를 함께 바꾼다. (JSON 데이터 경로는 자동 계산)
- UI는 1차 프로토타입용 화면이다. 최종 UI는 VISUAL_SPEC.md 이후 `scripts/game/`과 `scenes/`만 새로 만들면 된다. 규칙 코드는 그대로 쓴다.
