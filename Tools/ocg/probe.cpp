// Optional Fluorohydride-core diagnostic, not the game's authoritative backend.
// Protocol source: pinned common.h, playerop.cpp and operations.cpp (see lock.json).
// Defaults to synthetic Normal Monsters. Newdoria modes admit two reviewed cards
// and one owned Lua effect; practice mode uses six reviewed Normal Monsters.
// No arbitrary executable scripts, external database, or tournament deck claim.
#include "ocgapi.h"
#include "card_data.h"
#include "effect.h"
#include "reference_cards.h"
#include <array>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <limits>
#include <random>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
#include <unistd.h>

#ifndef OCG_REVISION
#error Build with Tools/build_ocg_probe.py to embed the pinned core revision.
#endif

namespace {
constexpr uint32_t FIRST_FIXTURE = 900000001;
std::string callback_error;

void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

// Callback buffers outlive every core call. Exceptions must never cross the C API.
uint8_t* fixture_script(const char* name, int* length) {
    static uint8_t empty[] = "-- Normal-only diagnostic; no external Lua assets.\n";
    if (std::strcmp(name, "./script/constant.lua") == 0 ||
        std::strcmp(name, "./script/utility.lua") == 0 ||
        std::strcmp(name, "./script/procedure.lua") == 0) {
        *length = sizeof(empty) - 1;
        return empty;
    }
    callback_error = "unsupported script requested";
    *length = 0;
    return nullptr;
}

uint32_t fixture_card(uint32_t code, card_data* data) {
    data->clear();
    if (code < FIRST_FIXTURE || code >= FIRST_FIXTURE + 80) {
        callback_error = "unsupported fixture card requested";
        return 0;
    }
    data->code = code;
    data->type = TYPE_MONSTER | TYPE_NORMAL;
    data->level = 4;
    data->attribute = ATTRIBUTE_EARTH;
    data->race = RACE_WARRIOR;
    data->attack = 1500;
    data->defense = 1000;
    return 0;
}

uint32_t core_message(intptr_t duel, uint32_t) {
    char message[4096]{};
    get_log_message(duel, message);
    callback_error = message;
    return 0;
}

struct DuelOwner {
    intptr_t handle;
    explicit DuelOwner(uint32_t seed) {
        std::array<uint32_t, SEED_COUNT> seeds{};
        // Explicit versioned seed expansion, independent of platform std::hash.
        for (size_t i = 0; i < seeds.size(); ++i)
            seeds[i] = seed + uint32_t(i) * UINT32_C(0x9e3779b9);
        handle = create_duel_v2(seeds.data());
        require(handle != 0, "create_duel_v2 failed");
    }
    ~DuelOwner() { end_duel(handle); }
    DuelOwner(const DuelOwner&) = delete;
    DuelOwner& operator=(const DuelOwner&) = delete;
};

struct Reader {
    const std::vector<uint8_t>& bytes;
    size_t cursor = 0;
    uint32_t read(size_t count) {
        require(count <= 4 && cursor + count <= bytes.size(), "truncated core message");
        uint32_t result = 0;
        for (size_t i = 0; i < count; ++i) result |= uint32_t(bytes[cursor++]) << (8 * i);
        return result;
    }
    void skip(size_t count) {
        require(cursor + count <= bytes.size(), "truncated core payload");
        cursor += count;
    }
};

struct Choice {
    std::string kind;
    std::string label;
    int32_t integer = 0;
    std::vector<uint8_t> bytes;
    uint32_t card_code = 0;
    uint32_t card_location = 0;
};

struct Prompt {
    int kind = 0;
    int player = -1;
    int summonable = 0;
    bool battle = false;
    bool end = false;
    bool shuffle = false;
    uint32_t forbidden_zones = 0;
    std::vector<Choice> choices;
};

struct Probe {
    intptr_t duel;
    uint64_t digest = UINT64_C(14695981039346656037);
    int turn_player = -1;
    int phase = 0;
    int turns = 0;
    int summoned = 0;
    int retried = 0;
    int messages = 0;
    int winner = -1;
    int win_reason = 0;
    bool allow_battle_effects = false;
    bool practice_mode = false;
    int attacks = 0;
    int chains_solved = 0;
    int damage_start = 0;
    int damage_end = 0;
    std::array<int, 2> life_points{{8000, 8000}};
    struct Move { uint32_t code, from, to, reason; };
    std::vector<Move> moves{};

