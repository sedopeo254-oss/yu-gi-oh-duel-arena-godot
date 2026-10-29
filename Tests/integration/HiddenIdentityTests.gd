class_name HiddenIdentityTests
extends RefCounted

## Regression for the public Deck-list-order attack, at the production UI boundary.
static func run() -> TestCase:
	var t := TestCase.new("HiddenIdentityTests")
	_test_opening_hands_do_not_identify_cards(t)
	_test_handles_and_historical_events(t)
	_test_decision_enums_and_deck_handles(t)
	_test_all_six_duels_keep_hidden_ids_opaque(t)
	return t


static func _test_opening_hands_do_not_identify_cards(t: TestCase) -> void:
	t.start("hidden hand identifiers do not reveal the public pre-shuffle Deck-list slot")
	var attacked := 0
	var hits := 0
	var blind := 0
	for seed_value in [7, 73, 2026]:
		for first in [0, 1]:
			var d0 := TestFixtures.real_deck(0)
			var d1 := TestFixtures.real_deck(1)
			var decks: Array = [d0["cards"], d1["cards"]]
			var session := EngineSession.new()
			t.is_true(session.start_duel(decks, [d0["name"], d1["name"]], seed_value, first),
				"session starts for seed %d, first player %d" % [seed_value, first])
			var harness := EngineSessionTests.Harness.new(session)
			var message := harness.next()
			t.eq(message.get("type"), "prompt", "opening prompt arrived")
			if message.get("type") == "prompt":
				var viewer := int(message["player"])
				var owner := 1 - viewer
				var engine := session.debug_engine()
				var hand: Array = engine.state.player(owner).hand
				var entries: Array = message["view"]["players"][owner]["hand"]
				var counts := {}
				for card in hand:
					counts[card.card_name()] = int(counts.get(card.card_name(), 0)) + 1
				blind += int(counts.values().max())
				for i in range(entries.size()):
					if not bool(entries[i].get("hidden", false)):
						continue
					attacked += 1
					var slot: int = int(entries[i]["id"]) - 1 - (decks[0].size() if owner == 1 else 0)
					if slot >= 0 and slot < decks[owner].size() \
							and decks[owner][slot].name == hand[i].card_name():
						hits += 1
			session.stop()
	t.is_true(attacked >= 30, "non-vacuity: both channels and three seeds exposed %d stubs" % attacked)
	t.is_true(hits <= blind, "Deck-list attack hits %d / %d, no more than blind baseline %d"
		% [hits, attacked, blind])
	print("  [identity] Deck-list attack: %d/%d hits, blind baseline %d" % [hits, attacked, blind])


static func _test_handles_and_historical_events(t: TestCase) -> void:
	t.start("handles are shared by views/offers/events, expire on movement, and reject raw guesses")
	var d := TestFixtures.new_duel(7111, 0)
	var engine: DuelEngine = d["engine"]
	var s := engine.state
	var card := TestFixtures.give_monster_on_field(engine, 1,
		TestFixtures.monster("Hidden identity probe", 4, 1000, 1000), Enums.Position.FACE_DOWN_DEFENSE)
	var identities := EngineSession.Identity.new()
	var record := func(event: GameEvent): identities.record(event, s)
	s.event_recorded.connect(record)
	identities.begin_message(0)
	var view := identities.view(s.get_visible_state(0), 0, s)
	var handle := int(view["players"][1]["monster_zones"][card.zone_index]["id"])
	t.is_true(handle < -1, "a hidden field card has an opaque handle, not its registration id")
	t.eq(identities.view(s.get_visible_state(0), 0, s), view, "re-reading a fixed board is stable")
	var offer: Dictionary = identities.payload({"target_candidates": [card.id]}, 0, s)
	t.eq(offer["target_candidates"], [handle], "target candidates use the visible stub's handle")
	t.eq(identities.decode_choices({"choices": {"target_ids": [handle]}}, 0, s)["choices"]["target_ids"],
		[card.id], "the current opaque target resolves to the right engine card")
	t.eq(identities.decode_choices({"choices": {"target_ids": [card.id]}}, 0, s)["choices"]["target_ids"],
		[0], "guessing a positive hidden engine id is rejected")
	s.emit(GameEvent.Kind.TARGET_SELECTED, {"target_id": card.id})
	# A subsequent event listener changes the board synchronously: capture must precede it.
	var flip := func(event: GameEvent):
		if event.kind == GameEvent.Kind.ATTACK_TARGET_SELECTED:
			s.set_battle_position(card, Enums.Position.FACE_UP_DEFENSE, true)
	s.event_emitted.connect(flip)
	s.emit(GameEvent.Kind.ATTACK_TARGET_SELECTED, {"target_id": card.id})
	s.event_emitted.disconnect(flip)
	var log := identities.drain_log(0)
	t.eq(log[0]["data"]["target_id"], handle, "historical target retains its original hidden handle")
	t.eq(log[1]["kind"], "ATTACK_TARGET_SELECTED", "nested effect events do not reorder the log")
	t.eq(log[1]["data"]["target_id"], handle, "visibility is captured before mutating event listeners")
	t.eq(identities.view(s.get_visible_state(0), 0, s)["players"][1]["monster_zones"][card.zone_index]["id"],
		card.id, "a revealed card is public")
	s.move_card(card, Enums.Zone.HAND, Enums.MoveReason.RETURNED_TO_HAND)
	view = identities.view(s.get_visible_state(0), 0, s)
	var hand_handle := int((view["players"][1]["hand"] as Array).back()["id"])
	t.ne(hand_handle, handle, "a returned card cannot keep its old field handle in the hand")
	log = identities.drain_log(0)
	var move: Dictionary = log.filter(func(event): return event["kind"] == "CARD_MOVED")[0]
	t.ne(move["data"]["card_id"], hand_handle,
		"a public named return event must not identify the new hidden-hand stub")
	s.move_card(card, Enums.Zone.MONSTER_ZONE, Enums.MoveReason.SET,
		{"position": Enums.Position.FACE_DOWN_DEFENSE})
	view = identities.view(s.get_visible_state(0), 0, s)
	var fresh := int(view["players"][1]["monster_zones"][card.zone_index]["id"])
	t.ne(fresh, handle, "setting the returned card creates a new field handle")
	t.ne(fresh, hand_handle, "a Set is not linkable to its hidden-hand handle")
	t.eq(identities.decode_choices({"choices": {"attack_target_id": handle}}, 0, s)["choices"]["attack_target_id"],
		0, "the expired field handle cannot select a card on its new stay")
	s.move_card(card, Enums.Zone.GRAVEYARD, Enums.MoveReason.DESTROYED_BY_EFFECT)
	s.move_card(card, Enums.Zone.MONSTER_ZONE, Enums.MoveReason.SUMMONED,
		{"position": Enums.Position.FACE_DOWN_DEFENSE})
	view = identities.view(s.get_visible_state(0), 0, s)
	t.ne(view["players"][1]["monster_zones"][card.zone_index]["id"], fresh,
		"even a non-hand field departure expires the field handle")
	s.event_recorded.disconnect(record)


