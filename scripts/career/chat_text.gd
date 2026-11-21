class_name ChatText
extends RefCounted
## The words side of My Player's social life: reading what you type (intent,
## target, how harsh it is) and writing replies from slot-filled templates in
## each player's own voice. Pure text: every game effect is decided in Social.
##
## Template lines may start with voice tags in brackets, e.g. "[tc] ..." = only
## toxic (t) or chill (c) players say it. Untagged lines suit anyone.
## Voices: t toxic, c chill, i igl, p pro, s showman, y shy, m mentor.

const VOICE_LETTER := {"toxic": "t", "chill": "c", "igl": "i", "pro": "p", "showman": "s", "shy": "y", "mentor": "m"}
## How often a voice types casually (lowercase, slang, the odd typo).
const CASUAL := {"toxic": 0.6, "chill": 0.8, "shy": 0.9, "showman": 0.25, "igl": 0.15, "pro": 0.0, "mentor": 0.2}
const VOICE_TEXT := {
	"toxic": "hot-headed and mouthy, swears a lot, quick to trash talk, never backs down",
	"chill": "laid-back and friendly, jokes around, types in lowercase",
	"igl": "the in-game leader type: calm, thinks about strategy, talks about calls, setups and reviewing demos",
	"pro": "professional and measured, polite, short proper sentences, no slang",
	"showman": "loud and hype, loves the spotlight, uses caps and exclamation marks",
	"shy": "quiet and shy, very short replies, lowercase, a bit awkward",
	"mentor": "an experienced veteran who gives advice and keeps people's heads up",
}

const INSULTS := ["trash", "garbage", "dogshit", "shit", "bot", "bots", "noob", "clown", "clowns", "idiot", "useless", "washed",
	"fraud", "bum", "loser", "losers", "pathetic", "terrible", "awful", "worst", "joke", "choke", "choker", "chokers", "dumb",
	"stupid", "moron", "fuck you", "fk you", "stfu", "shut up", "overrated", "hardstuck", "boosted", "braindead", "baiter",
	"uninstall", "rat", "snake", "coward", "embarrassing", "disgrace", "liability", "dead weight", "deadweight", "throwing",
	"thrower", "griefing", "clueless", "incompetent", "deluded", "crybaby", "sellout", "hack", "dog water", "dogwater", "ass", "sucks", "suck"]
## Slurs (homophobic, racist, transphobic, ableist). Not banter: a post or
## message with one is hate speech and treated as such. Matched on the text
## with leetspeak undone (f4g, n1gg...), and on a copy with repeated letters
## squashed (faaaggot) for the stems that survive that.
const SLURS := ["fag*", "f4g*", "nigg*", "nigga*", "niggu*", "retard*", "tranny*", "trannie*", "chink*", "spic", "spics",
	"kike*", "dyke", "dykes", "wetback*", "gook*", "coon", "coons", "paki", "pakis", "beaner*", "towelhead*", "raghead*",
	"sandnigg*", "shemale*", "homo", "homos", "golliwog*", "jigaboo*", "porchmonkey*"]
const SLURS_SQUASHED := ["fag*", "fagot*", "niga", "nigas", "nigaz", "retard*", "trany*", "kike*", "beaner*"]
const PROFANITY := ["fuck*", "shit*", "bitch*", "damn", "crap", "wtf", "stfu", "bullshit", "piss*", "dick*", "prick*", "bastard*", "ass", "asshole*"]
const PRAISE := ["gg", "ggs", "well played", "wp", "nice", "great", "insane", "goat", "legend", "respect", "love", "proud", "amazing",
	"clutch", "sick", "huge", "carry", "carried us", "beast", "best", "class", "unreal", "cracked", "mvp", "thanks", "thank you", "ty",
	"awesome", "brilliant", "good game", "massive", "hero", "big game", "monster", "king", "queen", "let's go", "lets go", "lfg",
	"believe", "together", "the boys", "family", "grateful", "support", "fantastic", "solid", "goated", "elite"]
const APOLOGY := ["sorry", "apolog*", "my bad", "my fault", "i was wrong", "regret*", "shouldnt have", "didnt mean", "forgive",
	"out of line", "mb", "i messed up", "not okay", "not ok", "owe you", "take it back", "heat of the moment", "too far"]
const HATER_WORDS := ["haters", "hater", "trolls", "troll", "critics", "doubters", "doubted", "keyboard warriors", "comments",
	"comment section", "the chat", "yall", "you lot", "you guys", "randoms", "twitter", "reddit", "experts", "armchair"]
## Digs without outright insults ("the coach has no idea", "we're coming for you").
const NEGATIVE := ["bad", "wrong", "blame", "fault", "no idea", "doesnt know", "dont know what", "should be fired", "fire the",
	"sack", "dont trust", "cant trust", "lost the plot", "out of his depth", "out of their depth", "questionable", "awful calls",
	"bad calls", "makes no sense", "fed up", "sick of", "tired of", "disappointed", "not good enough", "a mess", "falling apart"]
const CHALLENGE := ["coming for", "see you", "see u", "watch out", "watch your back", "well beat", "were beating", "ez", "easy win",
	"destroy", "smoke them", "cooked", "scared", "free win", "free elo", "no chance", "sit down", "talk is cheap", "on the server",
	"we run", "bring it", "can't wait to play", "cant wait to play", "next victim"]
const COACH_WORDS := ["coach", "coaching", "staff", "management", "the org", "front office", "the club", "decisions", "tactics", "board"]
const OWN_TEAM_WORDS := ["we", "us", "our", "the boys", "my team", "lads", "squad", "fam", "team", "my guys", "brothers"]

