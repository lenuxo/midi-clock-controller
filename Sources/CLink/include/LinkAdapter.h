#pragma once
#include <stdbool.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Small C ABI over official Link.hpp; snapshots are local to each call/thread.
typedef void *MCLLink;
typedef struct {
    double tempo, beat, seconds_per_beat, transport_time;
    uint64_t peers;
    bool playing;
    uint64_t transport_revision;
} MCLSnapshot;
MCLLink mcl_create(double bpm);
void mcl_destroy(MCLLink link);
bool mcl_enable(MCLLink link, bool enabled);
void mcl_sync_transport(MCLLink link, bool enabled);
MCLSnapshot mcl_snapshot(MCLLink link, double host_seconds);
void mcl_set_tempo(MCLLink link, double bpm, double host_seconds);
void mcl_set_playing(MCLLink link, bool playing, double host_seconds);
#ifdef __cplusplus
}
#endif