static func _test_decision_enums_and_deck_handles(t: TestCase) -> void:
	t.start("option kinds distinguish card handles from enums, and Deck handles are temporary")
	var d := TestFixtures.new_duel(7112, 0)
	var s: GameState = d["engine"].state
	var card := TestFixtures.give_to_deck(d["engine"], 0,
		TestFixtures.monster("Deck candidate", 4, 1000, 1000))
	var identity := EngineSession.Identity.new()
	for kind in ["CHOOSE_POSITION", "CHOOSE_ZONE", "ORDER_TRIGGERS"]:
		var p: Dictionary = identity.payload({"kind": kind, "options": [0, 1, 2]}, 0, s)
		t.eq(p["options"], [0, 1, 2], "%s values are not mistaken for card ids" % kind)
	identity.begin_message(0)
	var req := {"kind": "SELECT_EXACTLY", "options": [card.id]}
	var first: Dictionary = identity.payload(req, 0, s)
	t.is_true(int(first["options"][0]) < -1, "Deck-selection option does not reveal registration order")
	s.shuffle_deck(0)
	identity.begin_message(0)
	var next: Dictionary = identity.payload(req, 0, s)
	t.ne(first["options"], next["options"], "Deck handles expire before another prompt, including after a shuffle")
	var start := GameEvent.new(GameEvent.Kind.DUEL_STARTED, {"seed": 7112, "first_player": 0})
	t.is_false(EngineSession.project_event(start, 0)["data"].has("seed"),
		"the player channel cannot reconstruct hidden shuffle order from the duel seed")
	var core := EngineSession.Core.new()
	core.engine = d["engine"]
	var request := DecisionRequest.select(Enums.DecisionKind.SELECT_EXACTLY, 0,
		"Choose from your Deck", [card.id], 1, 1)
	t.eq(core._option_labels(request, 0), ["Deck candidate"],
		"authorized own-Deck candidates are labelled without exposing the whole Deck")
	t.eq(core._option_labels(request, 1), [""], "opponent hidden candidates stay anonymous")


