extends RefCounted

## Opt-in arranged test scenario, NOT a production deck/card-library addition.
## After initial fixture placement every showcase beat is a legally offered engine action.
## No fake animation events and no modification of the production game state by a renderer.
var engine: DuelEngine
var portrait: CardInstance
var weak_target: CardInstance
var strong_target: CardInstance
var identity := EngineSession.Identity.new()
var step := 0
var error := ""

func _init() -> void:
	engine = TestFixtures.new_duel(32541773, 0)["engine"]
	TestFixtures.advance_to_phase(engine, Enums.Phase.MAIN_1)
	var definition := TestFixtures.monster("The Portrait's Secret", 4, 1200, 1500, "EARTH", "Fiend")
	definition.passcode = "32541773"
	definition.konami_cid = "5219"
	definition.source_url = "https://www.db.yugioh-card.com/yugiohdb/card_search.action?cid=5219&ope=2"
	definition.text = "Animation test fixture: EARTH / Fiend / Normal, Level 4, ATK 1200 / DEF 1500."
	portrait = TestFixtures.give_to_hand(engine, 0, definition)
	weak_target = TestFixtures.give_monster_on_field(engine, 1, TestFixtures.monster("Training target", 4, 300, 300), Enums.Position.FACE_UP_ATTACK, 0)
	strong_target = TestFixtures.give_monster_on_field(engine, 1, TestFixtures.monster("Counterattacker", 4, 2000, 1500), Enums.Position.FACE_UP_ATTACK, 1)
	engine.state.event_recorded.connect(_record)

func _record(event: GameEvent) -> void:
	identity.record(event, engine.state)

func snapshot(viewer: int = 0) -> Dictionary:
	identity.begin_message(viewer)
	return identity.view(engine.get_visible_state(viewer), viewer, engine.state)

func drain(viewer: int = 0) -> Array:
	return identity.drain_log(viewer)

func advance() -> String:
	var caption := ""
	var accepted := false
	match step:
		0:
			caption = "SUMMON · empty frame → torn canvas → claw and eyes"
			accepted = _submit(Enums.ActionKind.NORMAL_SUMMON, portrait)
		1, 2:
			# Manual changes are illegal on the summon turn / twice in one turn.
			# Advance full legal turns instead of overriding those restrictions.
			TestFixtures.end_turn(engine)
			TestFixtures.end_turn(engine)
			TestFixtures.advance_to_phase(engine, Enums.Phase.MAIN_1)
			caption = "DEFENSE · retract and reverse the frame" if step == 1 else "ATTACK POSITION · uncover and emerge"
			accepted = _submit(Enums.ActionKind.CHANGE_POSITION, portrait)
		3:
			caption = "ATTACK · frame lunge and green / purple claw slash"
			TestFixtures.advance_to_phase(engine, Enums.Phase.BATTLE)
			accepted = TestFixtures.attack(engine, portrait, weak_target)
		4:
			caption = "DESTRUCTION · cracked wood, vertical tear, gray dust"
			TestFixtures.end_turn(engine)
			TestFixtures.advance_to_phase(engine, Enums.Phase.BATTLE)
			accepted = TestFixtures.attack(engine, strong_target, portrait)
		_:
			return "COMPLETE · replay to run a fresh deterministic fixture"
	TestFixtures.pass_until_open(engine)
	if not accepted: error = "Engine refused scenario step %d" % step
	step += 1
	return caption if accepted else error

func _submit(kind: Enums.ActionKind, card: CardInstance) -> bool:
	var action = TestFixtures.find_action(engine.get_legal_actions(card.controller_id), kind, card.id)
	return action != null and engine.submit_action(action)
