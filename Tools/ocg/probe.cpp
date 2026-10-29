// Optional Fluorohydride-core diagnostic, not the game's authoritative backend.
// Protocol source: pinned common.h, playerop.cpp and operations.cpp (see lock.json).
// Only synthetic level-4 Normal Monsters are permitted; no effect Lua is loaded.
#include "ocgapi.h"
#include "card_data.h"
#include <array>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <limits>
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
            case MSG_MOVE: r.skip(16); break;
            case MSG_SUMMONING: r.skip(8); break;
            case MSG_SUMMONED: ++summoned; break;
            case MSG_SELECT_IDLECMD: {
                require(prompt.kind == 0, "multiple prompts in one packet");
                prompt.kind = kind;
                prompt.player = r.read(1);
                for (int group = 0; group < 6; ++group) {
                    auto count = r.read(1);
                    if (group == 0) prompt.summonable = count;
                    for (uint32_t index = 0; index < count; ++index) {
                        r.skip(4); // Core card code stays inside the trusted process.
                        const auto controller = r.read(1);
                        const auto location = r.read(1);
                        const auto sequence = r.read(1);
                        if (group == 0) {
                            require(controller == uint32_t(prompt.player) && location == LOCATION_HAND,
                                    "unsupported normal summon candidate location");
                            prompt.choices.push_back({"normal_summon", "Normal Summon from hand slot " +
                                std::to_string(sequence + 1), int32_t(index << 16), {}});
                        }
                        if (group == 5) r.skip(4);
                    }
                }
                prompt.battle = r.read(1) != 0;
                prompt.end = r.read(1) != 0;
                prompt.shuffle = r.read(1) != 0;
                if (prompt.end) prompt.choices.push_back({"end_turn", "End turn", 7, {}});
                if (prompt.shuffle) prompt.choices.push_back({"shuffle_hand", "Shuffle own hand", 8, {}});
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
                require(cancelable == 0 && minimum == 1 && maximum == 1,
                        "reference session only supports single-card hand-limit discards");
                for (uint32_t index = 0; index < count; ++index) {
                    r.skip(4);
                    const auto location = r.read(4);
                    require((location & 0xff) == uint32_t(prompt.player) && ((location >> 8) & 0xff) == LOCATION_HAND,
                            "reference session only supports own-hand discard candidates");
                    prompt.choices.push_back({"discard", "Discard hand slot " + std::to_string(((location >> 16) & 0xff) + 1),
                        0, {1, uint8_t(index)}});
                }
                break;
            }
            case MSG_SELECT_CHAIN: {
                require(prompt.kind == 0, "multiple prompts in one packet");
                prompt.kind = kind;
                prompt.player = r.read(1);
                require(r.read(1) == 0, "effect chains are outside this diagnostic");
                r.skip(9); // special count + two timing masks (no chain candidates)
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
                if (prompt.kind == MSG_SELECT_CHAIN) {
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

std::string public_view(Probe& probe) {
    std::ostringstream view;
    view << "{\"turn_player\":" << probe.turn_player << ",\"turn_number\":" << probe.turns
         << ",\"phase\":" << probe.phase << ",\"players\":[";
    for (int player = 0; player < 2; ++player) {
        if (player) view << ',';
        view << "{\"deck_count\":" << query_field_count(probe.duel, player, LOCATION_DECK)
             << ",\"hand_count\":" << query_field_count(probe.duel, player, LOCATION_HAND)
             << ",\"monster_count\":" << query_field_count(probe.duel, player, LOCATION_MZONE)
             << ",\"graveyard_count\":" << query_field_count(probe.duel, player, LOCATION_GRAVE) << '}';
    }
    view << "]}";
    return view.str();
}

void publish_prompt(Probe& probe, const Prompt& prompt, uint32_t id) {
    require(prompt.player == 0 || prompt.player == 1, "invalid prompt player");
    require(!prompt.choices.empty() && prompt.choices.size() <= 64, "unsupported/empty session prompt");
    std::ostringstream out;
    out << "\"type\":\"prompt\",\"player\":" << prompt.player << ",\"prompt_id\":" << id
        << ",\"mode\":\"" << (prompt.kind == MSG_SELECT_IDLECMD ? "ACTION" : "DECISION")
        << "\",\"offers\":[";
    for (size_t i = 0; i < prompt.choices.size(); ++i) {
        if (i) out << ',';
        out << "{\"kind\":" << json_string(prompt.choices[i].kind)
            << ",\"label\":" << json_string(prompt.choices[i].label) << '}';
    }
    out << "],\"view\":" << public_view(probe);
    session_message(out.str());
}

void run_session(uint32_t seed) {
    set_fixture_callbacks();
    DuelOwner owner(seed);
    setup_fixture(owner.handle);
    Probe probe{owner.handle};
    Prompt prompt = probe.pump();
    std::array<uint32_t, 2> sequence{{0, 0}};
    uint32_t open_id = ++sequence.at(prompt.player);
    session_message("\"type\":\"ready\",\"player\":-1,\"capabilities\":[\"normal_summon\",\"choose_zone\",\"end_turn\",\"shuffle_hand\",\"discard\",\"deck_out\"]");
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
                    std::to_string(probe.win_reason) + ",\"view\":" + public_view(probe));
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
} // namespace

int main(int argc, char** argv) {
    // Bounds wall time even if a future incompatible core hangs inside process().
    // This diagnostic intentionally only builds for Linux in its first version.
    alarm(10);
    try {
        const bool session = argc == 4 && std::strcmp(argv[1], "--session") == 0;
        require((argc == 3 || session) && std::strcmp(argv[session ? 2 : 1], "--seed") == 0,
                "usage: ocg_probe [--session] --seed UINT32");
        const auto seed = unsigned_integer(argv[session ? 3 : 2]);
        if (session) run_session(seed);
        else run_probe(seed);
        return 0;
    } catch (const std::exception& error) {
        std::cout << "{\"schema_version\":1,\"status\":\"error\",\"error\":" << json_string(error.what()) << "}\n";
        return 1;
    }
}
