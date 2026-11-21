# Lockdown

Top-down tactical 5v5 shooter (T vs CT, bomb defusal) with a career layer. Godot 4.4, GDScript.

## Run
Open the folder in Godot 4.4+ and press F5.

**Controls:** WASD move, Shift (held) walk: half speed, no footsteps, mouse aim, left click shoot, R reload, 1 primary / 2 pistol / Q swap,
4 grenade in hand (press again for the next one; click throws at the cursor),
E (hold) plant/defuse, F pick up a gun, G drop (bomb first, else the gun in hand), Y ask the carrier
for the bomb (buy phase or live), B buy menu, Tab scoreboard, Enter continue, Esc leave (quick match only).
Right mouse (held) scopes in with scoped guns and looks further ahead. V in the buy phase: replay the last round.
Dead or spectating: click / right-click next / previous player (teammates only once you're dead),
Space free camera (WASD, Shift = fast), wheel zoom.

## The world (both careers)
`scripts/career/world.gd`: 64 teams in 4 leagues (Premier 90-97 / Pro 74-88 / Challenger 57-72 / Academy 40-55 team ratings, 16 each), ~600
uniquely named players (`NameGen`), 150 free agents. Season = 24 weeks: league round-robin (weeks 1-15),
top-8 playoffs (16-18), off-season cups; then top 2 promoted / bottom 2 relegated, contracts expire,
players age and retire, prospects arrive. Optional cups (Open / Challenger / Major) with league-based
eligibility. Transfer windows weeks 1-4 and 13-15 (all signings; free agents outside them only if you
can't field five). AI clubs have budgets,
sign free agents, buy from each other and sell when broke. Players are persistent across teams.
- **Overtime**: simulated matches never end level. At 5-5, overtime blocks of 4 rounds (first to 3) repeat until someone wins.
- **Chemistry**: each team's starting five gains chemistry the longer they've been together (new signings
  reset it). It's worth roughly -2 to +2 stat points on match day.
- **Nations and the World Cup**: every player has a nation. At the end of every second season the top 8
  nations (each nation's best five players) play a knockout World Cup.
- **Difficulty presets** (Casual / Normal / Hardcore), chosen when a career starts. They scale injuries,
  income, the board's patience, AI aggression for your players, refusals and a small match-day edge.
- **History** (both hubs): end-of-season review popup (league winners, playoff champions, promotions,
  cups, awards, biggest transfers, your season), champions per competition, world records, and a Hall
  of Fame of retired greats.
- **Achievements**: 24, kept across every save and both careers (main menu > Achievements).
- **Stats hub** (both careers): season leaders and a search across every player in the world.
- **Awards ceremony** at season end, before the review. **Watch live**: watch AI tournament matches; the result counts.
- **Editor** (main menu): team names, tags, colours and logo styles; player names and nations.
- **Map art** (`art/`): `python art/export_map.py <map> > art/maps/<map>.json`, then `blender -b art/blender/maps.blend --python art/blender/build_map.py -- <project> <map>... --save` (or `build` + `render` inside Blender) writes `assets/maps/<map>.png` (32 px per cell; the Arena draws it when present). All four maps have art. `THEMES` in build_map.py sets each map's look: Dustline desert town (cars, awnings), Harbor docks (sea, ships, containers), Foundry steelworks (machines, pipes, smokestacks), Cage concrete yard (jersey barriers, sandbags). `--percent 50 --out <dir>` renders previews. Source scenes: `art/blender/maps.blend`.
- **Weapon and bomb models**: `art/blender/gun_kit.py` builds all 21 guns plus the C4 (`GUNS`), and `showcase(keys, out_dir)` renders them. The in-game planted bomb `assets/sprites/c4_planted.png` is a top-down orthographic render of `c4` (320x240, transparent). Game gun sprites: `sprites(keys, "<project>/assets/guns")` writes `<key>_side.png`, `<key>_top.png`, `<key>_icon.png` (white silhouette) + `guns.json` (400 px/m, grip anchor). `scripts/game/gun_art.gd` (`GunArt`) draws them (held, floor, HUD, buy menu, kill feed), falling back to the old shapes for any gun without art. Turn mipmaps on in the imports of new sprites.
- **Player sprites**: `blender -b --factory-startup --python art/blender/player_kit.py -- <project>/assets/players [preview_dir|-]` renders every look (`ct`, `t`, `ct2`, `t2`) in both poses (`<key>_top.png` rifle, `<key>_pistol_top.png`) + `players.json` (300 px/m, 1.4 m square, hand points per pose). `scripts/game/player_art.gd` (`PlayerArt`) draws them; the held gun's grip (`gx` in guns.json, from `gun_kit.grip_point`) goes in the right hand. `art/blender/player_quick.py` is the older quick pass. Blender lives at the Steam install (`.../steamapps/common/Blender/blender.exe`).
- **Grenades**: `gun_kit.GRENADES` (frag, flash, smoke, incendiary, molotov) rendered with `sprites([...], <project>/assets/grenades, ppm=1600)`; drawn via `GunArt.draw_grenade`.
- **Knife**: `gun_kit.knife` (key `knife`), sprites in `assets/knife/` (`sprites(["knife"], <project>/assets/knife)`); drawn via `GunArt.draw_knife` (side view, swipe arc). Knife and draw sounds: `python art/audio/knife_sounds.py audio`.
- **VFX**: `assets/vfx/` (explosion and fire flipbooks, smoke puffs, scorch) come from the scripts in `art/vfx/` (Cycles volumes; fire is a Mantaflow sim). `scripts/game/vfx_layer.gd` (`VfxLayer`) draws them; smoke and fire drawing is stateless so the replay matches live play.
- **Team packs** (`scripts/data/real_teams.gd`): `data/real/` (HLTV ranking, 16 Nov 2026, top 64 + free agents) and `data/og/` (HLTV ranking, 28 Dec 2015, top 20), with logos. New careers pick one (Real teams / OG Teams checkboxes); the Editor can apply either to an existing save. Local only: delete a pack folder to remove it.
- **Saves**: written about a second after you act (and immediately when you leave a screen or quit),
  crash-safe (written to a temp file, then swapped in), with weekly backups (last 3) restorable in
  Settings. Settings also has an error log viewer.
- **Patch notes**: `scripts/data/patch_notes.gd` holds every update, newest first, shown from the main menu.
  Bump `PatchNotes.VERSION` and add an entry at the top for each update.

## Career Mode (manager)
Found your org (name, tag, colour, starting league, which team you take over). Investor capital,
sponsors (league + reputation), salaries, prize money; transfer portal (sign, bid, sell, release);
contracts (extend or lose players at season end); manual starting five; weekly training plan and an
upgradeable facility. Watch your matches (spectator, up to 8x, Esc sims the rest) or simulate them.
Hub: `scripts/ui/manager_hub.gd` (Overview, Inbox, Roster, Transfers, Club, League, Tournaments, Rankings, Finances, History).
- **Club page**:
  - **Board**: a season objective (from where your squad ranks) and a confidence meter. Below 10 you're
    sacked and must pick a job offer. Strong seasons bring offers from bigger clubs. Moving takes your
    staff with you but leaves the squad, money, sponsors, loans, academy and facilities behind.
  - **Staff**: Head Coach, Analyst, Physio, Scout, each rated 1-5 stars, paid weekly, with 4 weeks'
    wages to hire or fire.
  - **Facilities tree**: Training Center, Gaming House, Medical Room, Bootcamp, Analyst Room and Youth
    Academy. Some need others first, and each has weekly upkeep.
  - **Youth academy**: prospects aged 16-17 arrive each season and grow weekly. Promote, sell or release
    them; they leave at 20.
- **Scouting fog**: other clubs' players show estimates (faded, with a "?") until scouted. Send a scout
  from the player popup; 1 + scout stars players are covered a week.
- **Press conferences** before big matches; **player personalities** (Leader, Mentor, Troublemaker,
  Professional, Showman); **local derbies**; **loans** in and out (until season end); **club fans and
  merch**; an **affiliate** club as a second roster (Club page).
- **Contract clauses** when signing or extending:
  - release clause (lower wage, but any club paying it takes the player)
  - loyalty bonus (paid at the end of the deal; happier, likelier to sign)
  - appearance fees (lower wage, paid per match played)

- **Form, morale, bad days.** Every player has form (-8..+8 stat points: slumps and hot streaks, driven
  by results, morale and luck) and morale (benching, losing, unpaid wages). Before each match everyone
  rolls a day (off days / sharp days); form + day modify the gameplay curves (`PlayerData.match_mod`)
  and the simulator, never the displayed rating.
- **Match history.** Every player logs their last 30 matches (`PlayerData.match_log`) plus season totals.
  Click any player (roster, team popups, rankings) for the player card. Players carry a stable `uid`, so
  names can change and history follows them through transfers.
- **Clickable teams** in League, Tournaments brackets, Rankings and the overview table: squad + season
  stats tabs, rename (any team). Rename your own players from the roster.
- **Sponsorship.** Three slots (Main / Apparel / Partner). Offers arrive weekly (more on win streaks) in
  four styles: Steady, Performance (per-win bonus), Signing (cash up front), Goal (bonus for playoffs or
  a trophy). Ending a deal early costs 4 weeks of its fee.
- **Loans and investors** (`World.LENDERS`): banks/credit union/payday lender with weekly repayments,
  or equity investors who take a share of all income for 1-3 seasons. Pay off / buy out early.
- **Debt** costs reputation and morale; in week 3 creditors sell your most valuable player at 60%, in
  week 4 administrators force an emergency loan.
- **Bids for your players.** In windows, AI clubs bid cash or cash + one of their players (more for
  in-form or unhappy players). Accept, counter (+25%: they may agree, hold or walk) or decline.
- **Inbox** (`World.inbox`, `resolve_msg`): benched players ask to play (promise a spot / tell them to
  earn it / list them; broken promises hurt), unhappy players ask to leave (list / raise / refuse),
  in-form players ask for raises, contract reminders (weeks 12, 18, 22), staff suggestions (bootcamp,
  fan meet-up, free-agent tips, rest), sponsor extension offers, illness notices.
- **Transfer list**: listing a player brings bids over the following window weeks (no instant sales).
  Bids you make can include your own players. Some players refuse certain clubs (`PlayerData.refuses`).
- **Illness/injury**: players miss weeks; the lineup skips them. With under 5 fit players you can sign
  free agents outside windows, or forfeit (league fine 5% of the league prize pool; cups free).
- **Sponsors**: declining may bring one improved counter-offer, or they pull out; deals offer an
  extension 4 weeks before they end.
- **Cups**: registration opens 3 weeks before the start; overlapping cups clash. Brackets are drawn
  bracket-style; bracket matches are labelled with their stage (Quarter-final, Semi-final, Final).
- Roster rows drag-and-drop to reorder.
- **The Wire.** Bloomberg-style ticker along the bottom: team ratings with weekly change, plus world
  headlines (upsets, streaks, transfers, slumps, sponsorships). `scripts/ui/news_ticker.gd`.

## My Player
Your own character in the same world, on an AI-run club. Hub (`scripts/ui/player_hub.gd`) pages:
Overview, Inbox, Messages, Feed, Home, Shop, Profile, Training, Career, Team, League, Tournaments, Stats, History, plus the news ticker.
- **Shop** (`scripts/career/lifestyle.gd`, `scripts/ui/shop_view.gd`): property, cars, home extras, pets, style,
  weapon finishes (tint your guns in matches), personal staff and investments. Each item has an effect and weekly upkeep.
- **Home** (`scenes/home.tscn`, `scripts/home/home.gd`): walk around the place you live (9 homes from a rented room
  to the Sky duplex). E uses furniture (sleep, PC practice/stream, demos, cook, gym, drive, pets...), P opens your
  phone (invite a teammate, house party, vacation). Layouts: `art/homes/layouts.py` -> `data/homes/*.json`
  (validated: everything reachable). Art: `art/blender/build_home.py` -> `assets/homes/<id>.png` shells and
  `assets/homes/props/<kind>.png` furniture; casual bodies from `art/blender/player_kit.py -- --casual assets/homes`.
- **Streaming** (Training page): Off / Casual / Heavy. Earns money and followers, but builds fatigue;
  fatigue over 40 hurts form and raises injury risk.
- **Dressing room**: relationships with each teammate, shaped by duo practice, team dinners, blame
  after losses and jealousy over your fame. Friends lift each other on match day; rivals drag each other down.
- **Signature traits** earned from how you play (Entry King, Survivor, Damage Dealer, AWP God,
  Mr. Consistent, Big Stage, Clutch Minister), each adding a small stat bonus.
- **National team**: pick your nation at creation; the World Cup counts caps, and winning it goes in the
  trophy cabinet.
- **Coach your club** after retiring: it becomes a new manager career with that team.
- **Agents** (Career page): better wages, negotiation and interest from bigger clubs, for a cut of your wage.
- **Feed** page: fans, the press, rivals, teammates, clubs and brands react to what you do. **Post**
  your own text with a tone chip (hype team, call out a rival, flame a teammate, blame the coach, fire back
  at haters, apologise, neutral). `ChatText` reads the text (club and player names, insults, praise,
  apologies) and can overrule the chip; `Social.post()` applies the fallout (followers, teammate relations
  and morale, coach trust, toxicity, fines, sponsors dropping you, a rival fired up via `trash_target`)
  and generates slot-filled replies threaded under the post. 3 posts a week, with diminishing gains.
- **Messages** page (`scripts/ui/social_view.gd`): DMs with any player, the team group chat and the
  coach. Free text is read for intent (sign/join, contract, praise, apology, flame, strats, banter, form,
  practice, lineup...) and answered from templates in each player's voice (persona/role: toxic, chill, IGL,
  pro, showman, shy, mentor), mood and relationship. Effects are real: courted free agents and players can
  join your club or push for a move, asking a player about their club raises its interest in you, teammate
  chat moves relations/morale, the coach thread moves coach trust (and can promise starts). Bots message
  you first after big games, when you're benched or released, and after rivalry games. Threads are saved
  (capped). Rate-limited: only the first messages each week move relations; spamming annoys people.
- **Friends and rivals**: `World.relations` covers every player (time as teammates, DMs, posts) and
  combines with head-to-head `rivals`. Match chat API: `World.relation_to_user(p)` ("friend"/"rival"/""),
  `World.relation_strength(p)` (-1..1), `World.team_rivalry(t)` (trash talk, recent finals, derby, top rival's club).
- **Discipline**: bad form, toxic posts, flaming teammates, falling out with the coach, sulking, a
  transfer request, a better signing at your role and budget cuts build pressure: a warning, then a
  disciplinary bench, then release. Released mid-season you have no club (`World.teamless`).
- **Ways back** (Career page): weekly showmatches (playable through the exhibition match mode, or
  simulated) raise club interest; trial invites (a practice match decides the offer); your agent shops
  you around (lower leagues first, better clubs as interest recovers); stand-in calls from clubs with an
  injured player (good spells become permanent). Toxicity scares clubs off.
- **Where conversations lead** (`scripts/career/club_talk.gd`, `Social.talk`): the coach (personality per club:
  players' coach / disciplinarian / tactician) weighs a start request (recent ratings and form vs the starter
  ahead of you, training, trust, tone) and can start you (`start_bonus()` in `World.lineup_bonus`), promise next
  week, or get annoyed; team-chat flaming and coach insults make teammates complain and run the discipline
  path to bench/release; "release me / transfer me" lists you, terminates you or is refused. Other clubs'
  players pass you to their coach (thread `xc:<team>`, next week: offer, pre-agreement, trial or a reasoned
  no). `attitude(team)` (interested/neutral/wary/won't sign, with reasons) gates `World._add_offer`; shown as
  "How clubs see you" on the Career page. DM trash talk sets fired-up/tilted `match_mod` for the next meeting.
- **Local AI chat (optional)**: Settings > Local AI chat (Ollama), URL and model (default
  `llama3.2:3b`). After the game has decided a message's effects and stance, `LlmClient`
  (`scripts/career/llm_client.gd`) asks Ollama's `/api/chat` to word the reply in character (6 s timeout);
  any failure keeps the template line. Never changes effects.
- **Lineup**: the coach picks the five on rating, form and **coach trust** (0-100). Rookies get a few
  guaranteed starts. Benched or injured: watch the match from the bench (spectate) or simulate.
- **Contract and wallet**: weekly wage into your own wallet. Renewal offer at week 12 of your final
  season (sign, let your agent push, or reject); an expired deal means free agency: pick one of the
  offers before the season can go on.
- **Inbox**: bench calls (accept / demand a start / request a transfer), interviews (humble,
  confident, trash talk: fame vs trust; the trash-talked team gets fired up), role changes,
  teammates asking for duo practice, bids your club accepted (go or refuse), endorsements, awards.
- **Transfers**: offers come from clubs up to a league higher and within reach of your level; request
  a transfer (the club can refuse); good form attracts offers; very poor form and low trust can get you traded.
- **Training**: Light / Normal / Hard (injury risk), a specialty after 15 matches (+35% on its
  stats), gaming setup upgrades and a personal coach paid from your wallet.
- **Form, morale, illness and injury** apply to you too.
- **Season goals** (rating, kills, matches, a team target) pay a bonus plus trust and fame.
- **Perks** at milestones (matches, kills, trophies, followers, Player of the Match awards).
- **Awards**: Player of the Match, league MVP, Rookie of the Year, Team of the Season, Player of the
  Year, All-Star picks (a playable, non-counting showcase at the start of next season).
- **Profile**: career stats, trophy cabinet (wins, runner-up, promotions), awards, timeline per
  season and club, perks, rivalries (head to head against the best opponent each match), legacy.
- **Fans**: followers grow with performances, titles and interviews, and unlock personal sponsors.
- **Aging and retirement**: decline from 30, the option to retire from 30, forced at 38; your legacy
  tier is shown and you can go straight into a manager career.
Tests: `tests/world_runner.tscn`, `tests/manager_flow.tscn`, `tests/test_runner.tscn`, `tests/my_player_probe.tscn`.

## Team AI (scripts/game/tactics.gd + bot_controller.gd)
- Shared knowledge per side: last-known enemies (sight, gunfire, footsteps), angles cleared by teammates,
  and round maths (can we still plant / defuse in time?).
- Ts: each site has auto-computed "angles to clear" (Arena.site_angles: corners a CT could hold that the
  entrances can't see). Entering Ts split them up and pre-aim one each; the carrier sits on the plant
  spot and plants once the site is clear. Post-plant spots are computed at plant (hidden from CT retake
  approaches, eyes on the bomb, spread for crossfires). Attackers don't chase far contacts mid-execute.
- CTs: active jiggle-peeks while holding, an info play in quiet rounds, graded rotation calls (a dead
  anchor counts), rotators gather at a stage and go in together, retakes clear post-plant spots before
  the defuse.
- Holding a contact (BotController._plan_hold): the bot paths the enemy's likely route to it, finds
  the first point of it each nearby spot can see, and picks a spot that sees that point at a good range
  for its gun, hidden from where the enemy is now, outside the cone they'll pre-aim (their last sight of
  us), off their walking line, with cover a step away, and in crossfire with teammates on the same entry.
  Crosshair goes on the edge they appear from; the hold lasts about as long as their walk in (re-hearing
  them on the same route extends it); it stands and shoots when they appear and reloads in cover.
  `--ab=old_hold` restores the old behaviour; tests/hold_duel.tscn (`--trials= --debug`) A/B tests it.
- Trading: when a teammate dies nearby, players swing the killer fast.
- Weapons: every switch (gun, pistol, knife on 3, grenades) takes Unit.DRAW_TIME (1 s). Knife: Unit._slash
  (40 front, 150 backstab, KNIFE_SPEED). Bots: reload only hidden from `reload_threat()`, else cover / pistol
  (`_manage_weapon_in_fight`), knife as a last resort; they turn away from flashes about to pop (`_watch_flashes`),
  spray into smokes hiding a known enemy (plan "spam"), and never hold from inside a smoke.
- Vision: you see with your own eyes only; scripts/game/minimap.gd shows teammates and enemy callouts (from
  Tactics.seen_by, refreshed at most every 1.6 s per enemy). Match.user_sees() hides hit effects on unseen enemies.
- Smokes (Utility): frags blow a hole (FRAG_HOLE_T), bullets punch a lane (`on_bullet`); `blocks()` samples the
  chord through the cloud against the holes; VfxLayer.draw_smoke thins the cloud there.
- T routes: `_limit_mid` caps how many Ts go through mid each round (0-3, history-aware). Savers and bomb escapers
  hide via `_hide_spot` (clear of the 630 px blast, out of known enemies' sight, in corners).
- Dev tests: tests/knife_shot.tscn (screenshots: knife, smoke holes), tests/save_hide.tscn (bomb-save hiding).
- Saving: Ts who can't plant in time / are hopelessly outnumbered (and CTs who can't defuse in time)
  retreat and keep their guns; it weighs gear and team money; Decision Making decides how reliably.
- Exit time: after a round is decided there are 5 live seconds. Winners hunt savers, losers run;
  anyone alive at the end keeps their weapons.
- Spectate shows each bot's current thought ("bomb: on site, waiting for clear", "rotating B: gathering").
- Skill curves (PlayerData._curve): steep below 60, flatter at the top. 40-rated bots react in ~1s
  and miss most shots; 60 vs 70 is competitive; a 20-point gap is a blowout.
- Dev probes: tests/ai_probe.tscn (`--map= --rounds= --equal --mismatch=45,65 --trace`),
  tests/balance_runner.tscn (`--equal --map=`), tests/aim_duel.tscn, tests/audio_probe.tscn,
  tests/esc_probe.tscn, tests/hold_duel.tscn.

### Personalities, decisions, comms
- Every player has stable habits (`scripts/game/bot_personality.gd`, seeded from their name): aggression,
  patience, discipline and a peek style (wide-swinger, info-peeker, shoulder-baiter, angle-holder).
- On a contact, bots score their options (hold, jiggle, swing, shoulder bait, push, reposition to an
  off-angle, flank) from the situation and their habits, then pick one; poor decision makers are noisier.
  Stale contacts are dropped after a while instead of being held forever.
- Bots aim where they last saw / heard you and have to flick: callouts and sounds are rough (±40-120 px)
  and refresh about once every 1.2 s. Walking (silent) when lurking, sneaking up on intel, flanking.
- Cover hides the whole body (no shoulder sticking out past the wall).
- Reaction: holding still on a post is fast (holder's advantage); clearing corners on a hunch is slow,
  plus a surprise delay when nobody knew you were there.
- Match memory: CTs stack the site the Ts keep hitting, Ts avoid where CTs were seen and repeat what won,
  fakes (go loud on one site, hit the other), anti-eco aggressive CT setup.
- Team radio: strat calls, spots ("2 near B!"), rotations, plant/retake calls, death info — shown above
  the health panel for your team (both teams when spectating).

### Teamwork
- Dropped bomb: the nearest T goes for it ("Bomb's down mid, I'll get it"), the next one holds an angle
  over the pickup, and the execute waits until it's back (unless the clock is short). Fetchers and late
  Ts cut side-fights short.
- CTs who know where it dropped (killed the carrier / can see it) close in with the 1-2 nearest players
  (more when time is short or they have the numbers); someone else with sight holds the angle. In the
  last 25 s, if it's quiet, they sit on it.
- Executes: the player leading each route waits at the entrance until a teammate is in trade range;
  followers keep trade distance. Waiting is capped (4 s) so nobody stands at a door forever. The lurker
  joins once the team is on site (or ~14 s into the hit).
- A teammate dying nearby makes bots re-think mid-plan (trade swing). Retakes wait for nearly the whole
  team (up to 5 s after the first arrives, less with the bomb timer low).
- Stuck-hold guards: contact plans have a hard cap even while intel keeps trickling in; Ts with the clock
  running out ignore far-away noise and go for the site.

### Feel: imperfect information, stress, mistakes (bot_controller.gd + tactics.gd)
- **Beliefs, not truth.** Team intel (`Tactics.seen_by`) holds markers: `seen` (fades into a "ghost"
  once out of sight), `heard` and `call`, each with an uncertainty radius and a confidence that decays
  (`belief_conf`). Sounds (`Tactics.hear`): running footsteps 460px, reloads 380, plant/defuse 800, shots
  1300 (the suppressed Sentry 700). The nearest enemy in earshot hears it. The marker's error grows with
  distance and shrinks with Positioning + Decision Making, and that bot turns to check the spot.
- Bots pre-aim and clear the believed spot. A heard marker someone looks at and finds empty is cleared.
  A ghost is only cleared up close, because they just stepped out of view. Aggressive bots (and the
  "prefire" habit) prefire a fresh ghost when they swing it.
- Leak audit: cleared angles, frags on "known" enemies, utility on a defuser (must be within earshot),
  "bomb carrier" tells (only if someone saw it), shots from out of view and teammates' death callouts
  all use rough or believed positions now.
- **Fake reads**: T utility and noise near a site count as evidence (`Tactics.evidence`). Low-decision
  teams weigh it heavily and rotate on it, so fakes work on them. Rotation timing varies:
  early, late or on time.
- **Stress** (`BotController.stress`, 0-1): low HP, being outnumbered or last alive, flashes, a losing
  streak, taking damage and teammates dying. It widens flick error and hand jitter, causes panic
  sprays and hurried / bad re-peeks. Composure (personality), Decision Making and morale resist it.
- **Human mistakes** (rarer for higher-rated bots): dry peeks without the available flash, reloading
  on a live angle, whiffed flicks, overpeeking after a kill (aggressive / "hothead"), losing track of
  the bomb timer (wrong retake / escape timing).
- **Crosshair habits**: holds sit on the edge of the angle (where a peeker appears first), walking
  bots glance at corners in a natural sweep, AWP angles get baited with jiggles / shoulder peeks,
  wide vs tight swings by personality, strafing between bursts.
- **Trades**: every player has a trade partner (`Tactics.trade_partner`): the follower behind an
  execute's route lead, otherwise the nearest teammate within 450px. When a player dies his partner
  swings the killer in a refrag window. Before a swing, bots throw a flash (theirs or a nearby
  teammate's: "Flashing it for you") and wait for it to pop. Lone players don't get traded.
- **Difficulty**: `BotController.mistake_mult` (static, default 1.0) scales all of the mistakes and stress.

### Depth: IGL, adaptation, styles, chat
- **In-game leader** (`Tactics.igl`): the best decision maker alive makes the calls and changes the
  plan mid-round: "We're up 2, hit now", "Down 2, slow it down", "They're stacked A, rotate B",
  "Two down mid, one rotate B", save calls, post-plant "play time" vs "play for picks".
- **Adapting**: each team remembers where the Ts hit, CT early picks, rushes, strat records and the
  last strat. CTs stack the hit site, stop pushing out into rushes and push more when early picks
  work. Ts go slow default against early aggression and switch strats after 2+ losses in a row.
  **Economy read**: from the guns they carry (misreads for poor IGLs). Against an eco, CTs push out,
  Ts rush and every bot takes fights more readily.
- **Retakes / post-plant**: crossfire spots, "time" vs "picks" post-plant play, whole-team saves when
  a retake is hopeless (2v4 with the clock low), CT fake defuses (tap, let go, hold the angle; Ts that
  hear it peek).
- **Team styles** (`Tactics.team_style(team_name)`, stable from the name): aggressive (rushes,
  aggressive CT setups), default (slow defaults, later calls), utility (more nades bought and thrown),
  awp (a second sniper, AWPers buy on forces).
- **Player habits** (`BotPersonality.habits(player)`, stable from uid / name): early_peek, awp_angle
  (same favourite hold), prefire, jiggler, hothead, nade_happy, silent, clutch_calm.
- **Chat**: rare all-chat lines from bots (glhf, ns, nt, wp, taunts from trash-talkers after aces /
  clutches, gg) in the radio stack, max 3 a round.
- **F3 debug overlay**: belief markers (seen / ghost / heard / callout, uncertainty circles, cleared X),
  every bot's stress bar, its contact memory, plan and trade partner, each side's latest call and live
  metrics.
- Metrics: `balance_runner` prints trade rate, fakes bitten, aim at believed vs true position and
  mistake counts. `behavior_runner` adds hearing, ghost-clearing, trade and stress scenarios.
  `tests/ai_debug_probe.tscn` checks helpers, IGL calls, the overlay and chat (screenshots).

## Audio
Buses Master -> SFX / Weapons / UI with volume sliders in Settings (UI = "Interface"). Every button,
checkbox, dropdown and slider gets hover / click / confirm / back / tab / toggle sounds automatically
(`scripts/autoload/ui_sounds.gd`; opt out per control with `set_meta("ui_sound", "none")`); the buy
menu plays a buy or can't-afford sound. Fast-forward thins out repeats (per-sound rate limit), drops
footsteps/impacts at 4x+, and lowers effects 5 dB per speed doubling.

**Gun sounds**: every gun has its own firing sound, `audio/guns/<key>.wav`, where `<key>` is the
`sound` field in `WeaponData.TABLE` (pk9, sentry, raptor, longbow, ...). They are derived offline from
the original recordings (pitch shifts, EQ, transient shaping, saturation, layered thumps/tails, a
bolt rack on the Pathfinder and a pump on the Breacher, a suppressed thwip for the Sentry), loudness
matched with peaks at or below -3 dBFS. `Sfx.shot_sound()` returns `guns/<key>|<category sound>`; if a
gun's file is missing the old category sound (`pistol_shot`, `t_rifle_shot`, ...) plays instead.
Per-gun shots use at most +-3% random pitch. Check: `tests/gun_sound_probe.tscn` (`-- --test`).

## Display
Fullscreen is exclusive so the window is exactly the screen size and the 1280x720 UI scales by an exact
factor. Fonts use full hinting with no subpixel positioning and the UI's default texture filter is
nearest, so text lands on whole pixels; the match world switches back to linear filtering.

## UI
`scripts/ui/ui.gd` is the design system: palette, Bahnschrift/Segoe UI system fonts, theme (buttons:
default / PrimaryButton / GhostButton / DangerButton / NavButton), and components (cards, team badges,
rating chips, stat chips, pills, striped tables, sidebar nav, attribute bars, backdrop). All menus and
the match HUD (`scripts/game/hud.gd`) are built from it. HUD: CS-style player squares with names either
side of the score bar (alive/dead, HP strip, bomb), mag bar and reload ring on the crosshair, red damage flash and a
low-HP pulse below 50 HP, your bot teammates' current plan shown under them. Table headers for
attributes explain the stat on hover, with values computed from the real curves (`PlayerData.stat_tooltip`).
Simulated matches show the same results screen as watched ones (`World.sim_box_score`). Review renders: `tests/ui_shots.tscn`,
`tests/hud_shots.tscn` (`-- --test --windowed --out=<dir>`).

## Maps
Dustline (100x64), Harbor (104x68), Foundry (96x90, vertical) and the small Cage (56x34). Each map is a
data file in `scripts/maps/` (floors, cover, sites, spawns, named points, A/B main/alt/short routes, site
holds). Which site each area leads to is computed from walking distances. `tests/map_check.tscn` validates
every map and renders overview PNGs.

## Rules
- First to 6 of 10 rounds. Sides swap after round 5; money resets.
- **Overtime** at 5-5 (`Match.match_decided`): blocks of 4 rounds, first to 3 in the block wins; sides
  stay for the first 2, swap for the last 2; 2-2 plays another block. Everyone restarts each OT half on
  $10,000. The score bar shows OVERTIME n; the results screen says "after overtime". A playable match
  never ends in a draw. Esc-sim (`_sim_rest_of_match`) plays OT too.
- 10s buy phase. $800 start, $16k cap, CS-style win/loss rewards, loss bonus, $800 plant bonus.
- Bomb: 4s plant inside A/B, 45s fuse, 10s defuse (5s with kit). Dropped bomb can be picked up.
- Dead players drop their primary (or a bought pistol); anyone can pick it up (F; pistols go to the
  pistol slot). Bots grab clearly better guns nearby.
- Grenades (`scripts/game/utility.gd`, max 4, 2 flashes): Flashbang $200 (blinds by distance and
  facing; your own team gets 30%), Smoke $300 (blocks sight 16s), Frag $300 (98 dmg blast, line of
  sight), Molotov $400 / Incendiary $500 (7s fire, smoke puts it out). Unused grenades carry over.
  Bots buy and throw them by the Utility stat: T smokes/mollies on CT angles and entry flashes, CT
  mollies/smokes/frags on a push and retake flashes, mollies on a defuser, frags on known enemies.
- When the bomb is about to blow, bots who can't stop or finish a defuse run out of the blast.
- Ts win by elimination or detonation; CTs by elimination (pre-plant), defuse, or time.

### Weapons (`scripts/data/weapon_data.gd`)
21 guns, each with its own damage, fire rate, mag, spread, run-and-gun penalty, recoil, armour
penetration, range falloff (per 500px), move speed and kill reward. `cat` (Pistol / SMG / Shotgun /
Rifle / Sniper / Heavy) drives behaviour; `id` (100+) is the gun.

| Slot | Gun | Side | Price | Kill $ | Notes |
|---|---|---|---|---|---|
| Pistol | PK-9 | T | 200 | 300 | T starter, 20 rounds |
| Pistol | Sentry .45 | CT | 200 | 300 | CT starter, accurate, suppressed |
| Pistol | Duster P7 | both | 300 | 300 | cheap armour-piercing upgrade |
| Pistol | Viper MP | T | 500 | 300 | fast-firing, poor on the move |
| Pistol | Falcon 5.7 | CT | 500 | 300 | 20 rounds, good penetration |
| Pistol | Magnum .50 | both | 700 | 300 | 58 dmg, heavy recoil |
| SMG | Hornet M10 | T | 1050 | 600 | fast, inaccurate, run-and-gun |
| SMG | Kestrel K9 | CT | 1250 | 600 | fast, steadier |
| SMG | Bulldog .45 | both | 1200 | 600 | slower, harder hitting |
| SMG | Swarm 50 | both | 2350 | 300 | 50-round mag |
| Shotgun | Breacher Pump | both | 1050 | 900 | 8 pellets, steep falloff |
| Shotgun | Tempest Auto-12 | both | 1800 | 900 | semi-auto |
| Heavy | Hammer LMG | both | 1900 | 300 | 100 rounds, slow, sprays |
| Rifle | Kodiak AR | T | 1800 | 300 | cheap T rifle, 35 rounds |
| Rifle | Lancer F2 | CT | 2050 | 300 | cheap CT rifle |
| Rifle | Raptor 762 | T | 2700 | 300 | main T rifle, hits hard |
| Rifle | Guardian 556 | CT | 2900 | 300 | main CT rifle, low recoil |
| Rifle | Talon SR / Overwatch SR | T / CT | 3000 / 3300 | 300 | scoped rifles |
| Sniper | Pathfinder | both | 1700 | 300 | light bolt-action, 80 dmg, full speed |
| Sniper | Longbow .338 | both | 4750 | 100 | one-shot body hits through armour |

- Scoped guns (snipers, scoped rifles) add spread unscoped. Scoping in takes 0.3s and slows you to
  55%. You: hold right mouse. Bots scope in whenever they stand still, and wait for the scope before
  a shot.
- Gear: Kevlar $650 (absorbs 35% of damage, less against armour-piercing guns), Kevlar + Helmet
  $1000 ($350 over full kevlar; absorbs 42%), Defuse Kit $400 (CT).
- **Buy menu** (B): six columns, 1 Pistols / 2 SMGs / 3 Rifles / 4 Heavy / 5 Gear / 6 Grenades. Press
  the column number then the item number (0 / Backspace back, Esc / B close), or click. Shows your
  money, prices (red when you can't afford them), OWNED, and the other side's guns greyed out as
  T ONLY / CT ONLY. Hover shows the stats. Right-click something you bought this buy phase to sell it
  back for the full price (the gun you had before comes back). Buying a pistol replaces your pistol
  slot; buying a primary replaces your primary.
- **Bot buys** (`Match.team_buy_plan` / `_bot_buy`): the team calls pistol / eco / force / full.
  Full when the average player can afford a rifle and armour (owned guns count); force on must-win
  rounds (opponent on match point, last round of a half) or when saving wouldn't reach a full buy
  next round; eco otherwise (poor decision makers force anyway). By role: AWPers buy the Longbow on
  full buys and the Pathfinder on forces; Entry fraggers take SMGs or the Breacher on forces; Support
  keeps money for utility; Riflers sometimes take the scoped rifle. Helmets on full buys, pistol
  upgrades on pistol rounds, forces without a gun and when rich.
- **Bot use**: snipers hold still and scoped, peek-shoot-duck; shotguns hang back from long fights
  and push close ones; SMGs run and gun at close range and avoid long ones; the LMG sprays.

### Replays, kill-cam, highlights (`scripts/game/replay.gd`)
- Every live round is recorded at 20 Hz (positions, aim, HP, bomb, weapon, smokes/fires) with shots,
  kills and bomb events, kept for the whole match.
- **Kill-cam**: when you die, the last 4 seconds play back from your killer's position (their view
  cone shown), then spectating continues. Space / click skips it.
- **Round replays**: V in the buy phase (or "Round replays" on the results screen). Play/pause (Space),
  seek (Left / Right, or drag the timeline), speed 0.25x-8x (- / =), previous / next round (P / N),
  follow players (click / right-click / Tab), overview (F), Esc closes. The match is paused meanwhile.
- **Highlights** (results screen): up to 6 best moments, auto-picked: 3K / 4K / ACE rounds and clutches
  won 1vX (X >= 2). Yours when you played, anyone's when spectating or in manager mode. Kills in the
  5s exit time after a round is decided don't count.
- The result passed to `Game.finish_player_match` / `finish_manager_match` / `finish_allstar`
  (`Match.match_result()`) is `{"score", "rounds", "players", "highlights", "overtimes"}`;
  `"highlights"` is `{PlayerData: int}` (3k+ rounds + clutches won, simulated 3k+ rounds included,
  every starter present).

## AI
- `scripts/game/tactics.gd` is the team brain. T strategies: Execute A/B, Rush A/B, Split A/B (with a
  lurker), Default (spread, then call the site where fewer CTs were spotted). Ts walk real routes to
  staging points, execute together, cover the planter, then hold post-plant angles.
- CT setups: Standard 2-1-2, Stack A, Stack B (sometimes an aggressive mid). CTs share sightings;
  2+ Ts spotted on a site pulls mid, 3+ rotates everyone but one anchor (one may flank instead).
  After a plant they stage from two sides, then retake together; hopeless 1vX may save.
- `bot_controller.gd`: spotting delay from Reaction Time + distance; jiggle-peeks from cover while
  holding (AWPers/patient players hold open); evades + turns when shot from out of view; ducks back when
  hurt/reloading and after AWP shots; swaps to pistol when dry; holds the angle where an enemy vanished;
  trades; pre-aims intel from callouts, gunfire (1300px) and running footsteps (520px).
- Vision cones (`Match.sees`): everyone, player included, sees a cone (width from Positioning) plus
  120px close awareness and peripheral movement; walls block it. Teammates' cones are shared.
- Contact memory: when an enemy vanishes / is heard / shoots from out of view, bots remember where and
  choose hold, jiggle (info peek), swing (pre-aimed wide peek), push (chase), or fallback, weighing
  health, numbers, ammo, weapon, role, time pressure and whether they're defending.
- `tests/behavior_runner.tscn` checks: last CT retakes/defuses, bots react when shot from behind, holders peek.
- Map knowledge (routes, holds, cover spots, regions) is data in `arena.gd`.

## Bot aim
Bots react (Reaction Time), then swing their crosshair at a limited speed (Flick Speed, ~280-900 deg/s)
that brakes as it lands, with a flick error that settles (Aim), hand jitter, and tracking lag on moving
targets. They fire in bursts and duck into nearby cover between bursts, then decide how to re-peek.
They steer around teammates and sidestep/re-path when blocked.

## Players
Nine attributes (20-100): Aim, Flick Speed (time to target), Preaim, Recoil Control, Reaction Time,
Movement, Positioning, Decision Making, Utility. Rating = average. They drive bot behaviour, and spread/recoil/movement
for the human player too. Growth comes from match performance (HLTV-style match rating) and one
training session per matchday, scaled by age and a hidden potential. 30+ players decline.
Utility drives bot grenade buying and throwing.

## Layout
- `scripts/autoload/game.gd` — `Game` singleton: My Player, career league, schedule, sims, transfers, saves (`user://`).
- `scripts/data/` — `PlayerData`, `TeamData`, `WeaponData`, `Progression`.
- `scripts/game/match.gd` — round flow, economy, bomb, and the bots' team "brain" (objectives).
- `scripts/game/arena.gd` — grid map with sites/spawns, collision, A*.
- `scripts/game/unit.gd`, `player_controller.gd`, `bot_controller.gd`, `bullet_layer.gd`, `hud.gd`,
  `replay.gd` (round recorder, replays, kill-cam, highlights).
- `scripts/ui/` — main menu, My Player, career hub (built in code via `UI` helpers).

## Dev tests (headless, use separate `test_` saves)
```
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test     # career + one full match
godot --headless --path . --fixed-fps 60 res://tests/balance_runner.tscn -- --test  # T vs CT round balance (--matches=N --equal), guns carried
godot --path . res://tests/arsenal_probe.tscn -- --test --windowed --out=<dir>      # guns, buy menu keys, sell-back, bot buys, overtime, replays, kill-cam, highlights
godot --path . res://tests/ai_debug_probe.tscn -- --test --windowed --out=<dir>    # team styles, habits, IGL calls, F3 AI overlay, chat
godot --path . res://tests/screenshot_runner.tscn -- --test --out=<dir>             # screenshots
godot --path . res://tests/feature_probe.tscn -- --test --windowed --out=<dir>      # bomb request, gun drops, death spectate
godot --path . res://tests/grenade_probe.tscn -- --test --windowed --out=<dir>      # grenades, bomb escape, on-site plant
godot --path . res://tests/ui_sound_probe.tscn -- --test --windowed                # interface sounds fire
godot --path . res://tests/fairness_probe.tscn --fixed-fps 60 -- --test --windowed  # no off-screen spotting; surprise reaction
godot --path . res://tests/career_probe.tscn -- --test --windowed --out=<dir>      # sponsors, loans, debt, bids, renames, form, history
godot --path . res://tests/my_player_probe.tscn -- --test --windowed --out=<dir>   # My Player: contract, bench, inbox, transfers, goals, awards, retirement
godot --headless --path . res://tests/my_player_seasons.tscn -- --test              # a whole simulated My Player career, one line per season
godot --path . res://tests/b10_probe.tscn -- --test --windowed --out=<dir>         # personalities, derbies, loans, affiliate, agents, feed, logos, backups
godot --headless --path . res://tests/outcomes_probe.tscn -- --test                # coach case, escalations, leaving, other clubs' coaches, club attitudes, DM trash talk
godot --headless --path . res://tests/social_probe.tscn -- --test                  # posts, DMs, team chat, coach, friends/rivals API, discipline, release, ways back, LLM fallback
godot --path . res://tests/fit_sweep.tscn -- --test --out=<dir>                    # presses every hub button at 1280x720 and reports anything off-screen
godot --path . res://tests/club_probe.tscn -- --test --windowed --out=<dir>        # staff, facilities, academy, scouting, board, clauses, history, achievements, My Player extras
```
