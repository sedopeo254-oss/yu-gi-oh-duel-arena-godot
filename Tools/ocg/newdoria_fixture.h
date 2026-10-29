// Bounded real-card fixture; only project-authored Lua and reviewed numeric data.
// Included inside probe.cpp's private namespace after the common bridge helpers.

uint32_t real_fixture_card(uint32_t code, card_data* data) {
    for (const auto& row : REFERENCE_CARDS) {
        if (row.code != code) continue;
        data->clear();
        data->code = row.code;
        data->type = row.type;
        data->level = row.level;
        data->attribute = row.attribute;
        data->race = row.race;
        data->attack = row.attack;
        data->defense = row.defense;
        return 0;
    }
    return fixture_card(code, data);
}

uint8_t* newdoria_script(const char* name, int* length) {
    if (std::strcmp(name, "./script/c4335645.lua") == 0) {
        *length = sizeof(NEWDORIA_LUA) - 1;
        return reinterpret_cast<uint8_t*>(const_cast<char*>(NEWDORIA_LUA));
    }
    if (std::strcmp(name, "newdoria-predicate-checks.lua") == 0) {
        *length = sizeof(NEWDORIA_CHECKS) - 1;
        return reinterpret_cast<uint8_t*>(const_cast<char*>(NEWDORIA_CHECKS));
    }
    if (std::strcmp(name, "./script/constant.lua") == 0) {
        // Export only the constants used by our owned effect, from the actual
        // pinned MIT headers. No GPL constant/utility script is imported.
        static const std::string constants = []() {
            std::ostringstream out;
#define EXPOSE_LUA_CONSTANT(name) out << #name << '=' << uint64_t(name) << '\n';
            EXPOSE_LUA_CONSTANT(CATEGORY_DESTROY)
            EXPOSE_LUA_CONSTANT(EFFECT_TYPE_SINGLE)
            EXPOSE_LUA_CONSTANT(EFFECT_TYPE_TRIGGER_F)
            EXPOSE_LUA_CONSTANT(EVENT_BATTLE_DESTROYED)
            EXPOSE_LUA_CONSTANT(EFFECT_FLAG_CARD_TARGET)
            EXPOSE_LUA_CONSTANT(LOCATION_GRAVE)
            EXPOSE_LUA_CONSTANT(LOCATION_MZONE)
            EXPOSE_LUA_CONSTANT(REASON_BATTLE)
            EXPOSE_LUA_CONSTANT(REASON_EFFECT)
#undef EXPOSE_LUA_CONSTANT
            return out.str();
        }();
        *length = int(constants.size());
        return reinterpret_cast<uint8_t*>(const_cast<char*>(constants.data()));
    }
    return fixture_script(name, length);
}

void apply_choice(intptr_t duel, const Choice& choice) {
    if (choice.bytes.empty()) set_responsei(duel, choice.integer);
    else {
        std::array<uint8_t, SIZE_RETURN_VALUE> response{};
        require(choice.bytes.size() <= response.size(), "oversized fixture response");
        std::copy(choice.bytes.begin(), choice.bytes.end(), response.begin());
        set_responseb(duel, response.data());
    }
}

const Choice& find_choice(const Prompt& prompt, const std::string& kind, uint32_t code = 0, int controller = -1) {
    for (const auto& choice : prompt.choices)
        if (choice.kind == kind && (!code || choice.card_code == code) &&
            (controller < 0 || int(choice.card_location & 0xff) == controller)) return choice;
    throw std::runtime_error("missing real-card scenario choice: " + kind);
}

void set_newdoria_callbacks() {
    set_script_reader(newdoria_script);
    set_card_reader(real_fixture_card);
    set_message_handler(core_message);
}

void arrange_newdoria(intptr_t duel, bool target_own_monster, bool mutual) {
    new_card(duel, 4335645, 0, 0, LOCATION_MZONE, 0, mutual ? POS_FACEUP_ATTACK : POS_FACEUP_DEFENSE);
    new_card(duel, 32541773, 1, 1, LOCATION_MZONE, 0, POS_FACEUP_ATTACK);
    if (target_own_monster)
        new_card(duel, 32541773, 0, 0, LOCATION_MZONE, 1, POS_FACEUP_ATTACK);
}