## Keyword lists per DM intent (see dm_intent()).
const INTENT_KW := {
	"leave": ["release me", "let me go", "i want to leave", "want to leave", "i want out", "want out", "transfer me", "sell me",
		"terminate", "rip up my contract", "i quit", "trade me", "transfer list", "transfer-list", "list me", "let me leave", "cancel my contract"],
	"sign": ["join us", "join my", "come to", "sign for", "sign with", "play for us", "play with us", "want you", "need you", "transfer",
		"move to", "move here", "recruit", "pick you up", "on our team", "our roster", "would you join", "wanna join", "want to join us",
		"interested in you", "join the team", "come play", "free agent"],
	"join": ["can i join", "could i join", "let me join", "join your", "your team need", "need a player", "looking for a team",
		"looking for a club", "trial", "tryout", "put a word in", "good word", "your coach", "any spots", "a spot", "need a rifler",
		"need an awper", "need an entry", "need a support", "need a lurker", "take me", "sign me"],
	"contract": ["contract", "wage", "salary", "money", "paid", "pay", "raise", "deal", "extension", "renew", "buyout", "agent"],
	"lineup": ["start", "start me", "can i start", "let me start", "in the five", "starting five", "first team", "play next", "starting", "bench", "benched", "lineup", "play me", "playing time", "minutes", "chance", "drop me", "dropped"],
	"practice": ["practice", "practise", "scrim", "scrims", "train", "training", "aim map", "deathmatch", "dm", "duo", "grind",
		"extra session", "1v1", "aim duel", "drills", "demo review", "vod", "vods", "watch demos"],
	"strategy": ["strat", "strats", "call", "calls", "igl", "execute", "rotate", "rotation", "default", "smoke", "smokes", "eco",
		"retake", "site", "a site", "b site", "mid", "setup", "anti eco", "force buy", "force", "utility", "util", "flash", "flashes",
		"stack", "fake", "lurk", "entry", "trade", "trades", "crossfire", "timing", "rush", "save", "economy", "plan", "tactic"],
	"form": ["how are you", "how r u", "hows it going", "how is it going", "you good", "u good", "you ok", "u ok", "feeling",
		"form", "confidence", "how you doing", "hows life", "whats up", "wassup", "sup", "holding up", "doing okay", "how are things"],
	"banter": ["lol", "lmao", "haha", "hahaha", "xd", "joke", "meme", "banter", "kidding", "jk", "funny", "rofl", "bruh", "kek"],
	"greeting": ["hi", "hey", "hello", "yo", "hiya", "morning", "evening", "heya", "oi"],
}
const INTENT_ORDER := ["apology", "flame", "leave", "sign", "join", "contract", "lineup", "practice", "strategy", "praise", "form", "banter", "greeting"]

# =============================================================================
# Direct messages: DM[intent][stance] -> lines
# =============================================================================

