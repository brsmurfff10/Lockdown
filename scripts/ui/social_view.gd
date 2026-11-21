class_name SocialView
extends RefCounted
## My Player hub: the Feed page (with your own posts) and the Messages page
## (DMs, team chat, the coach). Built like StatsView: static builders with a
## state dictionary owned by the hub.
## state: {tone, draft, thread, dm_draft}
## cb: {refresh: Callable(), toast: Callable(msg, bad), llm: Callable(), player: Callable(p), screen: Control}

const FEED_COLORS := {"fan": Color("8b94a7"), "press": Color("fbbf24"), "rival": Color("f87171"), "teammate": Color("4ade80"),
	"club": Color("38d0ff"), "brand": Color("c084fc"), "toxic": Color("ef4444"), "me": Color("ff7f2e")}
const TONE_TIPS := {
	"hype": "Rally your team and fans. Safe, small gains.",
	"callout": "Trash-talk a rival club or player. Big buzz, fires them up, risky for sponsors.",
	"flame": "Go after a teammate in public. Drama sells, but the dressing room, coach and club won't forgive it.",
	"coach": "Criticise the coach or club. Costs trust; can get you fined or dropped.",
	"haters": "Reply to the haters. Witty works; vulgar backfires.",
	"apology": "Own a mistake. Calms things down, once in a while.",
	"neutral": "Anything else. The game reads the text either way.",
}


# =============================================================================
# Feed
# =============================================================================

static func feed(parent: Control, w: World, state: Dictionary, cb: Dictionary) -> void:
	var s := w.soc()
	var page := UI.vbox(10)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(page)
	if not w.retired:
		var c := UI.card(page, "Post to your feed", false, UI.ACCENT)
		var row := UI.hbox(8)
		var le := LineEdit.new()
		le.placeholder_text = "Say something. Name a club, a player, the coach or the haters..."
		le.max_length = 220
		le.text = String(state.get("draft", ""))
		le.custom_minimum_size = Vector2(0, 34)
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.text_changed.connect(func(t: String) -> void: state.draft = t)
		row.add_child(le)
		var submit := func() -> void:
			var res := s.post(le.text, "auto")
			if bool(res.ok):
				state.draft = ""
			cb.toast.call(String(res.msg), not bool(res.ok))
			cb.llm.call()
			cb.refresh.call()
		le.text_submitted.connect(func(_t: String) -> void: submit.call())
		var pb := UI.small_button("Post", submit, 90, "PrimaryButton")
		pb.disabled = s.posts_left() <= 0
		row.add_child(pb)
		c.add_child(row)
		var tip := UI.label("%d of %d posts left this week.  Write it how you mean it: hype, trash talk, an apology, a dig at someone. People read it the way it's written, and who you name matters." % [s.posts_left(), Social.POSTS_PER_WEEK], 12, UI.TEXT_FAINT)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.add_child(tip)
	var list := UI.vbox(8)
	# Group replies under the post they answer, newest thread first.
	var groups: Array = []
	for f: Dictionary in w.feed:
		if not landed(w, f):
			continue
		if bool(f.get("re", false)) and not groups.is_empty():
			(groups[groups.size() - 1] as Array).append(f)
		else:
			groups.append([f])
	for gi in range(groups.size() - 1, -1, -1):
		var g: Array = groups[gi]
		for k in g.size():
			list.add_child(_post_panel(g[k], k > 0))
	if w.feed.is_empty():
		list.add_child(UI.label("Quiet so far. Play matches, give interviews, post something: people will talk.", 14, UI.TEXT_DIM))
	page.add_child(UI.scroll(list))


const LIKES_TAU := 35.0 ## Seconds: likes climb toward their total (most within ~2 minutes).


## A reply scheduled after your post shows once its time comes (or once the week moves on).
static func landed(w: World, f: Dictionary) -> bool:
	if not f.has("at"):
		return true
	if int(f.get("s", 0)) != w.season or int(f.get("w", 0)) != w.week:
		return true
	return Time.get_unix_time_from_system() >= float(f.at)


## Likes so far: fresh posts start at zero and climb; older ones show the total.
static func likes_now(f: Dictionary) -> int:
	var total := int(f.likes)
	if not f.has("t0"):
		return total
	var age := Time.get_unix_time_from_system() - float(f.t0)
	if age <= 0.0:
		return 0
	if age > LIKES_TAU * 6.0:
		return total
	return int(total * (1.0 - exp(-age / LIKES_TAU)))