    Prompt decode(const std::vector<uint8_t>& bytes) {
        Reader r{bytes};
        Prompt prompt;
        for (auto byte : bytes) { digest ^= byte; digest *= UINT64_C(1099511628211); }
        while (r.cursor < bytes.size()) {
            const auto kind = r.read(1);
            ++messages;
            switch (kind) {
            case MSG_WIN: winner = r.read(1); win_reason = r.read(1); break;
            case MSG_RETRY: ++retried; prompt.kind = MSG_RETRY; break;
            case MSG_HINT: r.skip(6); break;
            case MSG_NEW_TURN: turn_player = r.read(1); ++turns; break;
            case MSG_NEW_PHASE: phase = r.read(2); break;
            case MSG_SHUFFLE_DECK: r.skip(1); break;
            case MSG_DRAW:
            case MSG_SHUFFLE_HAND: {
                r.skip(1);
                const auto count = r.read(1);
                r.skip(count * 4);
                break;
            }
            case MSG_MOVE: {
                const auto code = r.read(4), from = r.read(4), to = r.read(4), reason = r.read(4);
                moves.push_back({code, from, to, reason});
                break;
            }
            case MSG_SET:
            case MSG_FLIPSUMMONING:
                require(practice_mode, "set/flip is outside this scenario");
                r.skip(8); break;
            case MSG_FLIPSUMMONED:
                require(practice_mode, "flip is outside this scenario"); break;
            case MSG_POS_CHANGE:
                require(practice_mode, "position changes are outside this scenario");
                r.skip(9); break;
            case MSG_SUMMONING: r.skip(8); break;
            case MSG_SUMMONED: ++summoned; break;
            case MSG_ATTACK:
                require(allow_battle_effects, "battle is outside the normal reference session");
                ++attacks; r.skip(8); break;
            case MSG_BATTLE:
                require(allow_battle_effects, "battle is outside the normal reference session");
                r.skip(26); break;
            case MSG_DAMAGE_STEP_START: ++damage_start; break;
            case MSG_DAMAGE_STEP_END: ++damage_end; break;
            case MSG_CHAINING:
                require(allow_battle_effects, "chains are outside the normal reference session");
                r.skip(16); break;
            case MSG_CHAINED: r.skip(1); break;
            case MSG_CHAIN_SOLVING: r.skip(1); break;
            case MSG_CHAIN_SOLVED: ++chains_solved; r.skip(1); break;
            case MSG_CHAIN_END: break;
            case MSG_BECOME_TARGET: { const auto count = r.read(1); r.skip(count * 4); break; }
            case MSG_DAMAGE: {
                const auto player = r.read(1), amount = r.read(4);
                require(player < 2 && amount <= 100000, "invalid damage event");
                life_points[player] -= int(amount);
                break;
            }
            case MSG_SELECT_BATTLECMD: {
                require(allow_battle_effects && prompt.kind == 0, "unsupported battle prompt");
                prompt.kind = kind;
                prompt.player = r.read(1);
                require(r.read(1) == 0, "battle fixture has no activatable battle effects");
                const auto count = r.read(1);
                for (uint32_t index = 0; index < count; ++index) {
                    const auto code = r.read(4);
                    const auto controller = r.read(1), location = r.read(1), sequence = r.read(1);
                    r.skip(1); // direct-attack capability; the scenario chooses a real target.
                    prompt.choices.push_back({"attack", "Attack from your monster zone " + std::to_string(sequence + 1), int32_t((index << 16) | 1), {},
                        code, controller | (location << 8) | (sequence << 16)});
                }
                if (r.read(1)) prompt.choices.push_back({"main_two", "Enter Main Phase 2", 2, {}});
                if (r.read(1)) prompt.choices.push_back({"end_turn", "End turn", 3, {}});
                break;
            }
            case MSG_SELECT_IDLECMD: {
                require(prompt.kind == 0, "multiple prompts in one packet");
                prompt.kind = kind;
                prompt.player = r.read(1);
                for (int group = 0; group < 6; ++group) {
                    auto count = r.read(1);
                    if (group == 0) prompt.summonable = count;
                    for (uint32_t index = 0; index < count; ++index) {
                        const auto code = r.read(4); // Only owner-visible snapshots expose hand identity.
                        const auto controller = r.read(1);
                        const auto location = r.read(1);
                        const auto sequence = r.read(1);
                        if (group == 0) {
                            require(controller == uint32_t(prompt.player) && location == LOCATION_HAND,
                                    "unsupported normal summon candidate location");
                            prompt.choices.push_back({"normal_summon", "Normal Summon from hand slot " +
                                std::to_string(sequence + 1), int32_t(index << 16), {}});
                        }
                        if (practice_mode && (group == 2 || group == 3)) {
                            require(controller == uint32_t(prompt.player) && location == (group == 2 ? LOCATION_MZONE : LOCATION_HAND),
                                    "unsupported position/set candidate location");
                            prompt.choices.push_back({group == 2 ? "reposition" : "set_monster",
                                group == 2 ? "Change position / Flip Summon monster zone " + std::to_string(sequence + 1)
                                           : "Set face-down from hand slot " + std::to_string(sequence + 1),
                                int32_t((index << 16) | group), {}, code, controller | (location << 8) | (sequence << 16)});
                        }
                        if (group == 5) r.skip(4);
                    }
                }
                prompt.battle = r.read(1) != 0;
                prompt.end = r.read(1) != 0;
                prompt.shuffle = r.read(1) != 0;
                if (allow_battle_effects && prompt.battle)
                    prompt.choices.push_back({"battle_phase", "Enter Battle Phase", 6, {}});
                if (prompt.end) prompt.choices.push_back({"end_turn", "End turn", 7, {}});
                if (prompt.shuffle) prompt.choices.push_back({"shuffle_hand", "Shuffle own hand", 8, {}});
                break;
            }
            case MSG_SELECT_POSITION: {
                require(practice_mode && prompt.kind == 0, "unsupported position prompt");
                prompt.kind = kind;
                prompt.player = r.read(1);
                r.skip(4); // Card identity is already confined to this player's view.
                const auto mask = r.read(1);
                require(mask > 0 && mask <= 15, "invalid position mask");
                for (uint32_t position : {1u, 2u, 4u, 8u})
                    if (mask & position)
                        prompt.choices.push_back({"choose_position", std::string(position & POS_FACEUP ? "Face-up " : "Face-down ") +
                            (position & POS_ATTACK ? "Attack Position" : "Defense Position"), int32_t(position), {}});
                break;
            }
            case MSG_SELECT_PLACE:
                require(prompt.kind == 0, "multiple prompts in one packet");
                prompt.kind = kind;
                prompt.player = r.read(1);
                require(r.read(1) == 1, "unsupported multi-place selection");
                prompt.forbidden_zones = r.read(4);
                for (uint8_t slot = 0; slot < 5; ++slot)
                    if (!(prompt.forbidden_zones & (uint32_t(1) << slot)))
                        prompt.choices.push_back({"choose_zone", "Main monster zone " + std::to_string(slot + 1),
                            0, {uint8_t(prompt.player), LOCATION_MZONE, slot}});
                break;
            case MSG_SELECT_CARD: {
                require(prompt.kind == 0, "multiple prompts in one packet");
                prompt.kind = kind;
                prompt.player = r.read(1);
                const auto cancelable = r.read(1);
                const auto minimum = r.read(1);
                const auto maximum = r.read(1);
                const auto count = r.read(1);
                require((cancelable == 0 || allow_battle_effects) && minimum == 1 && maximum == 1,
                        "reference session only supports single-card hand-limit discards");
                for (uint32_t index = 0; index < count; ++index) {
                    const auto code = r.read(4);
                    const auto location = r.read(4);
                    const bool field_target = allow_battle_effects && ((location >> 8) & 0xff) == LOCATION_MZONE;
                    require(field_target || ((location & 0xff) == uint32_t(prompt.player) && ((location >> 8) & 0xff) == LOCATION_HAND),
                            "reference session only supports own-hand discard candidates");
                    prompt.choices.push_back({field_target ? "select_monster" : "discard",
                        field_target ? "Player " + std::to_string((location & 0xff) + 1) + " monster zone " + std::to_string(((location >> 16) & 0xff) + 1)
                                     : "Discard hand slot " + std::to_string(((location >> 16) & 0xff) + 1),
                        0, {1, uint8_t(index)}, code, location});
                }
                break;
            }
            case MSG_SELECT_CHAIN: {
                require(prompt.kind == 0, "multiple prompts in one packet");
                prompt.kind = kind;
                prompt.player = r.read(1);
                const auto count = r.read(1);
                require(allow_battle_effects || count == 0, "effect chains are outside this diagnostic");
                r.skip(9); // special count + two timing masks (no chain candidates)
                bool mandatory = false;
                for (uint32_t index = 0; index < count; ++index) {
                    r.skip(1); // descriptor
                    mandatory = r.read(1) != 0 || mandatory;
                    const auto code = r.read(4), location = r.read(4);
                    r.skip(4); // effect description
                    prompt.choices.push_back({"chain_effect", "Activate the offered effect", int32_t(index), {}, code, location});
                }
                if (count && !mandatory) prompt.choices.push_back({"pass_chain", "Pass optional response", -1, {}});
                break;
            }
            default:
                throw std::runtime_error("unsupported core message: " + std::to_string(kind));
            }
        }
        return prompt;
    }

