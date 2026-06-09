# Android Message for Mac

**맥유저를 위한 안드로이드 메세지 앱** — 안드로이드폰의 Google 메시지(SMS/RCS)를 Mac에서 쓰는 네이티브 macOS 앱입니다. 폰과 1회 QR 페어링하면, 폰이 주머니에 있어도(인터넷만 연결되면) Mac이 구글 서버와 직접 통신합니다. 브라우저 불필요.

> 메뉴바 미확인 알림 · 바탕화면 위젯 · 로컬 AI 답장/문장 다듬기 · 듀얼심 발신 선택 · 연락처 이름·사진 동기화 까지.

---

## ✨ 주요 기능

### 📱 메시지 (기본)
- **Google 메시지(SMS/RCS)** 송수신 — 안드로이드폰 페어링 기반
- **로컬 우선** — 모든 메시지는 Mac의 로컬 SQLite에 저장, 클라우드 없음
- 대화 목록·검색·미디어·답장·드래프트

### 🔔 메뉴바 미확인 알림
- 문자가 오면 메뉴바 아이콘이 **깜빡이고 미확인 개수**를 표시
- 드롭다운에서 최근 대화(연락처 + 미리보기) 확인, 클릭 시 앱 열기

### 🖥️ 바탕화면 위젯 (WidgetKit)
- 바탕화면에 최근 대화(연락처 + 한 줄 미리보기) + 전체 미확인 개수 표시
- 위젯 탭 → 앱 열기. (Medium / Large 크기)

### 🤖 AI 답장 추천 / 멘트 워싱 (로컬, 무료)
- 입력칸의 **추천** 버튼 → 직전 대화를 읽고 자연스러운 한국어 답장 제안
- **다듬기** 버튼 → 내가 쓴 초안을 더 자연스럽고 정중하게 교정
- **완전 로컬 처리** — API 키도, 로그인도, 클라우드 전송도 없음. 본인 Mac의 [Ollama](https://ollama.com)로만 동작 (기본 모델 `exaone3.5:7.8b`, 한국어 특화)

### 📇 연락처 프로필 동기화
- 로그인된 Google 계정(폰에 동기화된) 연락처의 **이름 + 프로필 사진**을 가져와 대화에 표시
- 번호만 뜨던 대화가 **연락처 이름 + 사진**으로 바뀜. 연결 시 자동 동기화 (읽기 전용 — 폰에 빈 방 생성 안 함)

### 📶 듀얼심 발신 SIM 선택
- 입력칸의 **SIM 버튼** → 발신 SIM 선택 → 그 대화의 **기본 SIM으로 고정**(영속)
- 설정에서 **앱 전체 기본 발신 SIM**도 지정 가능
- 우선순위: 대화별 핀 SIM → 앱 기본 SIM → 자동

### 🗑️ 방 삭제 / 계정 변경
- 대화 **우클릭 → 방 삭제** → 폰(Google 메시지)과 앱 양쪽에서 삭제
- 설정에서 **계정 로그아웃 / 변경** → 다른 Google 계정으로 재페어링

### 📨 RCS 실패 시 SMS/MMS 폴백
- 앱은 RCS를 강제하지 않아 **폰이 자동으로 SMS/MMS로 폴백**
- 추가로 앱이 전송 실패를 감지하면 **1회 자동 재전송**(기본 SIM으로) — 중복 방지 가드 포함

---

## 🧩 동작 구조

```
안드로이드폰 (Google 메시지)
        │  QR 1회 페어링 (이후 인터넷으로 직접 통신)
        ▼
libgm (Go 백엔드, 127.0.0.1:7007) — 메시지 수신·로컬 SQLite·HTTP API
        ▼
Swift 앱 (WKWebView로 로컬 웹 UI 표시)
   ├─ 메뉴바 미확인 점 (NSStatusItem)
   ├─ WidgetKit 바탕화면 위젯
   └─ 입력칸 AI / SIM / 연락처 / 삭제 등
```

---

## 📋 요구사항
- **macOS 14+** (Sequoia에서 테스트)
- **안드로이드폰** + Google 메시지 앱 (페어링용)
- 빌드 도구: **Xcode**, **Go**, **xcodegen** (`brew install xcodegen`)
- (선택) AI 기능용 **Ollama**: `brew install --cask ollama-app`

---

## 🚀 설치 & 빌드

```bash
# 1) 빌드 (Go 백엔드 + Swift 앱 + 위젯, ad-hoc 서명)
./macos/build-with-widget.sh

# 2) 설치
cp -R "macos/build/Android Message for Mac.app" /Applications/
xattr -cr "/Applications/Android Message for Mac.app"

# 3) 실행
open "/Applications/Android Message for Mac.app"
```

> 기존 `macos/build.sh`는 위젯 없이 앱만 빌드합니다. **위젯 포함은 `build-with-widget.sh`를 쓰세요.**

---

## 📖 사용법

1. **폰 페어링** — 앱 첫 실행 시 QR이 뜹니다. 안드로이드 Google 메시지 앱에서 *설정 ▸ 기기 페어링 ▸ QR 스캔*.
2. **바탕화면 위젯 추가** — 바탕화면 우클릭 ▸ 위젯 편집 ▸ "Messages" 검색 ▸ 끌어다 놓기.
3. **AI 기능 설정** (선택):
   ```bash
   brew install --cask ollama-app
   open -a Ollama
   ollama pull exaone3.5:7.8b   # 한국어 최강. 가벼운 건 qwen2.5:3b
   ```
   모델 변경: `~/Library/Application Support/GoogleRCS/ai-model.txt`에 모델명 한 줄.
4. **발신 SIM** — 입력칸 SIM 버튼(듀얼심일 때) 또는 설정의 "기본 발신 SIM".
5. **연락처/방 관리** — 대화 우클릭으로 방 삭제, 설정에서 계정 변경.

---

## 🔒 데이터 & 프라이버시
- 모든 메시지·세션은 **로컬에만** 저장: `~/Library/Application Support/GoogleRCS/`
- 외부 서버로 메시지를 보내지 않습니다. AI도 로컬(Ollama).
- 페어링 세션(`session.json`)·DB는 저장소에 포함되지 않습니다(`.gitignore`).

## ⚠️ 주의
- 이 앱은 Google 메시지 웹 프로토콜을 **리버스 엔지니어링한 라이브러리([libgm](https://github.com/mautrix/gmessages))** 기반입니다. 구글이 프로토콜을 바꾸면 동작이 깨질 수 있습니다.
- RCS는 안드로이드폰의 번호/SIM에 묶여 있어 **폰 페어링이 필수**이며 폰이 인터넷에 연결돼 있어야 합니다.

## 🙏 크레딧 & 라이선스
- 메시지 백엔드/웹 UI 기반: [MaxGhenis/openmessage](https://github.com/MaxGhenis/openmessage), [mautrix/gmessages](https://github.com/mautrix/gmessages)
- 라이선스: **Unlicense (퍼블릭 도메인)** — `LICENSE` 참고. 자유롭게 사용·수정·재배포 가능.
