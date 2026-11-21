class_name LlmClient
extends Node
## Optional local LLM (Ollama) for My Player chat lines. The game has already
## decided what happens (effects, stance); this only rewrites the words. Any
## failure, timeout or missing Ollama gives "" and the caller keeps its
## template line, so nothing depends on it.
## Settings (Game.settings): llm_on, llm_url, llm_model.

const DEFAULT_URL := "http://127.0.0.1:11434"
const DEFAULT_MODEL := "llama3.1:8b"
const KEEP_ALIVE := "30m" ## Keep the model loaded between messages (loading it takes up to a minute).

var timeout := 6.0
var busy := 0 ## Requests in flight.


static func enabled() -> bool:
	return bool(Game.settings.get("llm_on", false))


static func url() -> String:
	var u := String(Game.settings.get("llm_url", DEFAULT_URL)).strip_edges()
	return u if u != "" else DEFAULT_URL


static func model() -> String:
	var m := String(Game.settings.get("llm_model", DEFAULT_MODEL)).strip_edges()
	return m if m != "" else DEFAULT_MODEL


## Sends one chat request; cb(text: String) gets the reply or "" on failure.
func chat(system: String, user: String, cb: Callable, max_tokens: int = 60, history: Array = []) -> void:
	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)
	busy += 1
	var body := JSON.stringify({
		"model": model(), "stream": false, "keep_alive": KEEP_ALIVE,
		"messages": [{"role": "system", "content": system}] + (history if not history.is_empty() else [{"role": "user", "content": user if user != "" else "..."}]),
		"options": {"temperature": 0.9, "num_predict": max_tokens},
	})
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, data: PackedByteArray) -> void:
		var text := ""
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
			if parsed is Dictionary:
				var msg: Variant = (parsed as Dictionary).get("message", {})
				if msg is Dictionary:
					text = clean(String((msg as Dictionary).get("content", "")))
		busy -= 1
		http.queue_free()
		cb.call(text))
	var err := http.request(url().trim_suffix("/") + "/api/chat", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body)
	if err != OK:
		busy -= 1
		http.queue_free()
		cb.call("")


## Loads the model in the background (first load can take ~1 min, far past
## the chat timeout), so the first real message gets a model reply.
static func warm(parent: Node) -> void:
	if not enabled() or parent == null:
		return
	var c := LlmClient.new()
	c.timeout = 150.0
	parent.add_child(c)
	c.chat("Reply with one word.", "hi", func(_t: String) -> void:
		if is_instance_valid(c):
			c.queue_free(), 1)


## Keeps a model reply chat-sized: one or two lines, no quotes, hashtags,
## speaker labels or stage directions.
static func clean(t: String) -> String:
	var s := t.strip_edges()
	var think := s.find("</think>")
	if think >= 0:
		s = s.substr(think + 8).strip_edges()
	var lines: Array = []
	for l in s.split("\n", false):
		var ln := l.strip_edges()
		if ln != "":
			lines.append(ln)
	if lines.is_empty():
		return ""
	s = " ".join(lines.slice(0, 2))
	var colon := s.find(":")
	if colon > 0 and colon < 20 and not s.substr(0, colon).contains(" "):
		s = s.substr(colon + 1).strip_edges() # "Name: text"
	var words: Array = []
	for wd in s.split(" ", false):
		if not wd.begins_with("#"):
			words.append(wd)
	s = " ".join(words)
	s = s.replace("\"", "").replace("*", "")
	# Stray speaker tags mid-reply ("... roonk: yeah"): drop the tag, keep the words.
	var rx := RegEx.new()
	rx.compile("(^|[.!?,]\\s+|\\s)[A-Za-z0-9_]{2,16}:\\s")
	s = rx.sub(s, "$1", true).strip_edges()
	while s.begins_with("'") and s.ends_with("'") and s.length() > 2:
		s = s.substr(1, s.length() - 2)
	if s.length() > 200:
		# Too long: end at the last full sentence that fits, else at a word.
		var cut := s.substr(0, 200)
		var end := maxi(cut.rfind(". "), maxi(cut.rfind("! "), cut.rfind("? ")))
		s = cut.substr(0, end + 1) if end > 60 else cut.substr(0, cut.rfind(" "))
	return s.strip_edges()