const DM := {
	"greeting": {
		"warm": ["hey {me}! what's good", "{me}! was just thinking about that {opp} game", "yo yo, what's up man", "[c] heyy {me} whats good",
			"[s] {me}!! my favourite person on this server", "[p] Hey {me}, good to hear from you.", "[i] hey. good timing, I was going to message you about mid rounds",
			"[m] hey kid, how you holding up?", "[y] oh hey", "[t] yo {me}, what you want lol"],
		"neutral": ["hey", "yo", "what's up?", "hey {me}, what's up", "[p] Hello. What can I do for you?", "[y] hi", "[c] sup",
			"[t] yeah?", "[i] hey, what's on your mind"],
		"cold": ["what do you want", "oh. it's you", "hm. hi", "[p] Hi. Make it quick, I'm in practice.", "[y] ...hi", "[t] lol what",
			"[c] uh hey i guess"],
		"hostile": ["don't message me", "nah, not talking to you", "you've got some nerve messaging me", "[t] fuck off {me}",
			"[t] blocked in 3, 2...", "[p] I'd rather we kept this on the server.", "[s] lmao the audacity"],
	},
	"praise": {
		"warm": ["appreciate that {me}, means a lot", "thanks man! you were cracked too", "haha cheers, felt good tbh", "[s] I KNOW RIGHT. thanks {me}!!",
			"[c] aw thx man, ur too kind", "[p] Thank you, {me}. Team effort.", "[i] thanks. the setups made it easy, credit to everyone",
			"[m] cheers. keep that attitude, it'll take you far", "[y] thanks :)", "[t] finally someone with taste lol, thanks",
			"means a lot coming from you", "you're not so bad yourself, {me}"],
		"humble": ["thanks, still loads to fix though", "cheers. could've been better on {map}", "[p] Thanks. Plenty to improve.",
			"[y] thx, not my best tbh", "[c] ty but i whiffed so much lol", "[i] thanks, but our mid-round calls were messy"],
		"hostile": ["don't need your compliments", "save it", "lol ok", "[t] cool story, still gonna dumpster you",
			"[p] Thanks, I suppose.", "[s] i know i'm good, don't need you to tell me", "nice try, still not friends"],
	},
	"apology": {
		"accept": ["all good man, heat of the moment", "we're fine {me}, forget it", "appreciate you saying that. clean slate",
			"[c] its chill bro, all love", "[p] Apology accepted. Let's move on.", "[i] fine by me. let's focus on {opp} instead",
			"[m] takes a big person to say that. we're good", "[y] ok. thanks for saying it", "[t] yeah whatever, we're good. don't do it again",
			"[s] water under the bridge! we go again"],
		"wary": ["ok. we'll see", "words are easy {me}", "fine, but that stung", "[p] Noted. Actions matter more.", "[c] ok... i guess",
			"[t] yeah sure, until next time you open your mouth", "[i] alright. show it on the server"],
		"reject": ["nah, too late for that", "you meant every word. don't bother", "[t] shove your apology", "[p] I don't accept that.",
			"[s] lmao the PR team wrote that one", "[y] i don't want to talk about it"],
	},
	"flame": {
		"hurt": ["wow. didn't expect that from you", "that's out of order man", "seriously? after everything?", "[c] damn bro thats harsh",
			"[y] ok... that hurt", "[p] That's unnecessary. Let's keep it professional.", "[i] we're supposed to be a team, {me}",
			"[m] I've been where you are. this isn't the way"],
		"angry": ["say that to my face", "look at your own stats before you talk", "you're one to talk with that {rating} rating",
			"[t] fuck off {me}, you're hardstuck and you know it", "[t] keep talking, see what happens", "[s] lmao imagine flaming ME",
			"[c] bro chill, who hurt u", "[p] Check your own K/D first.", "[i] fix your own positioning, then we'll talk"],
		"laugh": ["lmao ok", "haha you're tilted", "someone's had a bad day", "[c] lol ok buddy", "[s] i'm framing this message",
			"[t] cry more", "[y] lol", "[p] I'll take that as a compliment."],
		"hostile": ["see you on the server", "we'll settle this in the game", "you just made this personal", "[t] you're done, {me}. watch",
			"[t] I'm going to hunt you every round", "[s] screenshot taken. see you at the match", "[p] Noted. See you at the match.",
			"[i] fine. we'll stack your side every round", "[c] ok now i actually want to beat u"],
	},
	"banter": {
		"laugh": ["LMAO", "hahaha stop", "ok that's actually funny", "[c] lmaooo", "[s] HAHAHA i'm stealing that", "[t] lmao you're an idiot",
			"[p] Ha, fair.", "[i] lol. now say that in the team meeting", "[m] haha, kids these days", "[y] lol",
			"crying lmao", "you're not right in the head {me}"],
		"meh": ["lol", "ok", "sure", "[c] haha", "[y] heh", "[p] Right.", "[t] mid joke"],
		"annoyed": ["not the time man", "we just lost to {opp}, read the room", "[t] shut up lol", "[p] Maybe after we win a game.",
			"[i] focus up, jokes later", "[c] cant laugh rn tbh"],
	},
	"strategy": {
		"agree": ["yeah good shout, let's try it", "makes sense, especially on {map}", "agreed, we've been too slow on {site}",
			"[i] good read. let's run that early and keep the {nade} for the retake", "[c] ye im down", "[p] Agreed. Let's bring it to practice.",
			"[s] YES. let's cook them", "[t] finally someone with a brain", "[m] good thinking. that's how you grow", "[y] ok sounds good"],
		"suggest": ["could work, but I'd hold a {nade} for mid", "maybe, but they stack {site} a lot. fake it first",
			"[i] I like it, but let's default first and hit {site} late", "[i] we tried that vs {opp}. better: split {site} with two from mid",
			"[c] hmm idk, what if we just default and see", "[p] Possible. I'd want to see their tendencies first.",
			"[t] nah that's how we lost to {opp}", "[m] not bad. think about the trade though"],
		"dismiss": ["leave the calls to {igl}", "let's not overthink it", "[t] just hit your shots", "[c] eh we'll see on the day",
			"[p] We'll go through it in the meeting.", "[y] maybe", "[i] I've got the calls covered, trust me"],
		"spy": ["lol nice try, not telling you our strats", "you're not on our team, {me}", "[t] lmao get your own strats",
			"[p] I don't discuss our tactics outside the team.", "[c] haha i see what ur doing", "[s] you wish"],
	},
	"form": {
		"good": ["feeling great tbh, shots are landing", "honestly never felt better", "[s] i'm HIM right now, can't miss",
			"[c] pretty good ngl, aim feels nice", "[p] Good. Practice is going well.", "[i] good. the team's clicking",
			"[m] solid. the young ones are pushing me", "[y] good i think", "[t] cracked as always lol"],
		"bad": ["not great. can't hit anything lately", "rough week honestly", "been better. head's not in it",
			"[c] kinda bad ngl, whiffing everything", "[p] Struggling a bit, working on it.", "[i] honestly frustrated, our calls aren't landing",
			"[y] not good", "[t] shit. everything's shit", "[m] up and down. part of the job"],
		"meh": ["alright, could be better", "same old. grinding", "[c] eh decent", "[p] Fine, thanks.", "[y] ok", "[t] whatever, fine",
			"[i] steady. need a big win though", "[s] building up to something big, watch"],
	},
	"practice": {
		"yes": ["yeah let's grind tonight", "down. aim map then some retakes?", "sure, 9pm?", "[c] ye lets go", "[s] LET'S GET IT",
			"[p] Sure. I'll be on at 8.", "[i] yes, and bring notes on {site} retakes", "[m] always. I'll show you a few spots",
			"[y] ok", "[t] fine, but don't cry when I dome you"],
		"later": ["can't tonight, next week?", "busy rn, maybe another day", "[c] not today man, rain check", "[p] Not this week, sorry.",
			"[y] maybe later", "[t] nah, got stuff on"],
		"no": ["nah I'm good", "not with you", "[t] lol no", "[p] I'll pass.", "[y] no thanks"],
	},
	"sign": {
		"interested": ["honestly? I'd listen", "tell me more. what's the project at {myteam}?", "not gonna lie, I'm interested",
			"[s] {myteam}? I could see it!", "[c] oh fr? id be down tbh", "[p] I'm open to it. My agent can talk to your club.",
			"[i] depends on the role. if I get to call, I'm in", "[m] I like what you're building. let's talk",
			"[y] maybe yeah", "[t] if the money's right, sure"],
		"maybe": ["maybe. depends on a lot", "I'm happy here for now, but never say never", "[p] I'll keep it in mind.",
			"[c] hmm idk, maybe", "[i] ask me again after the season", "[t] convince me", "[y] not sure"],
		"no": ["nah, happy where I am", "not a chance, sorry", "[t] lol {myteam}? no", "[p] Thanks, but no.", "[s] i'm too big for {myteam}, sorry",
			"[c] nah im good here", "[y] no sorry"],
		"already": ["we're literally teammates lol", "uh, I already play with you", "[c] bro we're on the same team", "[p] We're already teammates, {me}."],
		"noclub": ["you don't even have a club right now lol", "get yourself a team first", "[c] u dont have a team rn tho", "[p] Sort your own club out first."],
	},
	"join": {
		"positive": ["I'll put a word in with our coach", "we could use someone like you tbh", "let me ask around at {team}",
			"[s] YES. I'll tell the boss right now", "[c] id love that ngl, ill mention it", "[p] I'll mention it to management.",
			"[i] we need a {myrole}. I'll bring it up", "[m] I'll vouch for you. don't make me look bad"],
		"neutral": ["not my call, but I'll mention it", "maybe? coach decides", "[p] That's up to our staff.", "[c] idk man, not up to me",
			"[y] i can ask i guess", "[t] depends if you stop whiffing"],
		"no": ["nah, we're full", "not happening", "[t] after what you said? no chance", "[p] I don't think that would work.",
			"[s] you couldn't handle {team}", "[c] nah sorry bro"],
		"fa": ["I don't have a team either lol", "I'm a free agent too man", "[c] bro im teamless too", "[p] I'm without a club myself."],
		"already": ["you're already on {team}, {me}", "we're teammates lol"],
	},
	"contract": {
		"deflect": ["not talking money over DMs", "ask my agent lol", "[t] mind your business", "[p] I don't discuss contracts, sorry.",
			"[c] haha cant talk about that", "[i] let's keep the focus on the game", "[y] idk, agent stuff"],
	},
	"lineup": {
		"askcoach": ["that's the coach's call, not mine", "talk to the coach about that", "[c] ask coach man", "[p] That's for the staff to decide.",
			"[i] earn it in scrims, the coach notices", "[m] keep working. your chance will come", "[t] lol not my problem"],
	},
	"smalltalk": {
		"warm": ["haha true", "honestly same", "you're a good one {me}", "[c] fr fr", "[s] that's why you're my guy",
			"[p] Agreed.", "[i] fair point", "[m] good to hear", "[y] yeah", "[t] lol ok you're alright"],
		"neutral": ["ok", "fair", "right", "[c] ye", "[p] Understood.", "[y] ok", "[t] cool", "[i] noted"],
		"cold": ["ok?", "and?", "cool", "[t] who asked", "[p] Is there something you need?", "[y] ok"],
		"hostile": ["stop messaging me", "nobody asked, {me}", "[t] go away", "[p] Please stop.", "[s] lol desperate"],
	},
	"spam": {
		"annoyed": ["bro chill with the messages", "I'm going to mute you", "can you not spam me", "[t] stop blowing up my phone",
			"[p] Please give me some space.", "[c] dude relax lol", "[y] too many messages..."],
	},
}