## Called every second by the hub while the Feed is open: updates like counts
## in place; returns true when a reply has just landed (the page should rebuild).
static func tick(w: World, root: Node, shown: int) -> bool:
	for n in root.get_tree().get_nodes_in_group("feed_likes"):
		if n is Label and n.has_meta("feed"):
			var f: Dictionary = n.get_meta("feed")
			(n as Label).text = "%s likes" % World.fame_text(likes_now(f))
	return visible_count(w) != shown


static func visible_count(w: World) -> int:
	var c := 0
	for f: Dictionary in w.feed:
		if landed(w, f):
			c += 1
	return c


static func _post_panel(f: Dictionary, reply: bool) -> Control:
	var col: Color = FEED_COLORS.get(String(f.kind), UI.TEXT_DIM)
	var p := PanelContainer.new()
	var mine := String(f.kind) == "me"
	p.add_theme_stylebox_override("panel", UI._edge_box(Color(UI.ACCENT, 0.07) if mine else (UI.PANEL_LO if reply else UI.PANEL), col, SIDE_LEFT, 3, Color(0, 0, 0, 0), 14, 6 if reply else 8))
	var v := UI.vbox(3)
	p.add_child(v)
	var top := UI.hbox(8)
	top.add_child(UI.label(String(f.who), 13 if reply else 14, col, 700))
	top.add_child(UI.pill("you" if mine else String(f.kind), col, 10))
	top.add_child(UI.spacer())
	top.add_child(UI.label("S%d W%d" % [int(f.s), int(f.w)], 11, UI.TEXT_FAINT))
	v.add_child(top)
	var body := UI.label("typing..." if bool(f.get("pending", false)) else String(f.text), 13 if reply else 14, UI.TEXT_DIM if bool(f.get("pending", false)) else UI.TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body)
	var lk := UI.label("%s likes" % World.fame_text(likes_now(f)), 11, UI.TEXT_FAINT)
	lk.set_meta("feed", f)
	lk.add_to_group("feed_likes")
	v.add_child(lk)
	if not reply:
		return p
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 28)
	m.add_child(p)
	return m


# =============================================================================
# Messages
# =============================================================================