    Prompt pump() {
        for (int tick = 0; tick < 256; ++tick) {
            const auto state = process(duel);
            require(callback_error.empty(), "core callback: " + callback_error);
            const auto length = state & PROCESSOR_BUFFER_LEN;
            require(length <= 65536, "core packet exceeds diagnostic limit");
            std::vector<uint8_t> bytes(length ? length : 1);
            const auto actual = get_message(duel, bytes.data());
            require(actual >= 0 && uint32_t(actual) == length, "core message length mismatch");
            bytes.resize(length);
            Prompt prompt = decode(bytes);
            if (winner != -1) return prompt;
            require((state & PROCESSOR_END) == 0, "duel ended before diagnostic completed");
            if ((state & PROCESSOR_WAITING) != 0) {
                require(prompt.kind != 0, "core waiting without a supported prompt");
                if (prompt.kind == MSG_SELECT_CHAIN && prompt.choices.empty()) {
                    set_responsei(duel, -1); // Only a verified empty candidate list.
                    continue;
                }
                return prompt;
            }
            require(prompt.kind == 0, "prompt without waiting status");
        }
        throw std::runtime_error("core processing exceeded step budget");
    }

    void counts(int player, int deck, int hand, int field) {
        require(query_field_count(duel, player, LOCATION_DECK) == deck, "unexpected deck count");
        require(query_field_count(duel, player, LOCATION_HAND) == hand, "unexpected hand count");
        require(query_field_count(duel, player, LOCATION_MZONE) == field, "unexpected monster count");
    }
};

std::string json_string(const std::string& text) {
    std::ostringstream out;
    out << '"';
    for (unsigned char c : text) {
        if (c == '"' || c == '\\') out << '\\' << c;
        else if (c < 32) out << "\\u" << std::hex << std::setw(4) << std::setfill('0') << int(c);
        else out << c;
    }
    out << '"';
    return out.str();
}

void set_fixture_callbacks() {
    set_script_reader(fixture_script);
    set_card_reader(fixture_card);
    set_message_handler(core_message);
}

void setup_fixture(intptr_t duel) {
    require(callback_error.empty(), "core creation callback: " + callback_error);
    for (uint8_t player = 0; player < 2; ++player) {
        set_player_info(duel, player, 8000, 5, 1);
        for (uint32_t i = 0; i < 40; ++i)
            new_card(duel, FIRST_FIXTURE + player * 40 + i, player, player,
                     LOCATION_DECK, 0, POS_FACEDOWN_DEFENSE);
    }
    require(callback_error.empty(), "fixture callback: " + callback_error);
    start_duel(duel, uint32_t(CURRENT_RULE) << 16);
}

uint32_t unsigned_integer(const std::string& value) {
    require(!value.empty() && value.find_first_not_of("0123456789") == std::string::npos,
            "expected unsigned decimal integer");
    const auto result = std::stoull(value);
    require(result <= std::numeric_limits<uint32_t>::max(), "integer exceeds uint32");
    return uint32_t(result);
}

void session_message(const std::string& fields) {
    std::cout << "{\"schema_version\":1,\"core_revision\":\"" OCG_REVISION
              "\",\"fixture_only\":true," << fields << "}\n" << std::flush;
}

std::string visible_monsters(Probe& probe, int player, int viewer) {
    std::ostringstream out;
    out << '[';
    constexpr uint32_t FLAGS = QUERY_CODE | QUERY_POSITION | QUERY_ATTACK | QUERY_DEFENSE;
    for (int slot = 0; slot < 5; ++slot) {
        if (slot) out << ',';
        std::vector<uint8_t> buffer(32);
        const auto length = query_card(probe.duel, player, LOCATION_MZONE, slot, FLAGS, buffer.data(), 0);
        require(length == 4 || length == 24, "unexpected field-card query layout");
        buffer.resize(length);
        Reader reader{buffer};
        require(reader.read(4) == uint32_t(length), "field query length mismatch");
        if (length == 4) { out << "null"; continue; }
        require(reader.read(4) == FLAGS, "field query flags mismatch");
        const auto code = reader.read(4), location = reader.read(4);
        const auto attack = int32_t(reader.read(4)), defense = int32_t(reader.read(4));
        const auto position = (location >> 24) & 0xff;
        const bool known = (position & POS_FACEUP) || player == viewer;
        out << "{\"slot\":" << slot << ",\"position\":" << position << ",\"known\":" << (known ? "true" : "false");
        if (known) out << ",\"code\":" << code << ",\"attack\":" << attack << ",\"defense\":" << defense;
        out << '}';
    }
    out << ']';
    return out.str();
}

std::string private_hand(Probe& probe, int player, int viewer) {
    if (player != viewer) return "[]";
    const auto count = query_field_count(probe.duel, player, LOCATION_HAND);
    require(count >= 0 && count <= 40, "practice hand exceeds admitted deck size");
    constexpr uint32_t FLAGS = QUERY_CODE | QUERY_ATTACK | QUERY_DEFENSE;
    std::ostringstream out;
    out << '[';
    for (int slot = 0; slot < count; ++slot) {
        if (slot) out << ',';
        std::vector<uint8_t> buffer(32);
        const auto length = query_card(probe.duel, player, LOCATION_HAND, slot, FLAGS, buffer.data(), 0);
        require(length == 20, "unexpected private-hand query layout");
        buffer.resize(length);
        Reader reader{buffer};
        require(reader.read(4) == uint32_t(length) && reader.read(4) == FLAGS, "private-hand query header mismatch");
        const auto code = reader.read(4);
        const auto attack = int32_t(reader.read(4)), defense = int32_t(reader.read(4));
        out << "{\"slot\":" << slot << ",\"code\":" << code << ",\"attack\":" << attack << ",\"defense\":" << defense << '}';
    }
    out << ']';
    return out.str();
}

std::string public_view(Probe& probe, int viewer) {
    std::ostringstream view;
    view << "{\"turn_player\":" << probe.turn_player << ",\"turn_number\":" << probe.turns
         << ",\"phase\":" << probe.phase << ",\"players\":[";
    for (int player = 0; player < 2; ++player) {
        if (player) view << ',';
        view << "{\"deck_count\":" << query_field_count(probe.duel, player, LOCATION_DECK)
             << ",\"hand_count\":" << query_field_count(probe.duel, player, LOCATION_HAND)
             << ",\"monster_count\":" << query_field_count(probe.duel, player, LOCATION_MZONE)
             << ",\"graveyard_count\":" << query_field_count(probe.duel, player, LOCATION_GRAVE);
        if (probe.allow_battle_effects)
            view << ",\"life_points\":" << std::max(0, probe.life_points[player])
                 << ",\"monsters\":" << visible_monsters(probe, player, viewer);
        if (probe.practice_mode) view << ",\"hand\":" << private_hand(probe, player, viewer);
        view << '}';
    }
    view << ']';
    if (probe.allow_battle_effects) view << ",\"viewer\":" << viewer;
    view << '}';
    return view.str();
}

void publish_prompt(Probe& probe, const Prompt& prompt, uint32_t id) {
    require(prompt.player == 0 || prompt.player == 1, "invalid prompt player");
    require(!prompt.choices.empty() && prompt.choices.size() <= 64, "unsupported/empty session prompt");
    std::ostringstream out;
    out << "\"type\":\"prompt\",\"player\":" << prompt.player << ",\"prompt_id\":" << id
        << ",\"mode\":\"" << (prompt.kind == MSG_SELECT_IDLECMD || prompt.kind == MSG_SELECT_BATTLECMD ? "ACTION" : "DECISION")
        << "\",\"offers\":[";
    for (size_t i = 0; i < prompt.choices.size(); ++i) {
        if (i) out << ',';
        out << "{\"kind\":" << json_string(prompt.choices[i].kind)
            << ",\"label\":" << json_string(prompt.choices[i].label) << '}';
    }
    out << "],\"view\":" << public_view(probe, prompt.player);
    session_message(out.str());
}

void set_newdoria_callbacks();
void arrange_newdoria(intptr_t duel, bool target_own_monster, bool mutual = false);

void set_practice_callbacks();
void setup_practice(intptr_t duel, const std::string& profile, uint32_t seed);

void run_session(uint32_t seed, bool real_cards = false, const std::string& profile = "") {
    const bool practice = !profile.empty();
    if (practice) set_practice_callbacks();
    else if (real_cards) set_newdoria_callbacks();
    else set_fixture_callbacks();
    DuelOwner owner(seed);
    if (practice) setup_practice(owner.handle, profile, seed);
    else {
        if (real_cards) arrange_newdoria(owner.handle, false);
        setup_fixture(owner.handle);
    }
    Probe probe{owner.handle};
    probe.allow_battle_effects = real_cards;
    probe.practice_mode = practice;
    Prompt prompt = probe.pump();
    std::array<uint32_t, 2> sequence{{0, 0}};
    uint32_t open_id = ++sequence.at(prompt.player);
    session_message(std::string("\"type\":\"ready\",\"player\":-1,\"capabilities\":[\"normal_summon\",\"choose_zone\",\"end_turn\",\"shuffle_hand\",\"discard\",\"deck_out\"") +
        (real_cards ? ",\"battle_phase\",\"attack\",\"select_monster\",\"chain_effect\",\"pass_chain\",\"main_two\",\"life_point_win\"" : "") +
        (practice ? ",\"set_monster\",\"reposition\",\"choose_position\"]" : "]") +
        (practice ? ",\"pool_sha256\":\"" + std::string(PRACTICE_POOL_SHA256) + "\",\"deck_profile\":" + json_string(profile) : ""));
    publish_prompt(probe, prompt, open_id);
    for (int command_count = 0; command_count < 4096; ++command_count) {
        // A waiting player is not a hung engine. The watchdog applies only while
        // executing a request, and EOF lets abandoned parent pipes terminate us.
        alarm(0);
        char line[256]{};
        if (!std::cin.getline(line, sizeof(line))) {
            require(std::cin.eof(), "session input exceeds line limit");
            session_message("\"type\":\"stopped\",\"player\":-1");
            return;
        }
        alarm(10);
        std::istringstream input(line);
        std::string verb, player_text, id_text, choice_text, extra;
        input >> verb;
        if (verb == "STOP") {
            require(!(input >> extra), "unexpected STOP argument");
            session_message("\"type\":\"stopped\",\"player\":-1");
            return;
        }
        require(verb == "ANSWER" && bool(input >> player_text >> id_text >> choice_text) && !(input >> extra),
                "expected ANSWER player prompt_id choice");
        const auto player = unsigned_integer(player_text);
        const auto id = unsigned_integer(id_text);
        const auto choice = unsigned_integer(choice_text);
        require(player < 2, "invalid session player");
        if (player != uint32_t(prompt.player) || id != open_id) {
            session_message("\"type\":\"rejected\",\"player\":" + std::to_string(player) +
                ",\"prompt_id\":" + std::to_string(id) + ",\"reason\":\"that is not the prompt open for you\"");
            continue;
        }
        if (choice >= prompt.choices.size()) {
            session_message("\"type\":\"rejected\",\"player\":" + std::to_string(player) +
                ",\"prompt_id\":" + std::to_string(id) + ",\"reason\":\"invalid choice index\"");
            continue;
        }
        const auto& selected = prompt.choices[choice];
        if (selected.bytes.empty()) set_responsei(owner.handle, selected.integer);
        else {
            std::array<uint8_t, SIZE_RETURN_VALUE> bytes{};
            require(selected.bytes.size() <= bytes.size(), "response too large");
            std::copy(selected.bytes.begin(), selected.bytes.end(), bytes.begin());
            set_responseb(owner.handle, bytes.data());
        }
        prompt = probe.pump();
        if (probe.winner != -1) {
            for (int viewer = 0; viewer < 2; ++viewer)
                session_message("\"type\":\"over\",\"player\":" + std::to_string(viewer) +
                    ",\"winner\":" + std::to_string(probe.winner) + ",\"reason_code\":" +
                    std::to_string(probe.win_reason) + ",\"view\":" + public_view(probe, viewer));
            return;
        }
        require(prompt.kind != MSG_RETRY, "core rejected a session-offered response");
        open_id = ++sequence.at(prompt.player);
        publish_prompt(probe, prompt, open_id);
    }
    throw std::runtime_error("session command budget exceeded");
}

void run_probe(uint32_t seed) {
    set_fixture_callbacks();
    DuelOwner owner(seed);
    const intptr_t duel = owner.handle;
    setup_fixture(duel);
    Probe probe{duel};
    Prompt opening = probe.pump();
    require(opening.kind == MSG_SELECT_IDLECMD && opening.player == 0 && opening.summonable == 5,
            "opening legal-action prompt mismatch");
    require(probe.phase == PHASE_MAIN1 && !opening.battle && opening.end && opening.shuffle,
            "opening phase flags mismatch");
    probe.counts(0, 35, 5, 0);
    probe.counts(1, 35, 5, 0);

    // Real invalid response must be rejected without changing the duel.
    set_responsei(duel, 0x7fff);
    require(probe.pump().kind == MSG_RETRY && probe.retried == 1, "invalid response was not rejected");
    probe.counts(0, 35, 5, 0);
    set_responsei(duel, 8); // Shuffle hand: exercises the core's seeded RNG.
    Prompt shuffled = probe.pump();
    require(shuffled.kind == MSG_SELECT_IDLECMD && shuffled.summonable == 5, "shuffle did not return to idle");

    set_responsei(duel, 0); // Normal Summon candidate index 0, selected from core's prompt.
    Prompt placement = probe.pump();
    require(placement.kind == MSG_SELECT_PLACE && placement.player == 0, "missing summon placement prompt");
    int slot = -1;
    for (int i = 0; i < 5; ++i)
        if (!(placement.forbidden_zones & (uint32_t(1) << i))) { slot = i; break; }
    require(slot >= 0, "no legal main monster zone");
    // set_responseb copies SIZE_RETURN_VALUE bytes, not merely the three-byte choice.
    std::array<uint8_t, SIZE_RETURN_VALUE> response{};
    response[0] = 0; response[1] = LOCATION_MZONE; response[2] = uint8_t(slot);
    set_responseb(duel, response.data());
    Prompt after_summon = probe.pump();
    require(after_summon.kind == MSG_SELECT_IDLECMD && after_summon.summonable == 0 && probe.summoned == 1,
            "normal summon did not consume the normal summon allowance");
    probe.counts(0, 35, 4, 1);
    require(after_summon.end, "cannot advance to end phase");
    set_responsei(duel, 7);
    Prompt second_turn = probe.pump();
    require(second_turn.kind == MSG_SELECT_IDLECMD && second_turn.player == 1 && second_turn.summonable == 6,
            "second-turn legal-action prompt mismatch");
    require(probe.turns == 2 && probe.phase == PHASE_MAIN1 && second_turn.battle,
            "second-turn phase flags mismatch");
    probe.counts(0, 35, 4, 1);
    probe.counts(1, 34, 6, 0);
    std::ostringstream digest;
    digest << std::hex << std::setfill('0') << std::setw(16) << probe.digest;
    std::cout << "{\"schema_version\":1,\"status\":\"ok\",\"backend\":\"fluorohydride-diagnostic\","
              << "\"core_revision\":\"" OCG_REVISION "\",\"scenario\":\"normal-summon-turn\","
              << "\"fixture_only\":true,\"seed\":" << seed
              << ",\"opening_hand_counts\":[5,5],\"opening_summon_options\":5,"
              << "\"after_summon_hand_counts\":[4,5],\"after_summon_field_counts\":[1,0],"
              << "\"after_summon_options\":0,\"second_turn_player\":1,"
              << "\"second_turn_hand_counts\":[4,6],\"second_turn_deck_counts\":[35,34],"
              << "\"invalid_response_rejected\":true,\"summons\":1,\"turns\":2,"
              << "\"message_count\":" << probe.messages
              << ",\"transcript_fnv1a64\":\"" << digest.str() << "\"}\n";
}
#include "newdoria_fixture.h"
} // namespace

