# AVAudioEngine + SFSpeechRecognizer Crash Documentation

## Crash 1: `inputNode != nullptr || outputNode != nullptr`
**Source:** Apple Developer Forums (thread 44833), AVAEInternal.h

**Cause:** AVAudioEngine requires at least one node (input or output) connected before calling `.start()`. An engine with no connected nodes cannot function.

**Solutions:**
- Access `mainMixerNode` or `inputNode` first to force node creation before `.start()`
- **Critical:** `prepare()` can deallocate nodes—re-access `inputNode` after `prepare()` before calling `.start()`

## Crash 2: `CreateRecordingTap: (nullptr == Tap())`
**Source:** Stack Overflow 43711492, 41805381

**Cause:** Installing a tap when one already exists, or engine in corrupted state from previous use.

**Solutions:**
- Always `removeTap(onBus:)` before reinstalling
- **Most reliable:** Create a **new AVAudioEngine instance** for each recording session instead of reusing
- Order: stop engine → remove tap → install new tap → prepare → start
- Before removeTap: some suggest `inputNode.reset()` then `removeTap(onBus: 0)`

## Crash 3: `IsFormatSampleRateAndChannelCountValid(format)`
**Source:** Stack Overflow 41805381 (23 upvotes)

**Cause:** Invalid format—`sampleRate == 0` or `channelCount == 0`. Can happen when:
- AVAudioSession not configured before accessing inputNode
- Microphone in use elsewhere (phone call, etc.)
- Input node constructed before AVAudioSession setup

**Solutions:**
- Use `inputFormat(forBus: 0)` not `outputFormat(forBus: 0)` for microphone input
- **Set up AVAudioSession BEFORE accessing inputNode**
- Validate format: check `sampleRate > 0` and `channelCount > 0` before installTap
- Fallback: `AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)`
- Check `inputNode.inputFormat(forBus: 0).channelCount == 0` → "Not enough inputs"
- Call `audioEngine.reset()` or create new engine

## Key Order of Operations (from multiple sources)
1. **AVAudioSession** — set category and activate FIRST
2. **Access inputNode** — only after session is active (format is undefined otherwise)
3. **Validate format** — sampleRate > 0, channelCount > 0
4. **installTap** — use inputFormat(forBus: 0) for mic
5. **prepare()**
6. **Re-access inputNode** if prepare() may have deallocated
7. **start()**

## Creating New AVAudioEngine Per Session
**Source:** Stack Overflow 45598226, 52264151, Apple Forums 658078

Creating a **new AVAudioEngine instance** for each recording session is more reliable than resetting. The engine can get into corrupted state; discarding and recreating avoids tap/format/graph issues.

## Haptics and Sounds During Recording
**Fix:** By default, iOS disables haptics and system sounds during audio recording to prevent them from being captured. To allow haptic feedback and playback (e.g. AVAudioPlayer, system sounds) while the mic is active:

```swift
try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [...])
try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)  // Allow haptics + sounds while mic is active
try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
```

Call `setAllowHapticsAndSystemSoundsDuringRecording(true)` after `setCategory` and before `setActive`.

## Apple SpokenWord Sample
- Uses `outputFormat(forBus: 0)` (differs from SO recommendation of inputFormat)
- Session: `.record`, `.measurement`, `.duckOthers`
- Order: setCategory → setActive → get inputNode → installTap → prepare → start
