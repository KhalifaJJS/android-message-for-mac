package web

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/maxghenis/openmessage/internal/db"
)

// Local AI features (reply suggestion + draft polishing) powered by a local
// Ollama server — no API key, no cloud, fully private. The user runs Ollama
// (https://ollama.com) and pulls a model; nothing leaves the machine.

const (
	defaultOllamaURL = "http://127.0.0.1:11434"
	// LG's EXAONE 3.5 — Korean-specialized, clean output with no language
	// code-switching (small models like qwen2.5:3b drift into English/Japanese).
	// Override via OPENMESSAGES_OLLAMA_MODEL or <data-dir>/ai-model.txt.
	defaultOllamaModel = "exaone3.5:7.8b"
)

func ollamaURL() string {
	if v := strings.TrimSpace(os.Getenv("OPENMESSAGES_OLLAMA_URL")); v != "" {
		return strings.TrimRight(v, "/")
	}
	return defaultOllamaURL
}

func ollamaModel() string {
	if v := strings.TrimSpace(os.Getenv("OPENMESSAGES_OLLAMA_MODEL")); v != "" {
		return v
	}
	// No-rebuild override for end users: a single line in
	// <data-dir>/ai-model.txt (e.g. "qwen2.5:7b" or "exaone3.5:7.8b").
	if dir := strings.TrimSpace(os.Getenv("OPENMESSAGES_DATA_DIR")); dir != "" {
		if b, err := os.ReadFile(filepath.Join(dir, "ai-model.txt")); err == nil {
			if v := strings.TrimSpace(string(b)); v != "" {
				return v
			}
		}
	}
	return defaultOllamaModel
}

// callOllama runs a one-shot chat completion against the local Ollama server and
// returns the assistant's text. It returns a friendly, user-facing error when
// Ollama isn't reachable so the UI can tell the user to start it.
func callOllama(system, user string, temperature float64) (string, error) {
	body, _ := json.Marshal(map[string]any{
		"model": ollamaModel(),
		"messages": []map[string]string{
			{"role": "system", "content": system},
			{"role": "user", "content": user},
		},
		"stream":  false,
		"options": map[string]any{"temperature": temperature},
	})

	req, err := http.NewRequest("POST", ollamaURL()+"/api/chat", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")

	httpClient := &http.Client{Timeout: 90 * time.Second}
	resp, err := httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("Ollama에 연결할 수 없습니다 (%s). Ollama를 설치·실행하고 모델을 받아주세요: `brew install ollama` → `ollama pull %s`", ollamaURL(), ollamaModel())
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(resp.Body)
		msg := strings.TrimSpace(string(b))
		if strings.Contains(msg, "try pulling") || strings.Contains(msg, "no such model") {
			return "", fmt.Errorf("모델 '%s'을 찾을 수 없습니다. `ollama pull %s` 로 받아주세요", ollamaModel(), ollamaModel())
		}
		return "", fmt.Errorf("Ollama 오류 %d: %s", resp.StatusCode, msg)
	}

	var out struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return "", fmt.Errorf("Ollama 응답 해석 실패: %w", err)
	}
	return cleanAIText(out.Message.Content), nil
}

// cleanAIText strips wrapping quotes / surrounding whitespace some models add.
func cleanAIText(s string) string {
	s = strings.TrimSpace(s)
	s = strings.Trim(s, "“”\"'")
	return strings.TrimSpace(s)
}

// buildTranscript renders recent messages oldest→newest as "나"/"상대" lines.
func buildTranscript(msgs []*db.Message, selfName string) string {
	var b strings.Builder
	for _, m := range msgs {
		who := "상대"
		if m.IsFromMe {
			who = "나"
		} else if m.SenderName != "" {
			who = m.SenderName
		}
		body := strings.TrimSpace(m.Body)
		if body == "" {
			continue
		}
		b.WriteString(who)
		b.WriteString(": ")
		b.WriteString(body)
		b.WriteString("\n")
	}
	return b.String()
}

// suggestReplyHandler reads the recent messages of a conversation and proposes a
// single natural Korean reply to the latest incoming message.
func suggestReplyHandler(store *db.Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			httpError(w, "method not allowed", 405)
			return
		}
		var req struct {
			ConversationID string `json:"conversation_id"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			httpError(w, "invalid JSON: "+err.Error(), 400)
			return
		}
		if strings.TrimSpace(req.ConversationID) == "" {
			httpError(w, "conversation_id required", 400)
			return
		}

		msgs, err := store.GetMessagesByConversation(req.ConversationID, 15)
		if err != nil {
			httpError(w, "load messages: "+err.Error(), 500)
			return
		}
		// store returns newest-first; flip to chronological for the prompt.
		for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
			msgs[i], msgs[j] = msgs[j], msgs[i]
		}
		transcript := buildTranscript(msgs, "나")
		if strings.TrimSpace(transcript) == "" {
			httpError(w, "이 대화에 아직 메시지가 없어 답장을 추천할 수 없습니다", 400)
			return
		}

		system := "너는 문자 메시지 사용자('나') 본인이다. 아래 대화를 읽고, 가장 최근 상대 메시지에 보낼 자연스러운 답장 한 개만 작성해라. 반드시 한국어(한글)로만 쓰고 영어·일본어·중국어를 절대 섞지 마라. 설명·따옴표·머리말 없이 보낼 문장 본문만 출력해라. 너무 길지 않게, 평소 문자처럼 자연스럽게."
		suggestion, err := callOllama(system, "대화:\n"+transcript+"\n\n'나'가 보낼 답장:", 0.7)
		if err != nil {
			httpError(w, err.Error(), 503)
			return
		}
		writeJSON(w, map[string]string{"suggestion": suggestion})
	}
}

// polishHandler rewrites the user's draft to read more naturally and politely.
func polishHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			httpError(w, "method not allowed", 405)
			return
		}
		var req struct {
			Text string `json:"text"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			httpError(w, "invalid JSON: "+err.Error(), 400)
			return
		}
		draft := strings.TrimSpace(req.Text)
		if draft == "" {
			httpError(w, "다듬을 문장을 먼저 입력해주세요", 400)
			return
		}

		system := "너는 한국어 문자 메시지를 다듬는 도우미다. 사용자가 쓴 초안의 의미는 그대로 유지하되, 더 자연스럽고 정중하며 읽기 좋은 문장으로 고쳐라. 반드시 한국어(한글)로만 출력하고 영어·일본어·중국어를 절대 섞지 마라. 설명·따옴표·여러 후보 없이 다듬은 문장 본문 하나만 출력해라."
		polished, err := callOllama(system, "초안:\n"+draft+"\n\n다듬은 문장:", 0.3)
		if err != nil {
			httpError(w, err.Error(), 503)
			return
		}
		writeJSON(w, map[string]string{"polished": polished})
	}
}
