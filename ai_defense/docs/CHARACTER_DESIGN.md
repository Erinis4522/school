# AI 디펜스 캐릭터 설계 v2 (2026-11-11)

v1은 8명이 모두 비슷한 또래 여자 캐릭터였다. 초등~중학생이 체험하는 프로그램이므로 **성별·나이·생김새가 다양한 인물**로 다시 설계했다.
역할(공격 방식·수치·AI 판단)은 그대로이고, **사람(이름·나이·성격·외형)만 바뀌었다.** 게임 데이터는 `data/heroes.json`.

## 1. 구성 원칙
- 성별 4 : 4 (남 — 소년 2, 중년 1, 노인 1 / 여 — 소녀·청소년 3, 노인 1)
- 나이 11~72살. 학생 또래(11·13·15·17·19)와 어른(45), 할아버지·할머니(68·72)
- 피부색도 한 가지로만 하지 않음 (대장장이 아저씨는 갈색 피부)
- 모두 **"우리 마을 사람들"**: 견습 기사, 숲지기, 등대지기, 대장장이, 설산 마을 마법사, 꼬마 발명가, 불꽃놀이 장인, 도서관 사서
- 명랑한 판타지, 초등학생에게 친숙하고 중학생에게 너무 유아적이지 않게 (PRD 7.1)
- 색만 다르게 하지 말고 **실루엣·소품·머리 모양**으로 구분

## 2. 인물 표

| 역할 | 이름 | 나이·직업 | 성별 | 성격 한 줄 | 실루엣 핵심 | 그림 상태 |
|---|---|---|---|---|---|---|
| 검객 | 윤한결 | 15살 견습 기사 | 남 | 겁 많지만 친구 앞에선 먼저 나섬 | 둥근 방패 + 짧은 검, 삐죽 머리 | 임시 (v1 벡터 리그) |
| 궁수 | 나래 | 13살 숲지기 | 여 | 눈이 좋고 조용함 | 포니테일, 초록 망토, 활 | **완료** (v1 그림 유지) |
| 저격수 | 백석 할아버지 | 72살 은퇴한 등대지기 | 남 | 느긋하고 정확함 | 선장 모자, 흰 수염, **모노클**, 긴 석궁 | 도형 임시 |
| 화염술사 | 강철수 아저씨 | 45살 마을 대장장이 | 남 | 호탕하게 잘 웃음 | 빨간 반다나, 주황 앞치마, **불꽃 망치**, 큰 체격 | 도형 임시 |
| 빙결술사 | 서리 | 17살 설산 마을 마법사 | 여 | 차분하고 다정함 | 긴 은발, 하늘색 외투, 얼음 결정 지팡이 | **완료** (v1 그림 유지) |
| 번개술사 | 이도윤 | 11살 꼬마 발명가 | 남 | 실패해도 웃는 실험광 | 이마 고글, 부스스한 머리, 보라 조끼, 직접 만든 전도봉 | 도형 임시 |
| 폭탄공학자 | 말순 할머니 | 68살 불꽃놀이 장인 | 여 | 노련하고 장난기 있음 | 쪽진 백발 + 두건, 고글, 공구 벨트, 둥근 폭탄 | 도형 임시 |
| 표식술사 | 하은 | 19살 별빛 도서관 사서 | 여 | 꼼꼼하고 동료를 잘 챙김 | 베레모, 긴 머리, 마법 책·두루마리, 빛나는 표식 | **완료** (v1 그림 유지) |

PRD 7.3 실루엣 키워드에서 바뀐 점: 화염술사 "주황 망토 + 불꽃 지팡이" → **주황 앞치마 + 불꽃 망치**(대장장이). 나머지 키워드(방패+검, 후드+활, 석궁+모노클, 얼음 결정, 보라 전도봉+번개, 고글+공구 벨트+폭탄, 두루마리+표식)는 유지.

## 3. 새로 그려야 할 그림

| 파일 (`assets/heroes/`) | 인물 | 비고 |
|---|---|---|
| `sniper.png` | 백석 할아버지 | 전신 |
| `fire.png` | 강철수 아저씨 | 전신 |
| `lightning.png` | 이도윤 | 전신 |
| `bomb.png` | 말순 할머니 | 전신 |
| `sword.png` + `rigs/sword/` | 윤한결 | 지금 리그는 v1 "swordswoman". **머리 파츠 3장(`head_face`, `hair_front`, `hair_back`)만 소년으로 다시 그려도** 몸·팔·검 관절 애니메이션은 그대로 쓸 수 있음. 카드용 `sword.png`도 함께 교체 |

그림이 들어오기 전까지는 `look` 값으로 그린 **도형 SD 인물**이 대신 나오고, 대기·공격·특기 모션도 똑같이 적용된다.
그림을 넣으면 자동으로 그림이 우선한다 (재빌드 없이 exe 옆 `assets/heroes/`에 넣어도 됨).

## 4. 그림 규칙 (v1 완료 3종과 맞추기)
- SD(2.5~2.8 등신) 애니메 일러스트, 정면에서 약간 비스듬히, 전신, **발이 이미지 아래쪽**
- 512×512 투명 PNG, 캐릭터는 가운데. 발밑 그림자 타원은 있어도 됨
- **흰 배경에서 오려 내지 말 것** (v1은 흰 테두리가 남아 `tools/defringe.gd`로 정리했음). 처음부터 투명 배경으로 출력
- 나래·서리·하은 그림과 선 굵기·채색 방식·조명 방향을 맞출 것
- 노인 캐릭터도 귀엽고 친근하게(SD), 희화화·과장된 주름 금지. 피부색은 표의 `look.skin` 값 참고

### 그림 생성/의뢰용 설명 예시
> SD chibi fantasy character, 2.6 heads tall, full body, front three-quarter view, standing idle pose, transparent background, 512x512, clean line art, soft cel shading, same style as the reference sheet.
> **72-year-old kind grandfather, retired lighthouse keeper**: navy captain's hat with a gold badge, short white beard, golden monocle on the right eye, navy coat with a mustard vest, holding a long wooden crossbow.

> **45-year-old village blacksmith**, warm brown skin, short black hair, red bandana, light stubble, broad shoulders, orange leather apron, holding a forge hammer with a small flame on its head, big friendly smile.

> **11-year-old boy inventor**, messy brown hair, goggles on the forehead, purple vest with yellow lightning patches, holding a homemade lightning rod staff with sparks.

> **68-year-old grandmother firework master**, grey hair in a bun under an olive headscarf, round goggles, maroon work jacket, tool belt, holding a round black bomb with a lit fuse, mischievous smile.

> **15-year-old apprentice knight boy**, spiky black hair, navy tunic with a steel chest plate, small round shield and short sword.
