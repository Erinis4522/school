# 그림 넣는 곳

이 폴더에 **정해진 이름으로 그림 파일을 넣으면 게임이 자동으로 그 그림을 씁니다.** 코드는 고치지 않습니다.
같은 이름의 파일을 덮어쓰면 그림이 바뀝니다. 파일이 없으면 `placeholders/`의 임시 그림을 대신 쓰거나(인물·아이콘), 그냥 안 보입니다.

- 형식: `.png` `.webp` `.jpg` `.svg` (같은 이름이 여러 개면 png → webp → jpg → svg 순서)
- 그림을 넣은 뒤 Godot 편집기로 프로젝트를 한 번 열거나 `build_exe.ps1`을 실행하면 자동으로 가져옵니다(import).
- 큰 그림은 화면에 맞게 줄여서 부드럽게(밉맵) 보여 주고, 작은 도트 그림을 키울 때는 또렷하게(Nearest) 보여 줍니다. 자동으로 고릅니다.
- 큰 일러스트(인물·배경·타이틀)는 실행 파일 크기를 줄이려고 고화질 손실 압축(품질 0.85)으로 가져옵니다. 새로 넣은 큰 그림도 같게 하려면 Godot 편집기의 가져오기(Import) 탭에서 압축 모드를 Lossy로 바꿉니다.

## 타이틀

```
title/title.png        첫 화면 그림 (지금: 1672 × 941)
```

그림 안에 그려진 "새 게임" / "종료" 버튼 위에 투명한 Godot 버튼이 겹쳐 있습니다.
버튼 위치는 `data/visuals/title.json`의 `rect` (그림 원본 픽셀 기준 x, y, 너비, 높이). 타이틀 그림을 바꾸면 이 숫자만 맞춥니다.

## 인물

```
characters/<인물 id>_<표정>.png       예: characters/luka_delight.png
```

(`characters/<인물 id>/<표정>.png` 처럼 인물마다 폴더를 나눠도 됩니다)

| 인물 id | 이름 · 역할 | 맡는 사건 |
|---|---|---|
| luka | 루카 · 마을 안내원 | 첫 인사, 주민 관련 사건 |
| bruno | 브루노 · 개발회사 대표 | 개발·건설 |
| cain | 케인 · 안전 담당관 | 시설·안전 |
| noel | 노엘 · 환경 지킴이 | 환경 |
| cherry | 체리 · 상인회장 | 상권·재정 |
| owen | 오웬 · 기획 주무관 | 행정·예산 |
| mina | 미나 · 청소년 대표 | 학생·청년 |
| rio | 리오 · 마을 주민 | 들판·골목 |

**표정**: 그림은 `neutral`(기본) · `delight`(기쁨) · `sad`(슬픔) 세 가지입니다.
게임 속 표정은 이렇게 연결됩니다: happy → delight / worried·angry → sad / neutral → neutral.
나중에 `angry.png`, `worried.png`, `happy.png`를 따로 넣으면 그 그림이 먼저 쓰입니다. (연결 규칙: `scripts/game/asset_library.gd`의 `EXPRESSION_ALIASES`)

- 인물 그림은 세로가 긴 그림(지금 1248 × 1824)입니다. 카드에서는 위쪽(얼굴과 상반신)을 기준으로 잘라 보여 줍니다.
- `<이름>_blink.png` (예: `luka_neutral_blink.png`)를 넣으면 가끔 눈을 깜빡입니다. 없으면 깜빡이지 않습니다.
- 정적인 그림이어도 게임이 아주 미세한 숨쉬기, 등장(아래에서 슥), 반응 흔들림을 붙입니다.
- 인물을 늘리려면 `data/npcs/npcs.json`에 추가하고 같은 id로 그림을 넣습니다.

## 마을 배경 (상황별)

```
backgrounds/normal.png       평소
backgrounds/pollution.png    환경이 위험할 때
backgrounds/poor.png         재정이 위험할 때
backgrounds/complain.png     주민이 위험할 때
backgrounds/danger.png       안전이 위험할 때
```

