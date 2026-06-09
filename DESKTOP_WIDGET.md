# Google 메시지 — 메뉴바 알림 + 바탕화면 위젯

[OpenMessage](https://github.com/MaxGhenis/openmessage)(Apache-2.0)를 포크해, Google 메시지(SMS/RCS)를
**메뉴바 깜빡임 + macOS 바탕화면 위젯**으로 보여주도록 확장한 것입니다.

- 문자가 오면 **메뉴바 아이콘이 깜빡이고 미확인 개수**가 표시됩니다.
- **바탕화면 위젯**에 최근 대화(연락처 + 한 줄 미리보기)와 전체 미확인 개수가 보입니다.
- 메뉴바 항목·드롭다운의 대화·위젯을 **클릭하면 앱이 열립니다**.

> RCS는 안드로이드폰에 묶여 있어 **폰과 1회 QR 페어링**이 필요합니다. 페어링 후에는 폰이 인터넷에만
> 연결돼 있으면 Mac 앱이 구글 서버와 직접 통신합니다(브라우저 불필요). 비공식 리버스 엔지니어링
> 프로토콜(`libgm`)을 쓰므로 구글이 변경하면 깨질 수 있습니다.

## 동작 구조

```
libgm(Go 백엔드, 127.0.0.1:7007)  ──/api/conversations, /api/events──┐
        │ 메시지 수신·로컬 SQLite 저장                                │
        ▼                                                            ▼
Swift 앱: InboxMonitor (SSE 구독 + 폴링)                    WidgetKit 위젯
  · 메뉴바 점 깜빡임 + 미확인 개수                            · localhost 직접 fetch
  · 최근 대화 드롭다운                                        · (오프라인 시 App Group 스냅샷 폴백)
  · 위젯 reload 트리거                                        · 탭 → openmessage:// → 앱 열기
```

추가/변경한 파일:

| 파일 | 역할 |
|------|------|
| `macos/OpenMessage/Sources/InboxShared.swift` | 앱·위젯 공용 모델(`InboxItem`/`InboxSnapshot`)·상수 |
| `macos/OpenMessage/Sources/InboxBackend.swift` | `/api/conversations`(+미리보기) fetch·디코딩(공용) |
| `macos/OpenMessage/Sources/InboxMonitor.swift` | SSE+폴링, 미확인 계산, 깜빡임, 스냅샷 기록·위젯 reload |
| `macos/OpenMessage/Sources/MenuBarView.swift` | 깜빡이는 메뉴바 라벨 + 최근 대화 목록 |
| `macos/OpenMessage/Sources/OpenMessageApp.swift` | InboxMonitor 연결, `openmessage://` 처리, 로그인 자동 실행 |
| `macos/Widget/` | WidgetKit 위젯(뷰·TimelineProvider·Info.plist·entitlements) |
| `macos/project.yml` | xcodegen 프로젝트(앱 + 위젯 익스텐션 2개 타깃) |
| `macos/build-with-widget.sh` | Go 유니버설 빌드 → xcodegen → xcodebuild → ad-hoc 서명 |

## 빌드 & 설치

필요: macOS 14+, Xcode, Go, `xcodegen`(`brew install xcodegen`).

```bash
cd messages-widget
./macos/build-with-widget.sh
cp -R macos/build/OpenMessage.app /Applications/ && xattr -cr /Applications/OpenMessage.app
open /Applications/OpenMessage.app
```

> 기존 `macos/build.sh`는 위젯 없이 앱만 빌드합니다. **위젯을 포함하려면 `build-with-widget.sh`를 쓰세요.**

## 사용법

1. **폰 페어링**: 앱 첫 실행 시 QR이 뜹니다. 안드로이드 Google 메시지 앱에서
   *설정 ▸ 기기 페어링 ▸ QR 스캔*으로 스캔하세요.
2. **위젯 추가**: 바탕화면 빈 곳을 우클릭 → *위젯 편집* → "Messages"(또는 OpenMessage) 검색 →
   바탕화면에 끌어다 놓기. (Medium / Large 크기 지원)
3. **자동 실행**: 앱이 로그인 항목으로 자동 등록됩니다. *시스템 설정 ▸ 일반 ▸ 로그인 항목*에서 끌 수 있습니다.

## 서명에 대한 메모

ad-hoc 서명으로 빌드되므로 **App Group 공유 컨테이너는 동작하지 않을 수 있습니다.** 이 경우 위젯은
백엔드(`localhost:7007`)를 직접 조회해 데이터를 가져오므로 정상 동작합니다. App Group 스냅샷은
백엔드가 잠시 꺼졌을 때의 오프라인 폴백으로만 쓰입니다. (유료 Apple Developer 계정으로 프로비저닝
프로파일을 넣으면 App Group도 활성화됩니다.)

## AI 기능 — 답장 추천 / 멘트 워싱 (로컬 Ollama)

대화 입력칸에 두 버튼이 있습니다(스크린샷의 입력칸 우측):
- **추천**: 현재 대화의 최근 메시지를 읽고 자연스러운 한국어 답장 1개를 제안 → 입력칸에 채움.
- **다듬기(멘트 워싱)**: 입력칸에 쓴 초안을 더 자연스럽고 정중하게 다듬어 교체.

**완전 로컬 처리** — API 키도, 로그인(OAuth)도, 클라우드 전송도 없습니다. 모든 추론은 본인 Mac의 [Ollama](https://ollama.com)에서 돌아갑니다.

### 설치(1회)
```bash
brew install --cask ollama-app   # 런너 포함된 정식 앱 (formula 'ollama'는 런너 누락 버그 있음)
open -a Ollama                    # 백그라운드 서버 시작(로그인 시 자동 실행)
ollama pull exaone3.5:7.8b        # 한국어 최강(LG). 또는 qwen2.5:7b / 가벼운 qwen2.5:3b
```

### 모델 변경(재빌드 불필요)
기본 모델을 바꾸려면 아래 파일에 모델명 한 줄을 적으세요(없으면 생성):
```
~/Library/Application Support/GoogleRCS/ai-model.txt   예: exaone3.5:7.8b
```
우선순위: 환경변수 `OPENMESSAGES_OLLAMA_MODEL` → `ai-model.txt` → 기본값(`exaone3.5:7.8b`).

### 동작 메모
- Ollama 서버가 꺼져 있으면 버튼이 친절한 안내 메시지를 띄웁니다(설치/실행/모델 받기).
- 백엔드 엔드포인트: `POST /api/suggest-reply`(`{conversation_id}`), `POST /api/polish`(`{text}`). 구현: `internal/web/ai.go`.
- **모델 품질 주의**: 작은 `qwen2.5:3b`는 한국어를 가끔 영어/일어로 섞습니다. 한국어 품질이 중요하면 `exaone3.5:7.8b` 권장.

## 추가 기능 (대화 관리)

- **방 삭제**: 사이드바 대화 우클릭 → **방 삭제** → 폰(Google 메시지)과 앱에서 모두 삭제. (백필로 생긴 빈 방 정리에 유용)
- **발신 SIM 선택(듀얼심)**: 입력칸의 **SIM 버튼**(듀얼심일 때만 표시) → SIM 선택 → 그 대화의 기본 발신 SIM으로 **영속 저장**. 모델 변경처럼 한 번 고르면 유지됨. (SIM 목록은 연결 후 잠시 뒤 폰에서 자동 수신)
- **계정 변경**: 설정 → Google Messages → **계정 변경** → 연결 해제 후 새 계정 QR/로그인.
- **RCS 실패 시 MMS 폴백**: 앱은 RCS를 강제하지 않으므로 **폰이 자동으로 SMS/MMS로 폴백**합니다. 추가로 앱이 RCS 전송 실패를 감지하면 **1회 자동 재전송**(폰이 SMS/MMS로 라우팅). 폰에서 *Google 메시지 → 설정 → RCS 채팅 → "RCS 메시지 실패 시 SMS/MMS로 자동 재전송"* 을 켜두세요.

## 검증 상태

- ✅ 앱 + 위젯 빌드/서명, 위젯 익스텐션 시스템 등록(`pluginkit`) 확인.
- ✅ InboxMonitor가 백엔드에서 대화·미리보기를 가져와 미확인 개수·스냅샷을 계산함을 실제 앱에서 확인
  (폰 없이 DB에 가짜 미읽음 대화를 주입해 검증).
- ✅ AI 버튼이 설치된 앱 UI에 표시되고, `/api/polish`·`/api/suggest-reply`가 로컬 Ollama로 실제 한국어 결과를 반환함을 확인.
- ⏳ 실제 문자 수신 → 깜빡임/위젯 표시, 바탕화면 위젯 배치, AI 버튼 클릭→입력칸 반영은 **폰 페어링 + GUI 조작이 필요**해 사용자가 최종 확인.