## Bots writing to you first.
const OPEN := {
	"after_win": ["gg {me}! that {score} vs {opp} was huge", "what a game man. we're flying", "[s] WE'RE SO BACK", "[c] ggs today, u were nuts",
		"[p] Good win today. Well played.", "[i] good win. mid rounds were much cleaner", "[t] we fucking smashed them lol",
		"[m] proud of you today. that's how it's done", "[y] gg"],
	"after_loss": ["tough one vs {opp}. we go again", "head up, we'll bounce back", "[c] that one hurt ngl", "[p] Unlucky today. Review tomorrow.",
		"[i] we lost the mid rounds. let's review the demo", "[t] that was shit. we need to wake up", "[m] losses teach more than wins. rest up",
		"[y] unlucky"],
	"big_game": ["{rating} rating?? who are you", "you were unreal today {me}", "[s] HIGHLIGHT REEL {me}!!", "[c] bro u were cracked",
		"[p] Outstanding game today.", "[i] you won us that game. keep that energy", "[t] ok you're actually good lol", "[m] that was special, kid"],
	"bad_game": ["rough one, happens to everyone", "don't let one game get in your head", "[c] u good? tough day", "[p] Bad day. Reset and go again.",
		"[i] we'll fix your spots on {map}, don't stress", "[m] I've had a hundred of those. shake it off", "[t] lol you were awful today. still love you tho"],
	"benched": ["sorry about the bench man. you'll be back", "the bench is bullshit tbh", "[c] cant believe they benched u", "[p] Keep working. You'll get your spot back.",
		"[i] we need you back. grind scrims and make it impossible to drop you", "[m] use this. come back hungrier", "[y] sorry about the bench"],
	"released": ["heard you got cut. that's rough man", "they let you go?? clowns", "[c] wtf they released u?", "[p] Sorry to hear about your release. Stay sharp.",
		"[m] happened to me too. keep playing pugs, people notice", "[t] their loss. they're shit anyway", "[s] you'll be back bigger, trust"],
	"rival_taunt": ["see you next time {me}", "{score}. remember that", "[t] get fucking destroyed lmao", "[s] another W against {me} lol",
		"[p] Good game. Better luck next time.", "[c] gg ez jk jk... unless?", "[i] we had your setups figured out from round one", "[y] gg"],
	"rival_respect": ["respect {me}, you were too good today", "ok you got me this time", "[t] lucky. next time you're dead", "[p] Well played today. Deserved.",
		"[s] fine. you win this one", "[c] gg u were cracked today", "[i] good game. you read us well"],
	"ex_hello": ["miss playing with you at {oldteam} ngl", "how's life after {oldteam}?", "[c] yo stranger, hows the new place", "[p] Hope the new club is treating you well.",
		"[m] proud of how you're doing since you left", "[t] {oldteam} is worse without you lol"],
	"courted": ["any news from your club? still keen", "so... did you talk to your coach?", "[c] any updates on the move thing?", "[p] Any update from your side?",
		"[s] still waiting for my {myteam} shirt!"],
	"joined": ["told you I'd come! let's win stuff", "your messages worked lol. see you in practice", "[s] I'M HERE!!", "[p] Looking forward to playing together.",
		"[c] yo teammate!!"],
	"ex_beef": ["heard you're struggling lol", "karma {me}", "[t] how's that free agency treating you lmao", "[p] I hope you've learned something."],
}