void run_newdoria(uint32_t seed, bool target_own_monster, bool mutual) {
    constexpr uint32_t NEWDORIA = 4335645;
    constexpr uint32_t PORTRAIT = 32541773;
    set_newdoria_callbacks();
    DuelOwner owner(seed);
    const intptr_t duel = owner.handle;
    // Arrange a board position, not a claim of a complete legal deck setup.
    arrange_newdoria(duel, target_own_monster, mutual);
    require(preload_script(duel, "newdoria-predicate-checks.lua") && callback_error.empty(),
            "Newdoria predicate-level negative controls failed");
    setup_fixture(duel);
    Probe probe{duel};
    probe.allow_battle_effects = true;
    Prompt prompt = probe.pump();
    require(prompt.player == 0 && prompt.kind == MSG_SELECT_IDLECMD, "missing initial main-phase prompt");
    apply_choice(duel, find_choice(prompt, "end_turn"));
    prompt = probe.pump();
    require(prompt.player == 1 && probe.turns == 2, "battle must occur on ordinary turn two");
    apply_choice(duel, find_choice(prompt, "battle_phase"));
    prompt = probe.pump();
    require(prompt.player == 1 && prompt.kind == MSG_SELECT_BATTLECMD, "missing battle command");
    apply_choice(duel, find_choice(prompt, "attack", PORTRAIT, 1));
    prompt = probe.pump();
    if (prompt.kind == MSG_SELECT_CARD && prompt.player == 1) {
        apply_choice(duel, find_choice(prompt, "select_monster", NEWDORIA, 0));
        prompt = probe.pump();
    }
    int forced_prompts = 0;
    if (prompt.kind == MSG_SELECT_CHAIN) {
        require(prompt.player == 0, "Newdoria trigger belongs to its controller");
        for (const auto& choice : prompt.choices)
            require(choice.kind != "pass_chain", "Newdoria must not be made optional");
        ++forced_prompts;
        const auto effect_choice = find_choice(prompt, "chain_effect", NEWDORIA);
        set_responsei(duel, -1);
        require(probe.pump().kind == MSG_RETRY, "mandatory Newdoria trigger unexpectedly allowed decline");
        apply_choice(duel, effect_choice);
        prompt = probe.pump();
    }
    if (mutual) {
        require(prompt.kind == MSG_SELECT_BATTLECMD && probe.chains_solved == 1,
                "mandatory Newdoria chain must resolve even without a remaining monster target");
        for (int player = 0; player < 2; ++player) {
            require(query_field_count(duel, player, LOCATION_MZONE) == 0 &&
                    query_field_count(duel, player, LOCATION_GRAVE) == 1,
                    "equal ATK must destroy both monsters in battle");
            require(probe.life_points[player] == 8000, "equal ATK battle dealt unexpected damage");
        }
        int battle_moves = 0, effect_moves = 0;
        for (const auto& move : probe.moves) {
            if (((move.to >> 8) & 0xff) != LOCATION_GRAVE) continue;
            if (move.reason & REASON_BATTLE) ++battle_moves;
            if (move.reason & REASON_EFFECT) ++effect_moves;
        }
        require(battle_moves == 2 && effect_moves == 0, "no-target trigger must not invent effect destruction");
        std::cout << "{\"status\":\"ok\",\"scenario\":\"newdoria-mutual-no-target\",\"chains_solved\":1,"
                  << "\"battle_destroyed\":2,\"effect_destroyed\":0,\"graveyard_counts\":[1,1]}\n";
        return;
    }
    require(prompt.kind == MSG_SELECT_CARD && prompt.player == 0, "missing Newdoria target decision");
    require(query_field_count(duel, 0, LOCATION_GRAVE) == 1, "Newdoria must reach the GY before triggering");
    const int selected_controller = target_own_monster ? 0 : 1;
    const Choice target = find_choice(prompt, "select_monster", PORTRAIT, selected_controller);
    require(probe.attacks == 1 && probe.damage_start == 1, "effect must follow a real battle");
    apply_choice(duel, target);
    prompt = probe.pump();
    require(prompt.kind == MSG_SELECT_BATTLECMD && prompt.player == 1, "chain did not finish back in the Battle Phase");
    require(probe.chains_solved == 1 && probe.damage_end == 1, "Newdoria chain/damage-step completion missing");
    require(probe.life_points[0] == 8000 && probe.life_points[1] == 8000, "attack into lower DEF should cause no LP damage");
    require(query_field_count(duel, selected_controller, LOCATION_MZONE) == 0, "Newdoria target remained on field");
    require(query_field_count(duel, 0, LOCATION_GRAVE) == (target_own_monster ? 2 : 1), "wrong player-zero graveyard count");
    require(query_field_count(duel, 1, LOCATION_GRAVE) == (target_own_monster ? 0 : 1), "wrong player-one graveyard count");
    bool battle_destroyed = false, effect_destroyed = false;
    for (const auto& move : probe.moves) {
        if (move.code == NEWDORIA && ((move.to >> 8) & 0xff) == LOCATION_GRAVE && (move.reason & REASON_BATTLE))
            battle_destroyed = true;
        if (move.code == PORTRAIT && int(move.to & 0xff) == selected_controller &&
            ((move.to >> 8) & 0xff) == LOCATION_GRAVE && (move.reason & REASON_EFFECT))
            effect_destroyed = true;
    }
    require(battle_destroyed && effect_destroyed, "battle-versus-effect destruction provenance mismatch");
    std::cout << "{\"schema_version\":1,\"status\":\"ok\",\"core_revision\":\"" OCG_REVISION
        "\",\"scenario\":\"newdoria-battle-trigger\",\"script_sha256\":\"" << NEWDORIA_LUA_SHA256
        << "\",\"seed\":" << seed << ",\"newdoria_code\":4335645,\"portrait_code\":32541773,"
        << "\"target_controller\":" << selected_controller << ",\"battle_turn\":2,\"attacks\":1,"
        << "\"battle_destroyed_newdoria\":true,\"effect_destroyed_target\":true,\"chains_solved\":1,"
        << "\"forced_chain_prompts\":" << forced_prompts << ",\"life_points\":[8000,8000],"
        << "\"graveyard_counts\":[" << query_field_count(duel, 0, LOCATION_GRAVE) << ','
        << query_field_count(duel, 1, LOCATION_GRAVE) << "]}\n";
}
