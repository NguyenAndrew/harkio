# harkio

Local narration for videos on Apple Silicon Macs. Write a script with timestamps,
and harkio turns it into a timed audio track plus subtitles using your Mac's
System Voice (including Siri voices). Everything runs offline.

## Requirements

- macOS on an Apple Silicon Mac
- Python 3 and Apple's command line tools (`xcode-select --install`, which also provides Python 3)
- macOS 14.2 or later for `harkio record` only

## Install

```bash
git clone https://github.com/NguyenAndrew/harkio.git
cd harkio
./install.command
```

Or double-click `install.command` in Finder. The installer links `harkio` into
`~/.local/bin`, adds that to your PATH, and builds the helper tools. Open a new
Terminal window afterwards so the PATH change takes effect.

Set your voice in System Settings > Accessibility > Spoken Content > System Voice.

## Use

```bash
harkio myvideo.txt                 # -> myvideo_narration/narration.wav, narration.srt, clips/
harkio myvideo.txt --rate 160      # slower overall
harkio myvideo.txt -o ~/Desktop/vo # choose the output folder
harkio example                     # create harkio-example/ showing every feature
harkio new myvideo.txt             # start a new script from a template
harkio voices                      # voices you can pick with --voice
harkio --help
```

Put `narration.wav` at the very start of your editor's timeline; import
`narration.srt` as captions.

## Script syntax

```
# Comments are ignored.
[0:00] Welcome back! Today we're building a farm.

[0:12] First, open Godot. [pause 1s] Then make a new project.

No timestamp: this follows the previous paragraph after a short gap.

[0:30] [rate 150] This part is slower. [rate default] Back to normal.
```

- `[m:ss]` / `[h:mm:ss]` / `[1:05.5]` at the start of a paragraph: when it starts.
  If the paragraph before runs late, it starts late and you get a warning.
- `[pause 1s]`, `[pause 400ms]`: silence.
- `[rate 150]`: speed from that point on (words per minute; 175 is normal). `[rate default]` resets.

## Pronunciations

`pronunciations.txt` next to the script, or `~/.config/harkio/pronunciations.txt` for all scripts:

```
Godot = Gaw-doh
SQL = sequel
```

Fixes change the audio only; subtitles keep your spelling.

## Other commands

- `harkio rate-test`: how your voice responds to speed settings.
- `harkio record out.wav [--wait] [--stop-after 2] [--mute] [--process NAME]`: record
  whatever your Mac is playing (macOS 14.2+; needs System Audio Recording permission).
- `harkio setup`: rebuild the helper tools.

## Files

| File | What it is |
|---|---|
| `harkio` | the command |
| `narrate.py` | narration engine |
| `tempo.swift` / `tempo` | pitch-preserving speed changes |
| `harkio-record.swift` / `harkio-record` | system audio recorder |
| `rate_test.py` | speed test |
| `examples/` | sample scripts |

## License

[MIT](LICENSE) © 2026 NguyenAndrew