static func _test_all_six_duels_keep_hidden_ids_opaque(t: TestCase) -> void:
	t.start("all six real duels expose no registration-order identifier at any player's prompt")
	var inspected := 0
	var references := 0
	var leaks: Array = []
	for cfg in ScriptedDuelTests.DUELS:
		var d0 := TestFixtures.real_deck(0)
		var d1 := TestFixtures.real_deck(1)
		var session := EngineSession.new()
		session.start_duel([d0["cards"], d1["cards"]], [d0["name"], d1["name"]],
			int(cfg["seed"]), int(cfg["first"]))
		var h := EngineSessionTests.Harness.new(session, false)
		var policy := DuelDriver.new()
		policy.seed_value = int(cfg["seed"])
		policy.first_player = int(cfg["first"])
		policy.styles = cfg["styles"].duplicate()
		policy.surrender_on_turn = int(cfg.get("surrender_on_turn", -1))
		var answerer := DuelDriver.PolicyController.new(0, "identity policy")
		var out := {"outcome": "", "problems": [], "decisions": {}, "refused": 0}
		var audit: EventAudit = null
		var observed: GameState = null
		while true:
			var m := h.next()
			if m.is_empty() or m.get("type") != "prompt":
				t.eq(m.get("type"), "over", "%s reaches a terminal result" % cfg["label"])
				break
			var engine := session.debug_engine()
			if audit == null:
				observed = engine.state
				audit = EventAudit.new(observed)
				for event in observed.events:
					audit.record(event)
				observed.event_recorded.connect(audit.record)
			var viewer := int(m["player"])
			var hidden := _hidden_ids(observed, viewer)
			if m.has("offers"):
				var offers: Array = engine.get_pending_decision()["actions"]
				for i in range(offers.size()):
					references += _audit_references(EngineSession.offer_view(offers[i], i),
						m["offers"][i], hidden, leaks)
			for event in m["log"]:
				if (audit.pending[viewer] as Array).is_empty():
					leaks.append("projected event missing from independent event audit")
					continue
				var expected: Dictionary = audit.pending[viewer].pop_front()
				if expected["event"]["kind"] != event["kind"]:
					leaks.append("projected event order differs from independent emission order")
				references += _audit_references(expected["event"]["data"], event["data"],
					expected["hidden"], leaks, "", int(expected["named"]))
			for player in m["view"]["players"]:
				for zone in ["hand", "monster_zones", "spell_trap_zones", "excavated"]:
					for entry in player[zone]:
						if entry != null and bool(entry.get("hidden", false)):
							inspected += 1
							if int(entry["id"]) >= -1:
								leaks.append("%s: %s" % [cfg["label"], str(entry)])
				var field = player["field_zone"]
				if field != null and bool(field.get("hidden", false)):
					inspected += 1
					if int(field["id"]) >= -1:
						leaks.append("field: %s" % str(field))
			if not EngineSessionTests._answer_like_the_driver(h, policy, answerer, m, out):
				t.check(false, "session policy could not answer: %s" % str(out))
				break
		policy.engine = null
		if observed != null:
			observed.event_recorded.disconnect(audit.record)
		session.stop()
	t.is_true(references > 0, "non-vacuity: audited %d hidden offer/event references" % references)
	t.is_true(inspected > 1000, "non-vacuity: inspected %d hidden stubs through both channels" % inspected)
	t.eq(leaks, [], "no hidden stub, candidate or event reference yields a public Deck-list slot")
	print("  [identity] %d hidden stubs and %d hidden offer/event references audited" % [inspected, references])


## Independent event-time truth, recorded on the worker; read only while it is parked.
class EventAudit extends RefCounted:
	var state: GameState
	var pending: Array = [[], []]

	func _init(s: GameState) -> void:
		state = s

	func record(event: GameEvent) -> void:
		for viewer in [0, 1]:
			var projected = EngineSession.project_event(event, viewer)
			if projected != null:
				pending[viewer].append({"event": projected,
					"hidden": HiddenIdentityTests._hidden_ids(state, viewer),
					"named": int(event.data.get("card_id", -1)) if event.data.has("card_name") else -1})


static func _hidden_ids(state: GameState, viewer: int) -> Dictionary:
	var out := {}
	for card in state.all_instances():
		if viewer in card.revealed_to:
			continue
		if card.zone == Enums.Zone.DECK \
				or (card.zone in [Enums.Zone.HAND, Enums.Zone.EXTRA_DECK] and card.controller_id != viewer) \
				or (card.is_on_field() and not card.is_face_up() and card.controller_id != viewer):
			out[card.id] = true
	return out


static func _audit_references(raw, projected, hidden: Dictionary, leaks: Array,
		key: String = "", named: int = -1) -> int:
	var count := 0
	if raw is Dictionary:
		for field in raw:
			count += _audit_references(raw[field], projected.get(field), hidden, leaks, str(field), named)
	elif raw is Array:
		if not (projected is Array) or raw.size() != projected.size():
			leaks.append("candidate collection changed shape")
			return count
		for i in range(raw.size()):
			count += _audit_references(raw[i], projected[i], hidden, leaks, key, named)
	elif typeof(raw) == TYPE_INT and hidden.has(raw) and key in ["card_id", "source_card_id",
			"source_id", "target_id", "attacker_id", "defender_id", "attack_target_id", "by_card_id",
			"for_card_id", "substituted_by_card_id", "equipped_to_id", "card_ids", "target_ids",
			"tribute_ids", "target_candidates", "tribute_candidates", "tribute_combinations",
			"attack_target_candidates"]:
		if key == "card_id" and raw == named:
			return count
		count += 1
		if typeof(projected) != TYPE_INT or projected >= -1:
			leaks.append("hidden %s retained engine id %s" % [key, str(raw)])
	return count