## The coach (lineup trust lives here).
const COACH := {
	"lineup": {
		"promise": ["Alright. Show me in scrims this week and you start the next two.", "You've earned a shot. Next two matches are yours, don't waste them.",
			"Fine. Two starts. Make me look smart."],
		"earn": ["Earn it. Your form is {myform} right now.", "The lineup is on merit. Beat the guy in front of you in practice.",
			"Keep your head down and work. I notice who puts the hours in.", "Not this week. Your numbers have to come up first."],
		"no": ["Not happening right now, and you know why.", "After your recent behaviour? No.", "The answer is no. Fix your attitude first."],
		"pushy": ["You asked me already. Asking again doesn't help your case.", "Enough. The more you push, the less I want to listen."],
	},
	"apology": {
		"accept": ["Appreciated. Let's draw a line under it.", "Good. That's what I wanted to hear. Now prove it.", "Thank you. Back to work."],
		"nothing": ["Nothing to apologise for. Just keep working.", "We're fine. Focus on {opp}."],
	},
	"flame": {
		"furious": ["Watch your tone. That'll cost you.", "Say that again and you're done here.", "Noted. And you've just made my lineup decision very easy.",
			"I've had players with more talent than you talk like that. They're not here any more."],
	},
	"praise": {
		"thanks": ["Thanks. Keep that energy for the server.", "Appreciated. Now go win me some rounds.", "Good. The whole team's buying in."],
	},
	"strategy": {
		"likes": ["Good idea. I'll put it in the playbook for {map}.", "I like that. Let's try it in scrims.", "Sharp thinking. More of that."],
		"igl": ["Leave the calls to {igl}, focus on your own job.", "Interesting, but the system works. Trust it."],
	},
	"contract": {
		"later": ["We'll talk contracts when the time comes. Week 12.", "Contract talk can wait. Perform first."],
		"longterm": ["We see you as part of the long-term plan here.", "Keep playing like this and the contract will take care of itself."],
		"focus": ["Focus on your game. The money follows the results.", "Talk to management about money. I care about rounds."],
	},
	"form": {
		"good": ["You're in good shape. Keep the routine.", "Best I've seen you. Don't change a thing."],
		"bad": ["Your form's poor. Extra deathmatch, less streaming.", "You're off the pace. Rest, reset, go again."],
	},
	"practice": {
		"yes": ["Good attitude. Extra session is on.", "Love that. I'll stay late with you."],
	},
	"smalltalk": {
		"neutral": ["Noted.", "Okay.", "Right. Anything else?", "Let's keep the focus on {opp}."],
	},
	"join": {
		"under": ["You're under contract here. Don't make me regret trusting you.", "Thinking about other clubs already? Interesting."],
	},
	"sign": {
		"noted": ["I'll have a look at them.", "Interesting name. I'll ask the scouts.", "Recruitment isn't your job, but I'll take a look."],
	},
}

## Group chat: teammates reacting to each other.
const CROSS := {
	"agree": ["what {other} said", "{other} is right tbh", "+1 to {other}", "[p] Agreed with {other}.", "[c] ye {other} gets it"],
	"tease": ["lol {other} relax", "{other} typing an essay again", "[t] {other} shut up you missed every shot today", "[c] lmao {other}", "[s] {other} with the hot take"],
	"calm": ["guys chill", "let's keep it calm", "[i] enough, we sort this in the meeting", "[p] Let's keep this professional.", "[m] breathe, everyone"],
	"defend": ["leave {target} alone", "not cool, {target} carried us last week", "[t] say that again about {target}", "[p] That's out of line about {target}.", "[c] bro {target} is fine"],
	"pile": ["{me} has a point though", "honestly, yeah", "[t] {target} was shit today, facts", "[c] ngl kinda true"],
}

# =============================================================================
# Feed replies: FEED[situation] -> lines
# =============================================================================