- 위험 기준(지금 30) 이하인 상태가 있으면 그중 **값이 가장 낮은 상태**의 배경으로 0.6초 동안 서서히 바뀝니다. 회복되면 다른 배경이나 `normal`로 돌아갑니다.
- 기준값, 상태별 배경 이름, 바뀌는 시간은 `data/visuals/backgrounds.json`에 있습니다.

### 배경 위 겹침 레이어 (선택, 지금은 그림 없음)

```
backgrounds/layers/<레이어 id>.png          조건에 따라 배경 위에 겹쳐 켜지는 투명 그림
backgrounds/layers/<레이어 id>_1.png, _2.png …   (선택) 프레임 애니메이션 — 번호 순서대로 번갈아 나옵니다
```

공장·공원·연기 같은 작은 변화를 배경 위에 겹치고 싶을 때 씁니다. 레이어 목록·조건·미세 움직임(`frames` 프레임 교대, `drift` 떠다님, `sway` 흔들림, `flicker` 깜빡임)은 `data/visuals/village_layers.json`에 있고, 그림이 없는 레이어는 그냥 안 보입니다.

## 화면 요소 (지금은 임시 도트 그림)

```
ui/icons/residents.png  ui/icons/finance.png  ui/icons/environment.png  ui/icons/safety.png   상태 아이콘
ui/arrow_up.png  ui/arrow_down.png    오름/내림 화살표
ui/card_frame.png                     카드 틀 (9분할로 늘려 씀. 바깥 6픽셀은 늘어나지 않음)
ui/choice.png                         선택할 때 메인 창 위에 뜨는 "당신의 선택은?" 안내 그림 (지금: 실제 그림, 투명 배경)
```

- `choice.png`는 폭 400픽셀로 줄여 메인 창 위 테두리에 살짝 겹쳐 보여 줍니다. 크기·겹침 정도는 `scripts/game/game_screen.gd`의 `BANNER_WIDTH`, `BANNER_OVERLAP`. 그림이 없으면 안 뜹니다.
- 초상화의 둥근 모서리와 테두리(둥글기·색·굵기)는 `ui_style.gd`의 `PORTRAIT_RADIUS`, `PORTRAIT_BORDER`, `PORTRAIT_BORDER_WIDTH`.

색·글자 크기 같은 나머지 화면 스타일은 `scripts/game/ui_style.gd` 한 곳에 모여 있습니다.

## 소리

```
audio/bgm/village_theme.ogg     배경음 (반복 재생)
audio/sfx/button.ogg            버튼 누를 때 (타이틀, 다시 시작)
audio/sfx/advance.ogg           대사·결과를 넘길 때
audio/sfx/card_out.ogg          인물 카드가 펼쳐질 때
audio/sfx/card_select.ogg       선택을 결정할 때
```

- 형식: `.ogg` `.wav` `.mp3` (같은 이름이 여러 개면 ogg → wav → mp3 순서). 배경음은 **ogg** 권장 (자동으로 반복 재생됨)
- 지금은 코드로 합성한 임시 소리(`placeholders/audio/`)가 나옵니다. 다시 만들려면 `tools/make_sounds.gd`
- 상황별로 어떤 파일을 쓸지, 배경음·효과음 크기는 `data/audio/audio.json`에서 정합니다.
  예: 타이틀과 게임 배경음을 다르게 하려면 `"bgm": {"title": "title_theme", "game": "village_theme"}` 로 바꾸고 `audio/bgm/title_theme.ogg`를 넣습니다.
- 압축된 wav를 배경음으로 쓰면 Godot 가져오기(Import) 설정에서 Loop Mode를 Forward로 바꿔야 반복됩니다. (ogg는 신경 쓰지 않아도 됨)

## 엔딩 그림 (선택)

```
endings/<엔딩 id>.png     예: endings/term_growth.png, endings/collapse_finance.png
```

엔딩 id는 `data/endings/endings.json`에 있습니다. 그림이 없으면 글만 나옵니다.