int main(int argc, char** argv) {
    // Bounds wall time even if a future incompatible core hangs inside process().
    // This diagnostic intentionally only builds for Linux in its first version.
    alarm(10);
    try {
        const bool practice = argc == 6 && std::strcmp(argv[1], "--practice-session") == 0;
        const bool real_session = practice || (argc == 4 && std::strcmp(argv[1], "--newdoria-session") == 0);
        const bool session = real_session || (argc == 4 && std::strcmp(argv[1], "--session") == 0);
        const bool newdoria = (argc == 4 || argc == 5) && std::strcmp(argv[1], "--newdoria") == 0;
        require((argc == 3 || session || newdoria) && std::strcmp(argv[session || newdoria ? 2 : 1], "--seed") == 0,
                "usage: ocg_probe [--session|--newdoria-session|--newdoria] --seed UINT32 [--target-own|--mutual]");
        if (argc == 5) require(newdoria && (std::strcmp(argv[4], "--target-own") == 0 || std::strcmp(argv[4], "--mutual") == 0), "unsupported scenario option");
        const auto seed = unsigned_integer(argv[session || newdoria ? 3 : 2]);
        if (newdoria) run_newdoria(seed, argc == 5 && std::strcmp(argv[4], "--target-own") == 0, argc == 5 && std::strcmp(argv[4], "--mutual") == 0);
        else if (session) {
            if (practice) require(std::strcmp(argv[4], "--deck") == 0 &&
                (std::strcmp(argv[5], "mixed") == 0 || std::strcmp(argv[5], "dragons") == 0), "expected approved --deck mixed|dragons profile");
            run_session(seed, real_session, practice ? argv[5] : "");
        }
        else run_probe(seed);
        return 0;
    } catch (const std::exception& error) {
        std::cout << "{\"schema_version\":1,\"status\":\"error\",\"error\":" << json_string(error.what()) << "}\n";
        return 1;
    }
}