const FEED := {
	"hype_fan": ["LET'S GOOO {team}", "{me} gets it. Believe!", "this is the energy we need", "{team} till I die", "love this from {me}",
		"{me} talking like a captain", "the boys are cooking", "Big things coming. {team} on top", "{me} the heart of {team}",
		"after that {opp} game I believe anything", "hype levels: maximum", "screenshotting this for when we win it all"],
	"hype_cynic": ["hype after {streak}? sure buddy", "less posting, more winning", "talk is cheap, {me}", "we've heard this before",
		"post this after a win lol", "{team} fans getting baited again"],
	"hype_mate": ["let's gooo", "together. always", "we ride", "{team} on top", "that's my guy", "nothing but love for this squad"],
	"callout_fan": ["{me} really said that about {target}?? popcorn", "{target} is getting cooked lmao", "{me} has no fear and I love it",
		"oh this is going to be a GAME", "{target} fans in shambles", "the beef we needed", "{me} chose violence today", "{target} hasn't won anything to reply to this"],
	"callout_toxic": ["big words from a nobody", "{me} talks more than they frag", "{target} is going to end your career lol",
		"imagine calling out {target} with your stats", "{me} getting humbled next match, screenshot this"],
	"callout_target": ["see you on the server, {me}", "keep my name out your mouth", "lol ok", "{me} who?",
		"we'll talk after the match", "noted. see you soon", "this is going on the wall in our bootcamp", "cute"],
	"callout_club": ["We'll let our play do the talking. See you soon, {me}.", "Interesting. See you on the server.", "Saved for later.",
		"Our players have seen this.", "Noted for match day."],
	"flame_target": ["wow. ok {me}", "say it to my face in practice", "did not expect this from my own teammate", "this is why we lose",
		"deleted? no? brave", "classy, {me}. real classy", "we'll talk about this in the team room"],
	"flame_fan": ["{me} WHAT ARE YOU DOING", "airing dirty laundry online? yikes", "{team} dressing room is a disaster", "this is so unprofessional",
		"delete this {me}", "honestly {target} has been bad, but not like this", "{me} just ended a friendship live", "the vibes at {team} are not it"],
	"flame_toxic": ["{me} blaming teammates as usual, look in the mirror", "lmao {me} is the problem and everyone knows it", "imagine flaming {target} with that K/D"],
	"flame_club": ["We are aware of a post by {me}. This will be dealt with internally.", "{team} does not support public criticism of teammates. We'll be speaking to {me}.",
		"Statement: we expect every player to represent {team} with respect."],
	"flame_press": ["DRAMA: {me} goes after teammate {target} in public", "{team} in turmoil after {me}'s post", "Cracks at {team}? {me} calls out {target}"],
	"coach_fan": ["{me} isn't wrong though", "fire the coach honestly", "{me} saying what we're all thinking", "this is a bad look {me}",
		"you don't bite the hand that picks the lineup lol", "coach out?"],
	"coach_club": ["We're aware of the comments. Any issues will be discussed privately.", "{team} has full confidence in its coaching staff.",
		"Disappointed by the comments made in public today."],
	"coach_press": ["{me} slams the {team} coaching staff", "Rift at {team}: {me} questions the coach", "{me} vs the coach: what next?"],
	"haters_fan": ["tell em {me}", "{me} doesn't owe anyone anything", "the haters are crying", "good. block them all",
		"love the confidence", "{me} cooking the comment section"],
	"haters_toxic": ["we hit a nerve lmao", "cope {me}", "imagine replying to haters, so pressed", "{me} reading every comment lol",
		"still trash, {me}"],
	"haters_witty": ["ok that reply was actually funny", "{me} 1, haters 0", "the ratio is incoming", "most composed person on this app"],
	"apology_fan": ["respect for owning it {me}", "takes guts. good on you", "everyone makes mistakes", "this is the {me} we love",
		"apology accepted. now win", "mature from {me}"],
	"apology_cynic": ["PR team wrote this", "sorry you got caught", "means nothing until you change", "the notes app apology lol"],
	"apology_target": ["appreciate it {me}. we're good", "thanks for saying it. let's move on", "ok. clean slate"],
	"apology_none": ["apologising for what lol", "who hurt you {me}", "?? what did I miss", "this is confusing"],
	"neutral_fan": ["fair", "real", "{me} posting again", "facts", "true", "agreed {me}", "lol", "the man the myth", "W post"],
	"neutral_praise": ["{target} deserves it", "love this, {me} and {target} are the duo", "wholesome", "this is nice to see"],
	"released_fan": ["{oldteam} will regret this", "{me} deserves better", "someone sign {me} please", "clown decision by {oldteam}"],
	"released_toxic": ["deserved lol", "about time someone cut {me}", "{me} to the low leagues where they belong"],
}

# =============================================================================
# Reading what you typed
# =============================================================================

## Lowercase words separated by single spaces, padded: " like this ".
static func norm(text: String) -> String:
	var t := text.to_lower()
	var out := ""
	for i in t.length():
		var u := t.unicode_at(i)
		if (u >= 97 and u <= 122) or (u >= 48 and u <= 57) or u > 127:
			out += t[i]
		elif u == 39 or u == 8217: # Apostrophes vanish ("don't" -> "dont").
			continue
		else:
			out += " "
	var parts := out.split(" ", false)
	return " " + " ".join(parts) + " "


## kw "word" matches whole words/phrases; "stem*" matches words starting with stem.
static func has_kw(n: String, kw: String) -> bool:
	if kw.ends_with("*"):
		return n.contains(" " + norm(kw.trim_suffix("*")).strip_edges())
	return n.contains(norm(kw))


static func count_kw(n: String, list: Array) -> int:
	var c := 0
	for kw: String in list:
		if has_kw(n, kw):
			c += 1
	return c


## Undo common leetspeak / symbol swaps before looking for slurs.
static func unleet(text: String) -> String:
	var t := text.to_lower()
	for pair in [["4", "a"], ["@", "a"], ["3", "e"], ["1", "i"], ["!", "i"], ["|", "i"], ["0", "o"], ["$", "s"], ["5", "s"], ["7", "t"], ["9", "g"], ["6", "g"]]:
		t = t.replace(pair[0], pair[1])
	return t


## Runs of the same letter squashed to one ("faaaggot" -> "fagot").
static func squash(text: String) -> String:
	var out := ""
	for i in text.length():
		if i == 0 or text[i] != text[i - 1]:
			out += text[i]
	return out


static func slur_count(text: String) -> int:
	var u := unleet(text)
	var n := count_kw(norm(u), SLURS)
	if n == 0:
		n = count_kw(norm(squash(u)), SLURS_SQUASHED)
	return n


## The text with any slur starred out (first letter kept), for the feed and chats.
static func censor(text: String) -> String:
	var out: Array = []
	for word in text.split(" ", false):
		if slur_count(word) > 0:
			var letters := word.length()
			out.append(word.left(1) + "*".repeat(maxi(2, letters - 1)))
		else:
			out.append(word)
	return " ".join(out)


