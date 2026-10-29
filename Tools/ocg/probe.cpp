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

struct Prompt {
    int kind = 0;
    int player = -1;
    int summonable = 0;
    bool battle = false;
    bool end = false;
    bool shuffle = false;
    uint32_t forbidden_zones = 0;
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

    Prompt decode(const std::vector<uint8_t>& bytes) {
        Reader r{bytes};
        Prompt prompt;
        for (auto byte : bytes) { digest ^= byte; digest *= UINT64_C(1099511628211); }
        while (r.cursor < bytes.size()) {
            const auto kind = r.read(1);
            ++messages;
            switch (kind) {
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
                    r.skip(count * (group == 5 ? 11 : 7));
                }
                prompt.battle = r.read(1) != 0;
                prompt.end = r.read(1) != 0;
                prompt.shuffle = r.read(1) != 0;
                break;
            }
            case MSG_SELECT_PLACE:
                require(prompt.kind == 0, "multiple prompts in one packet");
                prompt.kind = kind;
                prompt.player = r.read(1);
                require(r.read(1) == 1, "unsupported multi-place selection");
                prompt.forbidden_zones = r.read(4);
                break;
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

void run_probe(uint32_t seed) {
    set_script_reader(fixture_script);
    set_card_reader(fixture_card);
    set_message_handler(core_message);
    DuelOwner owner(seed);
    const intptr_t duel = owner.handle;
    require(callback_error.empty(), "core creation callback: " + callback_error);
    for (uint8_t player = 0; player < 2; ++player) {
        set_player_info(duel, player, 8000, 5, 1);
        for (uint32_t i = 0; i < 40; ++i)
            new_card(duel, FIRST_FIXTURE + player * 40 + i, player, player,
                     LOCATION_DECK, 0, POS_FACEDOWN_DEFENSE);
    }
    require(callback_error.empty(), "fixture callback: " + callback_error);
    start_duel(duel, uint32_t(CURRENT_RULE) << 16);
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
        require(argc == 3 && std::strcmp(argv[1], "--seed") == 0, "usage: ocg_probe --seed UINT32");
        const std::string seed_text = argv[2];
        require(!seed_text.empty() && seed_text.find_first_not_of("0123456789") == std::string::npos,
                "seed must be an unsigned decimal integer");
        const auto seed = std::stoull(seed_text);
        require(seed <= std::numeric_limits<uint32_t>::max(), "seed exceeds uint32");
        run_probe(uint32_t(seed));
        return 0;
    } catch (const std::exception& error) {
        std::cout << "{\"schema_version\":1,\"status\":\"error\",\"error\":" << json_string(error.what()) << "}\n";
        return 1;
    }
}