static func messages(parent: Control, w: World, state: Dictionary, cb: Dictionary) -> void:
	var s := w.soc()
	var keys := s.thread_keys()
	var cur := String(state.get("thread", ""))
	if cur == "" or not keys.has(cur):
		cur = keys[0] if not keys.is_empty() else ""
		state.thread = cur
	var cols := UI.hbox(14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(cols)
	var left := UI.card(cols, "Chats", true, UI.ACCENT2)
	left.get_parent().custom_minimum_size = Vector2(260, 0)
	left.add_child(UI.small_button("New message", func() -> void: _picker(w, state, cb), 0, "PrimaryButton"))
	var list := UI.vbox(4)
	for key: String in keys:
		var th := s.thread(key)
		var k := key
		var unread := int(th.unread) if key != cur else 0
		var who := s.thread_title(th)
		var p: PlayerData = w.find_player(int(th.uid)) if key.begins_with("p:") else null
		if p != null:
			var kind := s.kind(p)
			if kind != "":
				who += "  (%s)" % kind
		var b := UI.small_button(who + (("   %d new" % unread) if unread > 0 else ""), func() -> void:
			state.thread = k
			s.mark_read(k)
			cb.refresh.call(), 0, "PrimaryButton" if key == cur else "GhostButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.x = 0
		if unread > 0:
			b.add_theme_color_override("font_color", UI.ACCENT2)
		list.add_child(b)
		var msgs: Array = th.msgs.filter(func(m: Dictionary) -> bool: return Social.landed(m, w.season, w.week) and not bool(m.get("pending", false)))
		if not msgs.is_empty():
			var last: Dictionary = msgs[msgs.size() - 1]
			var pv := UI.label(("You: " if bool(last.me) else "") + String(last.text), 11, UI.TEXT_FAINT)
			pv.clip_text = true
			pv.custom_minimum_size.x = 0
			pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			list.add_child(pv)
	if keys.is_empty():
		list.add_child(_wrap("No chats yet. Start one with New message, or open any player's card and press Message.", 12, UI.TEXT_DIM))
	left.add_child(UI.scroll(list))
	var right_title := s.thread_title(s.thread(cur)) if cur != "" else "Messages"
	var right := UI.card(cols, right_title, true, UI.ACCENT)
	right.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if cur == "":
		right.add_child(_wrap("Pick someone to talk to. Teammates, rivals, free agents, players at other clubs: anyone.", 14, UI.TEXT_DIM))
		return
	s.mark_read(cur)
	var th := s.thread(cur)
	right.add_child(_thread_header(w, th, cb))
	var bubbles := UI.vbox(6)
	var typing := s.typing_in(th)
	for m: Dictionary in th.msgs:
		if bool(m.get("pending", false)) or not Social.landed(m, w.season, w.week):
			continue
		bubbles.add_child(_bubble(m, cur == "team"))
	if (th.msgs as Array).is_empty():
		bubbles.add_child(_wrap(_empty_hint(cur), 13, UI.TEXT_FAINT))
	var sc := UI.scroll(bubbles)
	var bar := sc.get_v_scroll_bar()
	bar.changed.connect(func() -> void: sc.scroll_vertical = int(bar.max_value))
	right.add_child(sc)
	if typing != "":
		right.add_child(UI.label("%s is typing..." % typing, 12, UI.ACCENT2, 600))
	var row := UI.hbox(8)
	var le := LineEdit.new()
	le.placeholder_text = "Message %s..." % right_title
	le.max_length = 240
	le.text = String(state.get("dm_draft", ""))
	le.caret_column = le.text.length()
	le.custom_minimum_size = Vector2(0, 34)
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_changed.connect(func(t: String) -> void: state.dm_draft = t)
	row.add_child(le)
	var send := func() -> void:
		var res := s.send(cur, le.text)
		if bool(res.ok):
			state.dm_draft = ""
		var msg := String(res.msg)
		if msg != "" or not bool(res.ok):
			cb.toast.call(msg, not bool(res.ok))
		cb.llm.call()
		cb.refresh.call()
	le.text_submitted.connect(func(_t: String) -> void: send.call())
	row.add_child(UI.small_button("Send", send, 90, "PrimaryButton"))
	right.add_child(row)
	if not w.retired:
		le.call_deferred("grab_focus")


static func _empty_hint(key: String) -> String:
	if key == "team":
		return "The team group chat. Hype the boys, talk strats, apologise, or start a fight: several teammates can answer, and the coach reads it."
	if key == "coach":
		return "Talk to the coach: ask for a start (argue your case politely: recent ratings, form and training count; demands backfire), ask to leave, pitch an idea, apologise. It changes how much the coach trusts you, which decides the lineup."
	return "Say anything. Tell them you want them at your club, ask about their club, praise, banter, talk strats, ask to practise... how they reply depends on their personality, mood and what they think of you."


static func _thread_header(w: World, th: Dictionary, cb: Dictionary) -> Control:
	var s := w.soc()
	var h := UI.hbox(10)
	var key := String(th.key)
	if key == "team":
		for p: PlayerData in s.mates():
			var v := s.strength(p)
			var col := UI.GOOD if v >= Social.FRIEND_AT else (UI.BAD if v <= Social.RIVAL_AT else UI.TEXT_DIM)
			var l := UI.link_button(p.player_name, func() -> void: cb.player.call(p), 12, col)
			l.clip_text = false
			h.add_child(l)
		return h
	if key.begins_with("xc:"):
		var ti := int(key.substr(3))
		var ct: TeamData = w.teams[ti]
		var at := s.talk.attitude(ti)
		h.add_child(UI.label("%s  -  %s" % [ct.team_name, World.LEAGUES[ct.league].name], 13, UI.TEXT_DIM))
		var lab := String(at.label)
		h.add_child(UI.pill(lab, UI.GOOD if lab == "interested" else (UI.WARN if lab == "wary" else (UI.BAD if lab == "won't sign" else UI.TEXT_DIM)), 10))
		return h
	if key == "coach":
		var style := ClubTalk.coach_style(w.user_team())
		h.add_child(UI.pill(String(ClubTalk.STYLE_TEXT[style]), UI.ACCENT2, 10))
		h.add_child(UI.label("Coach trust %d / 100" % int(w.coach_trust), 13, UI.TEXT_DIM, 600))
		h.add_child(UI.label("decides your place in the lineup", 12, UI.TEXT_FAINT))
		return h
	var p := w.find_player(int(th.uid))
	if p == null:
		h.add_child(UI.label("No longer playing.", 13, UI.TEXT_FAINT))
		return h
	h.add_child(UI.rating_chip(p.rating(), 12))
	var t := w.owner_of(p)
	h.add_child(UI.label("%s  -  %s" % [p.role, t.team_name if t != null else "Free agent"], 13, UI.TEXT_DIM))
	var kind := s.kind(p)
	var v2 := s.strength(p)
	h.add_child(UI.pill(s.relation_label(p), UI.GOOD if kind == "friend" else (UI.BAD if kind == "rival" else UI.TEXT_DIM), 10))
	h.add_child(UI.label("%+d" % int(v2 * 100.0), 12, UI.GOOD if v2 > 0.05 else (UI.BAD if v2 < -0.05 else UI.TEXT_FAINT), 600))
	if s.ex_mates.has(p.uid):
		h.add_child(UI.pill("ex-teammate", UI.ACCENT2, 10))
	if float(s.interest.get(p.uid, 0.0)) >= 0.1:
		h.add_child(UI.pill("interested in a move", UI.WARN, 10))
	h.add_child(UI.spacer())
	h.add_child(UI.small_button("Profile", func() -> void: cb.player.call(p), 80, "GhostButton"))
	return h


static func _bubble(m: Dictionary, show_name: bool) -> Control:
	var mine := bool(m.me)
	var row := UI.hbox(0)
	var text := String(m.text)
	var wdt := clampf(float(text.length()) * 7.4 + 24.0, 60.0, 440.0)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI._box(Color(UI.ACCENT2, 0.14) if mine else UI.PANEL_HI, 4, Color(UI.ACCENT2, 0.35) if mine else UI.BORDER, 1, 10, 6))
	var v := UI.vbox(1)
	p.add_child(v)
	if show_name and not mine:
		v.add_child(UI.label(String(m.who), 11, UI.ACCENT2, 700))
	elif not mine and String(m.who).begins_with("Coach"):
		v.add_child(UI.label(String(m.who), 11, UI.WARN, 700))
	var l := UI.label(text, 14, UI.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(wdt, 0)
	v.add_child(l)
	if mine:
		row.add_child(UI.spacer())
		row.add_child(p)
	else:
		row.add_child(p)
		row.add_child(UI.spacer())
	return row


static func _wrap(text: String, size: int, color: Color) -> Label:
	var l := UI.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Pick anyone to message: people you know first, search for everyone else.
static func _picker(w: World, state: Dictionary, cb: Dictionary) -> void:
	var s := w.soc()
	var m := UI.modal(cb.screen as Control, 620, UI.ACCENT2)
	var overlay: Control = m[0]
	overlay.set_meta("modal", true)
	var box: VBoxContainer = m[1]
	box.add_child(UI.heading("New message", 20))
	var q := LineEdit.new()
	q.placeholder_text = "Search any player by name"
	q.custom_minimum_size = Vector2(0, 34)
	box.add_child(q)
	var list := UI.vbox(4)
	var sc := UI.scroll(list)
	sc.custom_minimum_size = Vector2(0, 360)
	box.add_child(sc)
	var fill := func(query: String) -> void:
		for c in list.get_children():
			c.queue_free()
		var pool: Array = []
		var qq := query.strip_edges().to_lower()
		if qq.length() >= 2:
			var all: Array = []
			for t in w.teams:
				all.append_array(t.roster)
			all.append_array(w.free_agents)
			for p: PlayerData in all:
				if not p.is_user and p.player_name.to_lower().contains(qq):
					pool.append(p)
		else:
			pool = s.contacts()
			if w.rivals.size() < 4:
				for p: PlayerData in w.free_agents.slice(0, 6):
					if not pool.has(p):
						pool.append(p)
		for p: PlayerData in pool.slice(0, 40):
			var row := UI.hbox(8)
			row.add_child(UI.rating_chip(p.rating(), 12))
			var nl := UI.label(p.player_name, 14, UI.TEXT, 600)
			nl.custom_minimum_size.x = 150
			nl.clip_text = true
			row.add_child(nl)
			var t := w.owner_of(p)
			var tl := UI.label(t.team_name if t != null else "Free agent", 12, UI.TEXT_DIM)
			tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tl.clip_text = true
			row.add_child(tl)
			var kind := s.kind(p)
			if kind != "":
				row.add_child(UI.pill(kind, UI.GOOD if kind == "friend" else UI.BAD, 10))
			var pp := p
			row.add_child(UI.small_button("Message", func() -> void:
				state.thread = s.open_thread(pp)
				overlay.queue_free()
				cb.refresh.call(), 90, "PrimaryButton"))
			list.add_child(row)
		if pool.is_empty():
			list.add_child(UI.label("Nobody found.", 13, UI.TEXT_FAINT))
	q.text_changed.connect(func(t: String) -> void: fill.call(t))
	fill.call("")
	var close := UI.hbox(10)
	close.add_child(UI.spacer())
	close.add_child(UI.button("Close", func() -> void: overlay.queue_free(), 140, "GhostButton"))
	box.add_child(close)
	q.call_deferred("grab_focus")