## Tone markers: insults, swearing, praise, apology, shouting. harsh: 0..1.
static func analyze(text: String) -> Dictionary:
	var n := norm(text)
	var letters := 0
	var caps := 0
	for i in text.length():
		var u := text.unicode_at(i)
		if u >= 65 and u <= 90:
			caps += 1
			letters += 1
		elif u >= 97 and u <= 122:
			letters += 1
	var caps_ratio := float(caps) / float(letters) if letters >= 8 else 0.0
	var insult := count_kw(n, INSULTS)
	var prof := count_kw(n, PROFANITY)
	var praise := count_kw(n, PRAISE)
	var apology := count_kw(n, APOLOGY)
	var slur := slur_count(text)
	var harsh := insult * 0.2 + prof * 0.12 + maxf(0.0, caps_ratio - 0.4) * 0.5 + (0.06 if text.contains("!!") else 0.0)
	if insult == 0 and prof == 0:
		harsh *= 0.4
	if slur > 0:
		harsh = 1.0
		insult += slur
	return {"n": n, "insult": insult, "profanity": prof, "praise": praise, "apology": apology, "caps": caps_ratio, "slur": slur,
		"negative": count_kw(n, NEGATIVE), "challenge": count_kw(n, CHALLENGE),
		"harsh": clampf(harsh, 0.0, 1.0), "haters": count_kw(n, HATER_WORDS), "coach": count_kw(n, COACH_WORDS),
		"own": count_kw(n, OWN_TEAM_WORDS), "length": text.length()}


## What a DM is about (see INTENT_KW). Apology and insults win over keywords.
static func dm_intent(a: Dictionary) -> String:
	var n: String = a.n
	if int(a.get("slur", 0)) > 0:
		return "hate"
	if int(a.apology) > 0 and int(a.insult) == 0:
		return "apology"
	if int(a.insult) > 0 and int(a.praise) <= int(a.insult):
		return "flame"
	var best := "smalltalk"
	var best_score := 0
	for intent: String in INTENT_ORDER:
		var score := 0
		if intent == "praise":
			score = int(a.praise)
		elif INTENT_KW.has(intent):
			score = count_kw(n, INTENT_KW[intent])
		if intent == "greeting" and score > 0 and int(a.length) > 25:
			score = 0 # "hey, can I join your team?" is a join request, not a hello.
		if score > best_score:
			best = intent
			best_score = score
	return best


## Players (and teams) named in the text. candidates: Array[PlayerData].
static func find_players(text: String, candidates: Array) -> Array:
	var n := norm(text)
	var out: Array = []
	for p: PlayerData in candidates:
		if p == null or p.is_user:
			continue
		var pn := norm(p.player_name)
		if pn.strip_edges().length() < 3 or INSULTS.has(pn.strip_edges()) or OWN_TEAM_WORDS.has(pn.strip_edges()):
			continue
		if n.contains(pn) and not out.has(p):
			out.append(p)
	return out


static func find_teams(text: String, teams: Array) -> Array:
	var n := norm(text)
	var full: Array = []
	var partial: Array = []
	var last_words := {}
	var tags := {}
	for t: TeamData in teams:
		var parts := norm(t.team_name).strip_edges().split(" ")
		var lw: String = parts[parts.size() - 1] if parts.size() > 1 else ""
		last_words[lw] = int(last_words.get(lw, 0)) + 1
		var tg := norm(t.short_name).strip_edges()
		tags[tg] = int(tags.get(tg, 0)) + 1
	for t: TeamData in teams:
		var tn := norm(t.team_name)
		if n.contains(tn):
			full.append(t)
			continue
		var tag := norm(t.short_name).strip_edges()
		var parts := tn.strip_edges().split(" ")
		var lw: String = parts[parts.size() - 1] if parts.size() > 1 else ""
		var hit := tag.length() >= 3 and int(tags.get(tag, 0)) == 1 and n.contains(" " + tag + " ") and not OWN_TEAM_WORDS.has(tag)
		if not hit and lw.length() >= 4 and int(last_words.get(lw, 0)) == 1 and not OWN_TEAM_WORDS.has(lw):
			hit = n.contains(" " + lw + " ")
		if hit:
			partial.append(t)
	return full + partial


# =============================================================================
# Writing replies
# =============================================================================

## A player's chat voice: their persona if they have one, else role + a hash.
static func voice(p: PlayerData) -> String:
	if p == null:
		return "pro"
	match PlayerData.persona_of(p):
		"Troublemaker": return "toxic"
		"Leader": return "igl"
		"Mentor": return "mentor"
		"Professional": return "pro"
		"Showman": return "showman"
	var h := absi(hash("%d/%s/voice" % [p.uid, p.player_name])) % 100
	match p.role:
		"Entry": return "toxic" if h < 30 else ("showman" if h < 55 else "chill")
		"AWPer": return "chill" if h < 45 else ("shy" if h < 75 else "pro")
		"Support": return "igl" if h < 45 else ("chill" if h < 75 else "mentor")
		"Lurker": return "shy" if h < 45 else ("chill" if h < 75 else "toxic")
	return "chill" if h < 40 else ("pro" if h < 60 else ("toxic" if h < 78 else "showman"))


static func _tagged(line: String) -> Array:
	if line.begins_with("["):
		var close := line.find("]")
		if close > 0:
			return [line.substr(1, close - 1), line.substr(close + 1).strip_edges()]
	return ["", line]


## A line for this voice, avoiding `avoid` (recently used templates).
static func pick(lines: Array, v: String, rng: RandomNumberGenerator, avoid: Array = []) -> String:
	var letter: String = VOICE_LETTER.get(v, "")
	var fit: Array = []
	var any: Array = []
	for l: String in lines:
		var tg: Array = _tagged(l)
		var tags: String = tg[0]
		any.append(tg[1])
		if tags == "" or (letter != "" and tags.contains(letter)):
			fit.append(tg[1])
	if fit.is_empty():
		fit = any
	if fit.is_empty():
		return ""
	var start := rng.randi() % fit.size()
	for k in fit.size():
		var cand: String = fit[(start + k) % fit.size()]
		if not avoid.has(cand):
			return cand
	# All used recently: take the one used longest ago (never the last line).
	var oldest: String = fit[start]
	var oldest_at := avoid.size()
	for cand: String in fit:
		var at := avoid.rfind(cand)
		if at < oldest_at:
			oldest_at = at
			oldest = cand
	return oldest


