# notes

Local meeting transcription for macOS. Capture your microphone and system audio, transcribe both on your Mac, and save a Markdown file with timestamps and separate `me` and `them` channels.

## Motivation

Meeting transcripts should be plain files you own. Notes is a small Granola-style tool with no meeting bot, account, database, or built-in summarizer.

## Build and test

Requires macOS 14.4 or later and Swift 6.1 or later. Swift Package Manager fetches the public Flow package and its transcription dependencies.

```sh
git clone https://github.com/Naveen-Kannan/notes.git
cd notes
swift build
swift test
```

The tests cover transcript merging, timestamp formatting, retention selection, and call-app detection. They do not record audio or download speech models. The first transcription downloads roughly 450 MB of Parakeet model assets through Flow. Audio transcription runs locally after setup.

## CLI

```sh
swift run notesctl record 10
swift run notesctl record 10 mic
swift run notesctl record 10 sys
swift run notesctl transcribe /path/to/me.wav /path/to/them.wav
swift run notesctl forget --dry
swift run notesctl detect
```

`record` captures for the specified number of seconds, then transcribes. `transcribe` recovers an existing pair of recordings. `detect` watches call-app microphone use until you stop it. `forget --dry` lists expired notes without changing files; omit `--dry` to move them to Trash.

Grant Microphone and System Audio Recording permissions to the app hosting the process. Missing permission can produce silence instead of an error. System capture includes all audio playing on the Mac, not just the call. Record only conversations you have permission to record.

## Host integration

`NotesSession` exposes `start()`, `stop()`, `toggle()`, and `isLive` on the main actor. A host can call these for manual recording. `NotesCommands` exports `notes.toggle` and starts automatic call detection and daily retention. There is no standalone graphical app or recording indicator in this package; the host should display `isLive`.

Automatic mode starts after a supported call app holds the microphone for three seconds, and stops thirty seconds after it releases it. Browsers count as call apps whenever any site uses the microphone. Set `NOTES_AUTO=0` before creating `NotesCommands` for manual recording only. Merely importing the library does not start recording.

## Storage and retention

Files go to `~/Notes/meetings`, or `NOTES_DIR`. The microphone is labeled `me` and system audio `them`; this is channel separation, not speaker identification. Successful transcription removes the temporary audio unless `NOTES_KEEP_AUDIO` is set. Failed transcription keeps audio for recovery.

The host's daily retention pass moves Markdown files not modified for 21 days to Trash. Opening a note does not update its modification time. Put `keep: true` in its front matter to retain it, or use `NotesSession` directly without scheduling retention. `NOTES_FORGET_DAYS` changes the retention window.

```markdown
---
date: 2026-01-01 12:00
duration: 2m
status: raw
keep: true
---

## Transcript
[00:00] me: Let's review the example.
[00:04] them: Ready.
```

`NOTES_NO_AEC=1` disables microphone voice processing. `NOTES_KEEP_AUDIO=1` retains audio. Transcription jobs share Flow's Parakeet model and run sequentially. Silent or sub-second channels can produce an empty transcript.

## License

[MIT](LICENSE).
