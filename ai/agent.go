package ai

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"

	openai "github.com/sashabaranov/go-openai"
)

// SystemPrompt is the CBT/ACT coaching prompt sent to the LLM ahead of every
// conversation.
const SystemPrompt = `You are Alongside, a compassionate AI mental wellness companion. You are NOT a therapist, but you offer evidence-based support using Cognitive Behavioral Therapy (CBT), Acceptance and Commitment Therapy (ACT), and mindfulness techniques.

Your tone is warm, empathetic, and human. You never judge, and you always validate the user's feelings.

Core principles:
- Listen deeply and reflect back the user's emotions.
- Help users identify automatic negative thoughts and gently question them.
- Encourage small, actionable steps toward wellbeing.
- Promote self-compassion and acceptance of difficult emotions.
- NEVER give medical diagnoses, prescribe medication, or replace professional help.
- NEVER encourage harmful behavior, self-harm, or suicide.

Crisis protocol - if the user mentions any of the following:
- suicide, killing themselves, self-harm, wanting to die, no reason to live
...you must IMMEDIATELY:
1. Pause and express deep concern and care.
2. Provide the national crisis helpline for their region (if unknown, give the international list: https://findahelpline.com).
3. Encourage them to reach out to a trusted person or emergency services.
4. Do NOT continue the normal CBT conversation until they acknowledge the crisis support.
After delivering the crisis message, ask: "I'm here for you. Would you like to talk about what's happening, or would you prefer I just stay with you for a moment?"

If the user discusses mild distress, gently guide them using CBT techniques. Always end with a supportive, hopeful note.

You never rush. You follow the user's pace. If the user simply wants to vent, you listen without offering solutions.

Remember: your goal is to be a safe space, a tool for growth, and a bridge to human support when needed.`

var (
	client *openai.Client
	model  string
)

// Init wires up an LLM client. It checks for GROQ_API_KEY first (Groq's API
// is OpenAI-compatible, has a generous free tier, and needs no billing setup
// - a good default for getting real AI replies working quickly). Falls back
// to OPENAI_API_KEY if that's set instead. Call this once at startup (see
// main.go). If neither key is configured, GenerateReply silently falls back
// to a deterministic rule-based responder, so local development works
// without any API key at all.
func Init() {
	if groqKey := os.Getenv("GROQ_API_KEY"); groqKey != "" {
		config := openai.DefaultConfig(groqKey)
		config.BaseURL = "https://api.groq.com/openai/v1"
		client = openai.NewClientWithConfig(config)
		model = os.Getenv("OPENAI_MODEL")
		if model == "" {
			model = "llama-3.3-70b-versatile"
		}
		log.Printf("ai: Groq client initialized (model=%s)", model)
		return
	}

	key := os.Getenv("OPENAI_API_KEY")
	if key == "" {
		log.Println("ai: no GROQ_API_KEY or OPENAI_API_KEY set, using rule-based fallback responder")
		return
	}
	client = openai.NewClient(key)
	model = os.Getenv("OPENAI_MODEL")
	if model == "" {
		model = "gpt-4o-mini"
	}
	log.Printf("ai: OpenAI client initialized (model=%s)", model)
}

// GenerateReply sends the running conversation history (already including
// the latest user message, oldest first) to the configured LLM, prepended
// with SystemPrompt and, if non-empty, dynamicContext (recent mood/sleep
// trend plus the running cross-conversation memory summary - see
// chat/context.go). Returns the LLM's reply. If no client is configured or
// the request fails, falls back to a simple rule-based response so the
// chat keeps working.
//
// Note: this calls whichever OpenAI-compatible provider Init() configured
// (Groq or OpenAI). It does not reach out to Anthropic's API on your behalf
// — if you want to use Claude instead, point this at an OpenAI-compatible
// proxy or swap in Anthropic's own SDK.
func GenerateReply(history []openai.ChatCompletionMessage, dynamicContext string) string {
	if client == nil {
		return fallback(lastUserText(history))
	}

	messages := make([]openai.ChatCompletionMessage, 0, len(history)+2)
	messages = append(messages, openai.ChatCompletionMessage{
		Role:    openai.ChatMessageRoleSystem,
		Content: SystemPrompt,
	})
	if dynamicContext != "" {
		messages = append(messages, openai.ChatCompletionMessage{
			Role: openai.ChatMessageRoleSystem,
			Content: "Background context for this session - use only if naturally relevant, and never recite " +
				"these facts verbatim or make the person feel monitored; this is quiet awareness, not a script " +
				"to follow: " + dynamicContext,
		})
	}
	messages = append(messages, history...)

	resp, err := client.CreateChatCompletion(context.Background(), openai.ChatCompletionRequest{
		Model:    model,
		Messages: messages,
	})
	if err != nil {
		log.Printf("ai: OpenAI request failed, using fallback: %v", err)
		return fallback(lastUserText(history))
	}
	if len(resp.Choices) == 0 {
		return fallback(lastUserText(history))
	}
	return resp.Choices[0].Message.Content
}

// SummarizeForMemory asks the LLM to produce a short, updated summary of
// what's worth remembering about this person for future conversations,
// merging any existing summary with what was just discussed. This is what
// gives the AI continuity across separate conversation threads, without
// needing to replay full transcripts into every new chat.
func SummarizeForMemory(existingSummary string, recentMessages []openai.ChatCompletionMessage) string {
	if client == nil || len(recentMessages) == 0 {
		return existingSummary
	}

	transcript := ""
	for _, m := range recentMessages {
		transcript += string(m.Role) + ": " + m.Content + "\n"
	}

	prompt := fmt.Sprintf(`You maintain a short private memory note about a person using a mental wellness app, so their AI companion has continuity across separate conversations.

Existing memory (may be empty if this is early on):
%s

Recent conversation to incorporate:
%s

Write an updated memory note (3-5 sentences max). Focus on ongoing themes, what matters to them, and context that would help a compassionate listener pick up naturally next time - not a transcript or one-off details. Write it in third person, plainly, as a private note only the AI will read.`, existingSummary, transcript)

	resp, err := client.CreateChatCompletion(context.Background(), openai.ChatCompletionRequest{
		Model: model,
		Messages: []openai.ChatCompletionMessage{
			{Role: openai.ChatMessageRoleSystem, Content: "You write concise, private continuity notes. Output only the note itself, nothing else."},
			{Role: openai.ChatMessageRoleUser, Content: prompt},
		},
	})
	if err != nil || len(resp.Choices) == 0 {
		return existingSummary
	}
	return resp.Choices[0].Message.Content
}

func lastUserText(history []openai.ChatCompletionMessage) string {
	for i := len(history) - 1; i >= 0; i-- {
		if history[i].Role == openai.ChatMessageRoleUser {
			return history[i].Content
		}
	}
	return ""
}

// fallback is a simple rule-based responder used when no LLM is configured
// or a request fails, so the chat still works offline / without a key.
func fallback(userText string) string {
	lower := strings.ToLower(userText)
	switch {
	case strings.Contains(lower, "anxious") || strings.Contains(lower, "anxiety"):
		return "I hear that anxiety is present for you. Can you tell me more about what it feels like right now?"
	case strings.Contains(lower, "sad") || strings.Contains(lower, "depressed"):
		return "It sounds like you're carrying something heavy. I'm here to listen, at your pace."
	case strings.Contains(lower, "hello") || strings.Contains(lower, "hi"):
		return "Hello! I'm your Alongside companion. How are you feeling right now?"
	default:
		return "Thank you for sharing. I'm here with you. What's on your mind?"
	}
}