static func fill(line: String, slots: Dictionary) -> String:
	var t := line
	for k: String in slots:
		t = t.replace("{%s}" % k, String(slots[k]))
	return t


## Casual typing for casual voices: lowercase, slang, the odd typo; swearing
## for toxic players and caps for showmen.
static func style(text: String, v: String, rng: RandomNumberGenerator) -> String:
	var t := text
	if v == "toxic" and rng.randf() < 0.3:
		t += [" ffs", " lmao", " fr", " ngl", " fucking hell"][rng.randi() % 5]
	elif v == "showman" and rng.randf() < 0.3:
		t = t.to_upper() if t.length() < 40 else t + "!!"
	elif v == "chill" and rng.randf() < 0.2:
		t += [" haha", " lol", " ngl", " fr"][rng.randi() % 4]
	if rng.randf() < float(CASUAL.get(v, 0.3)):
		t = t.to_lower()
		if t.ends_with(".") and not t.ends_with(".."):
			t = t.trim_suffix(".")
		var padded := " " + t + " "
		if rng.randf() < 0.4:
			padded = padded.replace(" you ", " u ").replace(" your ", " ur ").replace(" you're ", " ur ")
		padded = padded.replace(" going to ", " gonna ").replace(" right now ", " rn ").replace(" to be honest", " tbh").replace(" i don't know", " idk")
		if rng.randf() < 0.5:
			padded = padded.replace("'", "")
		t = padded.strip_edges()
		if rng.randf() < 0.15:
			t = _typo(t, rng)
	return t


static func _typo(t: String, rng: RandomNumberGenerator) -> String:
	var words := t.split(" ")
	var idx: Array = []
	for i in words.size():
		if words[i].length() >= 5 and words[i].is_valid_identifier():
			idx.append(i)
	if idx.is_empty():
		return t
	var wi: int = idx[rng.randi() % idx.size()]
	var wd: String = words[wi]
	var c := rng.randi_range(1, wd.length() - 3)
	words[wi] = wd.substr(0, c) + wd[c + 1] + wd[c] + wd.substr(c + 2)
	return " ".join(words)


## One finished line: template for this voice, slots filled, styled.
## Returns [text, template] so callers can remember the template.
static func line(bank: Array, v: String, slots: Dictionary, rng: RandomNumberGenerator, avoid: Array = []) -> Array:
	var tpl := pick(bank, v, rng, avoid)
	if tpl == "":
		return ["", ""]
	return [style(fill(tpl, slots), v, rng), tpl]


# =============================================================================
# Local LLM prompts (optional): the stance is decided by the game first
# =============================================================================

const STANCE_TEXT := {
	"warm": "friendly and positive", "neutral": "neutral, brief", "cold": "cold and distant", "hostile": "hostile, you dislike them",
	"humble": "modest, deflecting the praise", "accept": "you accept the apology", "wary": "you half-accept, still wary",
	"reject": "you refuse the apology", "hurt": "hurt and disappointed", "angry": "angry, you fire back", "laugh": "you laugh it off",
	"meh": "unimpressed", "annoyed": "annoyed", "agree": "you agree with the idea", "suggest": "you suggest a tweak to the idea",
	"dismiss": "you brush it off", "spy": "you refuse to share your team's tactics", "good": "you're in good form",
	"bad": "you're in poor form", "yes": "you agree to practise together", "later": "you can't right now, maybe later",
	"no": "you say no", "interested": "you're genuinely interested in a move", "maybe": "you're non-committal",
	"already": "you're already teammates", "noclub": "they don't even have a club", "positive": "you'll put in a good word with your club",
	"fa": "you're a free agent too", "deflect": "you won't discuss money", "askcoach": "it's the coach's decision, not yours",
	"promise": "you promise them two starts", "earn": "they must earn their place", "pushy": "they're being pushy",
	"furious": "furious at their disrespect", "thanks": "appreciative", "likes": "you like the idea", "igl": "leave calls to the IGL",
	"later_c": "contract talk later", "longterm": "they're part of the long-term plan", "focus": "focus on playing, not money",
	"under": "they're under contract, don't think about other clubs", "noted": "you'll take a look",
}


static func llm_system(ctx: Dictionary) -> String:
	var v: String = ctx.get("voice", "pro")
	var who := "You are %s, a %s-year-old professional esports player (%s) in a top-down Counter-Strike style game" % [ctx.get("name", "a player"), str(ctx.get("age", 22)), ctx.get("role", "Rifler")]
	if String(ctx.get("team", "")) != "":
		who += ", playing for %s" % ctx.team
	if bool(ctx.get("coach", false)):
		who = "You are %s, head coach of the esports team %s" % [ctx.get("name", "the coach"), ctx.get("team", "")]
	var lines: Array = [who + ".",
		"Personality: %s." % VOICE_TEXT.get(v, "normal"),
		"Mood: %s." % ctx.get("mood", "okay"),
		"Your relationship with %s: %s." % [ctx.get("me", "them"), ctx.get("relation", "neutral")]]
	if String(ctx.get("events", "")) != "":
		lines.append("Recent events: %s." % ctx.events)
	lines.append("How you feel about what they just said (the outcome is decided: keep to it, but say it your own way): %s." % STANCE_TEXT.get(String(ctx.get("stance", "")), String(ctx.get("stance", "neutral"))))
	lines.append("This is a private text conversation. Answer what they actually just wrote, pick up on earlier messages, and keep it going like a real person would: react, joke, ask something back now and then, don't repeat yourself. If it's a group chat, others may have spoken; you can react to them too.")
	lines.append("Text like a real player: 1-2 short lines, casual, in character. No hashtags, no quotation marks, no narration or actions in asterisks, never mention being an AI or a game. Under 35 words.")
	return "\n".join(lines)
