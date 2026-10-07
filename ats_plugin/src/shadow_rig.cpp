// Shadow Rig - ATS telemetry plugin.
// Reads the player's truck through the official SCS Telemetry SDK and sends it to the
// Shadow Rig BeamNG mod over localhost UDP. Detects crashes and repairs.
// Channels, events, thresholds and message layout all come from sheets/ via generated/sheet_data.h.

#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include <cmath>
#include <string>

#include "scssdk_telemetry.h"
#include "eurotrucks2/scssdk_eut2.h"
#include "amtrucks/scssdk_ats.h"
#include "amtrucks/scssdk_telemetry_ats.h"
#include "common/scssdk_telemetry_common_gameplay_events.h"
#include "../generated/sheet_data.h"
#include "crash_detector.h"

namespace {

scs_log_t game_log = nullptr;
SOCKET sock = INVALID_SOCKET;
sockaddr_in target{};

sheet::State state;
shadow::Detector<sheet::Rules> detector;
bool paused = true;
bool fined_crash = false;            // set by player.fined/crash, consumed next frame
double now_s = 0.0;                  // simulation time in seconds

void log(scs_log_type_t type, const std::string &msg) {
    if (game_log) game_log(type, ("[ShadowRig] " + msg).c_str());
}

void send(const std::string &payload) {
    if (sock == INVALID_SOCKET) return;
    sendto(sock, payload.data(), static_cast<int>(payload.size()), 0,
           reinterpret_cast<const sockaddr *>(&target), sizeof target);
}

void detect() {
    const double kmh = std::fabs(state.speed) * 3.6;
    const double g = std::sqrt(state.accel.x * state.accel.x + state.accel.y * state.accel.y +
                               state.accel.z * state.accel.z) / 9.81;
    const double wear = state.wear_cabin + state.wear_chassis + state.wear_engine + state.trailer_wear_body;
    const shadow::Detection d = detector.update(now_s, kmh, g, wear, fined_crash);
    fined_crash = false;
    sheet::Computed c;
    if (d.kind == shadow::Detection::repair) {
        c.wear_total = d.wear_total;
        send(sheet::encode_repair(state, c));
        log(SCS_LOG_TYPE_message, "repair detected, resetting shadow rig");
    } else if (d.kind == shadow::Detection::crash) {
        c.impact_kmh = d.impact_kmh;
        c.peak_g = d.peak_g;
        c.damage_delta = d.damage_delta;
        c.trigger = d.trigger;
        send(sheet::encode_crash(state, c));
        log(SCS_LOG_TYPE_message, "crash at " + std::to_string(static_cast<int>(d.impact_kmh)) + " km/h sent to BeamNG");
    }
}

SCSAPI_VOID on_frame_start(const scs_event_t, const void *const info, const scs_context_t) {
    const auto *fs = static_cast<const scs_telemetry_frame_start_t *>(info);
    now_s = static_cast<double>(fs->paused_simulation_time) / 1e6;
    if (fs->flags & SCS_TELEMETRY_FRAME_START_FLAG_timer_restart) detector.restart_timer();
}

SCSAPI_VOID on_frame_end(const scs_event_t, const void *const, const scs_context_t) {
    if (!paused) detect();
    // Ticks are spaced in wall-clock time so BeamNG keeps hearing from ATS while it is paused.
    static DWORD last_ms = 0;
    const DWORD ms = GetTickCount();
    if (ms - last_ms >= static_cast<DWORD>(1000.0 / sheet::send_rate_hz)) {
        last_ms = ms;
        sheet::Computed c;
        c.paused = paused;
        send(sheet::encode_tick(state, c));
    }
}

SCSAPI_VOID on_pause(const scs_event_t event, const void *const, const scs_context_t) {
    paused = (event == SCS_TELEMETRY_EVENT_paused);
}

SCSAPI_VOID on_configuration(const scs_event_t, const void *const info, const scs_context_t) {
    const auto *cfg = static_cast<const scs_telemetry_configuration_t *>(info);
    sheet::apply_configuration(cfg->id, cfg->attributes, state);
}

SCSAPI_VOID on_gameplay(const scs_event_t, const void *const info, const scs_context_t) {
    const auto *ev = static_cast<const scs_telemetry_gameplay_event_t *>(info);
    sheet::apply_gameplay(ev->id, ev->attributes, state);
    if (std::strcmp(ev->id, SCS_TELEMETRY_GAMEPLAY_EVENT_player_fined) == 0 && state.fine_offence == "crash")
        fined_crash = true;
}

}  // namespace

SCSAPI_RESULT scs_telemetry_init(const scs_u32_t version, const scs_telemetry_init_params_t *const params) {
    if (version != SCS_TELEMETRY_VERSION_1_01) return SCS_RESULT_unsupported;
    const auto *p = static_cast<const scs_telemetry_init_params_v101_t *>(params);
    game_log = p->common.log;

    if (std::strcmp(p->common.game_id, SCS_GAME_ID_ATS) != 0)
        log(SCS_LOG_TYPE_warning, std::string("built for ATS, running in ") + p->common.game_id);

    const bool ok =
        p->register_for_event(SCS_TELEMETRY_EVENT_frame_start, on_frame_start, nullptr) == SCS_RESULT_ok &&
        p->register_for_event(SCS_TELEMETRY_EVENT_frame_end, on_frame_end, nullptr) == SCS_RESULT_ok &&
        p->register_for_event(SCS_TELEMETRY_EVENT_paused, on_pause, nullptr) == SCS_RESULT_ok &&
        p->register_for_event(SCS_TELEMETRY_EVENT_started, on_pause, nullptr) == SCS_RESULT_ok;
    if (!ok) { log(SCS_LOG_TYPE_error, "could not register core events"); return SCS_RESULT_generic_error; }
    p->register_for_event(SCS_TELEMETRY_EVENT_configuration, on_configuration, nullptr);
    p->register_for_event(SCS_TELEMETRY_EVENT_gameplay, on_gameplay, nullptr);

    state = sheet::State{};
    const int missing = sheet::register_channels(p, state);
    if (missing) log(SCS_LOG_TYPE_warning, std::to_string(missing) + " channel(s) not available in this game version");

    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) == 0) {
        sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        target.sin_family = AF_INET;
        target.sin_port = htons(static_cast<u_short>(sheet::udp_port));
        target.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    }
    if (sock == INVALID_SOCKET) log(SCS_LOG_TYPE_error, "could not open UDP socket; BeamNG will not get data");

    paused = true;
    detector.reset();
    log(SCS_LOG_TYPE_message, "ready, sending to 127.0.0.1:" + std::to_string(static_cast<int>(sheet::udp_port)));
    return SCS_RESULT_ok;
}

SCSAPI_VOID scs_telemetry_shutdown(void) {
    if (sock != INVALID_SOCKET) { closesocket(sock); sock = INVALID_SOCKET; WSACleanup(); }
    game_log = nullptr;
}

BOOL APIENTRY DllMain(HMODULE, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_DETACH && sock != INVALID_SOCKET) { closesocket(sock); sock = INVALID_SOCKET; }
    return TRUE;
}
