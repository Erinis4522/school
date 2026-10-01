# 마을 운영 시뮬레이션

초등 사회 교과와 연계할 수 있는 마을 운영 선택형 시뮬레이션 게임입니다. (Godot 4 / GDScript, Windows 데스크톱)

플레이어는 마을 운영자가 되어 계속 일어나는 사건마다 두 가지 선택 중 하나를 고릅니다.
선택은 주민·재정·환경·안전 네 상태에 영향을 주고, 어떤 선택은 몇 턴 뒤 다른 사건으로 돌아옵니다.
하나라도 바닥나면 그 상태에 맞는 결말로 끝나고, 30턴을 버티면 임기를 마칩니다.

## 플레이

- **웹에서 바로**: https://erinis4522.github.io/school/ (크롬·엣지 권장, 설치 필요 없음)
- **Windows 프로그램**: Releases에서 `마을운영.exe`를 받아 더블클릭합니다. 설치할 필요가 없습니다.
  (서명하지 않은 파일이라 처음에 Windows 경고가 뜨면 "추가 정보 → 실행")

## 문서

| 문서 | 내용 |
|---|---|
| [GAME_SPEC.md](GAME_SPEC.md) | 게임 기획 원칙 |
| [EVENT_CATALOG.md](EVENT_CATALOG.md) | 사건 설계 초안 (실제 데이터는 JSON이 기준) |
| [village_game/village_sim/README.md](village_game/village_sim/README.md) | 폴더 구조, 사건 추가 방법, 밸런싱 도구, 빌드 방법 |

## 개발 환경 준비

1. [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/) (Windows, 표준 버전)을 받아 `tools/godot/`에 풉니다.
2. 같은 폴더에 빈 파일 `._sc_`를 만듭니다. (Godot 설정을 이 폴더 안에만 저장)
3. exe를 만들려면 Godot 편집기에서 "편집기 → 내보내기 템플릿 관리"로 템플릿을 설치합니다.
4. `village_game/build_exe.ps1`을 실행하면 `build/마을운영.exe`가 만들어집니다.
5. `village_game/publish_web.ps1`을 실행하면 웹 버전을 만들어 GitHub Pages(gh-pages 브랜치)에 올립니다.

```
coding/
├─ GAME_SPEC.md
├─ EVENT_CATALOG.md
├─ village_game/        Godot 프로젝트 (project.godot)
│  ├─ build_exe.ps1     exe 만들기
│  └─ village_sim/      게임 모듈 (코드 + 사건 데이터)
├─ tools/godot/         휴대용 Godot (저장소에는 포함하지 않음)
└─ build/               만들어진 exe (저장소에는 포함하지 않음)
```
