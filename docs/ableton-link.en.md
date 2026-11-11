# Ableton Link sync

[简体中文](ableton-link.md) · English

The app bridges a shared Link beat timeline to USB MIDI Clock at 24 pulses per quarter note. Following MIDI devices use that timeline; independent devices keep their own tempo and transport.

Each device card labels **MIDI Clock** as the actual output protocol. **Beat source: Link** means Link-to-MIDI bridging; **Local master** and **Independent** use local clocks. The **Ableton Link** group summarizes other participants and transport settings. Shared tempo appears in the master display; the original Link tempo is shown separately only when MIDI uses a tempo ratio. Link does not expose names or individual connection, sync, or playback status. **MIDI Devices** lists each local MIDI output separately. Labels on disconnected cards describe the configured route, not active clock reception.

## Use

1. Stop the master, then click **Join** in the Ableton Link card. Independent devices can keep playing. Link is off and transport defaults to **Local** at each launch; joining never starts MIDI playback automatically.
2. Enable Link in another app on this computer or on the same local network. The count shows other Link participants, not local MIDI outputs. With no other peers, playback still works at the current tempo.
3. Joining an existing session adopts its tempo. Master BPM edits, including the arrow keys and hold buttons, change the shared session tempo. Independent-device edits stay local. While you edit BPM, Link can still change the session tempo. Press Esc to discard your draft and display the current tempo. Confirming an unchanged field also preserves the latest session tempo.
4. In the card, **MIDI launch** independently chooses **Next beat** or **Every 4 beats**; stop the master before changing it. Four beats is a launch boundary, not a promise that every participant uses the same time signature.
5. Start, Continue, and Restart wait for that boundary; **Cancel Start** cancels the pending launch. Stop does not wait for a beat boundary. Continue sends MIDI Continue and preserves each device's own stopped position; it does not align song positions.
6. Set **Transport** to **Linked** on both sides to share new transport commands. **Local** (the default) neither sends nor follows remote Start/Stop. Enabling sync does not consume an earlier Play command. A remote Start continues eligible MIDI devices and starts the others from the beginning; independent devices are excluded.
7. Master Stop sends Stop to Link when sync is enabled. **Stop All** instead stops all local MIDI, cancels pending launches, and turns off Start/Stop sync; it does not stop other Link peers. Tempo and beat sharing remain active.
8. Clicking **Leave** preserves the current tempo. The last peer leaving does not stop local playback. Reconnected MIDI devices need a manual start; devices still disconnected after 30 seconds leave the list.

## Tempo range and troubleshooting

Outside 20–300 BPM, MIDI uses a power-of-two tempo ratio rather than clipping. For example, **Link 999.0 BPM · MIDI ÷4** means MIDI runs at 249.75 BPM (shown as 249.8 on the display). Edits retain that ratio where possible; edits outside its range return to 1:1 so the MIDI tempo matches the requested value.

If no peers appear, check Link on both sides, local network access, firewalls, and network client isolation. macOS may ask for local network permission. A zero peer count alone does not identify the cause.

Choose one sync route per hardware device to avoid duplicate clocks. Abrupt phase jumps or serious scheduling stalls stop the affected MIDI output with an error instead of sending stale pulses. USB, hardware, and audio latency still need physical measurement; software beat alignment does not guarantee aligned sound.

## Build, tests, and licenses

The pinned official Link 4.1.1 SDK and Asio sources are included in the repository; builds do not download dependencies. Their licenses ship in the app's `ThirdPartyLicenses` folder, accessible from About alongside the DSEG font license. Link is GPLv2+ / proprietary dual licensed. This project uses the GPL-2.0-or-later route and includes corresponding source archives with releases; see LICENSE and COPYING.md at the repository root.

Developer details and verification commands are in the [Chinese implementation and test guide](ableton-link.md#实现与依赖). Real network tests are opt-in and belong on an isolated test network; MIDI integration tests use private virtual destinations only.

For hardware acceptance, change tempo in both directions, test quantized Start/Continue/cancellation with Start/Stop sync on, and keep an independent MIDI device at a different tempo. Record hardware clicks against a Link reference to assess offset and long-term drift, then test peer loss, MIDI disconnection/reconnection, and Stop All.

The app tracks each change reported by the official SDK callback and its final playback state, so a Stop followed by Play between polls reaches the local transport in order. A remapped transport timestamp by itself never triggers playback. Local commands retain their intended state until observation, so a concurrent remote reversal is not swallowed as a local acknowledgement. Timing correction and delayed local callbacks do not restart stopped outputs. Tests cover these cases and rapid transport changes; real network tests skip without sending commands when unrelated peers are present.

For Ableton Move, select **Setup → Link → Start/Stop**, rather than **Tempo**, as described in the [Move manual](https://www.ableton.com/en/move/manual/#using-ableton-link-on-move). Join in this app and select **Linked** transport. With both stopped and a nonzero peer count, start and stop five times from Move, then repeat from the app. Test **Next beat** first, then **Every 4 beats** waiting/cancellation. MIDI outputs are optional for testing Link transport alone. This is a hardware acceptance procedure, not a claim that Move has been tested.
