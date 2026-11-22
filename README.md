# harkio

Local narration for videos on Apple Silicon Macs. Write a script with timestamps,
and harkio turns it into a timed audio track plus subtitles using your Mac's
System Voice (including Siri voices). Everything runs offline.

## Requirements

- An Apple Silicon Mac (M1 or newer)
- Apple's command line tools, which also provide Python 3. To check if you have
  them, run `xcode-select -p`. If it prints a folder path, you're all set. If you
  get an error instead, install them with `xcode-select --install`.
- macOS 14.2 or later for `harkio record` only

## Install

Watch the install walkthrough on YouTube (narrated with harkio):

[![How to install harkio](https://img.youtube.com/vi/qdaM55kPdp4/hqdefault.jpg)](https://youtu.be/qdaM55kPdp4)

1. **Pick your voice.** Open System Settings > Accessibility > Read & Speak and
   choose a System voice. harkio speaks with whichever voice you choose here.
   To get more voices, click the info button (ⓘ) next to System voice, then the
   download button next to a voice; the play button lets you hear it first.
   (On macOS versions before Tahoe, this setting is under Accessibility > Spoken Content.)
2. **Get the project from GitHub.** Clone this repository any way you like, then
   open its folder in Terminal.
3. **Run the installer:**

   ```bash
   ./install.command
   ```

   Or double-click `install.command` in Finder. The installer links `harkio` into
   `~/.local/bin`, adds that to your PATH, and builds the helper tools.
4. **Open a new Terminal window** so the PATH change takes effect, then check
   that it works:

   ```bash
   harkio --help
   ```

5. **Try the example:**

   ```bash
   harkio example
   cd harkio-example && harkio example.txt
   ```

   You'll get a timed narration track (`narration.wav`) and subtitles
   (`narration.srt`) in `harkio-example/example_narration/`.

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
