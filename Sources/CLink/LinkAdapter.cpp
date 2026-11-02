#include "LinkAdapter.h"
#include <ableton/Link.hpp>
#include <cmath>

using Link = ableton::Link;
static std::chrono::microseconds micros(double seconds) {
    return std::chrono::microseconds{static_cast<int64_t>(std::llround(seconds * 1000000.0))};
}
MCLLink mcl_create(double bpm) { try { return new Link(bpm); } catch (...) { return nullptr; } }
void mcl_destroy(MCLLink link) { delete static_cast<Link *>(link); }
bool mcl_enable(MCLLink link, bool enabled) {
    try { static_cast<Link *>(link)->enable(enabled); return true; } catch (...) { return false; }
}
void mcl_sync_transport(MCLLink link, bool enabled) {
    static_cast<Link *>(link)->enableStartStopSync(enabled);
}
MCLSnapshot mcl_snapshot(MCLLink handle, double seconds) {
    auto &link = *static_cast<Link *>(handle);
    auto state = link.captureAppSessionState();
    const auto t = micros(seconds);
    const double beat = state.beatAtTime(t, 4.0);
    const auto a = state.timeAtBeat(beat, 4.0);
    const auto b = state.timeAtBeat(beat + 1.0, 4.0);
    return {state.tempo(), beat, (b - a).count() / 1000000.0,
            state.timeForIsPlaying().count() / 1000000.0, link.numPeers(), state.isPlaying()};
}
void mcl_set_tempo(MCLLink handle, double bpm, double seconds) {
    auto &link = *static_cast<Link *>(handle);
    auto state = link.captureAppSessionState();
    state.setTempo(bpm, micros(seconds));
    link.commitAppSessionState(state);
}
void mcl_set_playing(MCLLink handle, bool playing, double seconds) {
    auto &link = *static_cast<Link *>(handle);
    auto state = link.captureAppSessionState();
    state.setIsPlaying(playing, micros(seconds));
    link.commitAppSessionState(state);
}
