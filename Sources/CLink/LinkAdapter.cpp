#include "LinkAdapter.h"
#include <ableton/Link.hpp>
#include <cmath>
#include <mutex>

using Link = ableton::Link;
// The SDK callback identifies transport changes; timeForIsPlaying can also
// move during clock/tempo correction and is not a command identifier.
struct LinkHandle {
    std::mutex transportMutex;
    uint64_t transportRevision = 0;
    bool callbackPlaying = false;
    Link link;
    explicit LinkHandle(double bpm) : link(bpm) {
        link.setStartStopCallback([this](bool playing) {
            std::lock_guard<std::mutex> lock(transportMutex);
            if (playing != callbackPlaying) {
                callbackPlaying = playing;
                ++transportRevision;
            }
        });
    }
};
static std::chrono::microseconds micros(double seconds) {
    return std::chrono::microseconds{static_cast<int64_t>(std::llround(seconds * 1000000.0))};
}
MCLLink mcl_create(double bpm) { try { return new LinkHandle(bpm); } catch (...) { return nullptr; } }
void mcl_destroy(MCLLink link) { delete static_cast<LinkHandle *>(link); }
bool mcl_enable(MCLLink link, bool enabled) {
    try { static_cast<LinkHandle *>(link)->link.enable(enabled); return true; } catch (...) { return false; }
}
void mcl_sync_transport(MCLLink link, bool enabled) {
    static_cast<LinkHandle *>(link)->link.enableStartStopSync(enabled);
}
MCLSnapshot mcl_snapshot(MCLLink handle, double seconds) {
    auto &holder = *static_cast<LinkHandle *>(handle);
    auto &link = holder.link;
    // Keep the notification revision stable while capturing its state.
    std::lock_guard<std::mutex> lock(holder.transportMutex);
    auto state = link.captureAppSessionState();
    const auto t = micros(seconds);
    const double beat = state.beatAtTime(t, 4.0);
    const auto a = state.timeAtBeat(beat, 4.0);
    const auto b = state.timeAtBeat(beat + 1.0, 4.0);
    return {state.tempo(), beat, (b - a).count() / 1000000.0,
            state.timeForIsPlaying().count() / 1000000.0, link.numPeers(), state.isPlaying(),
            holder.transportRevision, holder.callbackPlaying};
}
void mcl_set_tempo(MCLLink handle, double bpm, double seconds) {
    auto &holder = *static_cast<LinkHandle *>(handle);
    auto &link = holder.link;
    auto state = link.captureAppSessionState();
    state.setTempo(bpm, micros(seconds));
    link.commitAppSessionState(state);
}
void mcl_set_playing(MCLLink handle, bool playing, double seconds) {
    auto &holder = *static_cast<LinkHandle *>(handle);
    auto &link = holder.link;
    auto state = link.captureAppSessionState();
    state.setIsPlaying(playing, micros(seconds));
    link.commitAppSessionState(state);
}
