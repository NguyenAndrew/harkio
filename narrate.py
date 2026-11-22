#!/usr/bin/env python3
"""
narrate.py - turn a narration script into video-ready audio with your Mac's System Voice.

Outputs (in the output folder, default: next to the script, named <script>_narration/):
  narration.wav   one track, each paragraph placed at its [timestamp], ready for the timeline
  narration.srt   subtitles timed sentence by sentence
  clips/          one WAV per paragraph, if you'd rather place them by hand

SCRIPT FORMAT
  # Lines starting with # are notes and are ignored.

  [0:00] Welcome back! Today we're building a farm.

  [0:12] First, open Godot. [pause 1s] Then make a new project.

  A paragraph without a timestamp follows the previous one after a short gap.

  - Paragraphs are separated by blank lines.
  - Timestamps: [m:ss], [h:mm:ss], decimals allowed ([1:05.5]).
  - Pauses: [pause 1s], [pause 1.5s], [pause 400ms]
  - Speed: [rate 150] changes speed from that point on; [rate default] goes back.
    Rates are words per minute where 175 is normal, so 150 = 86% speed and 210 = 120%.
  - If a paragraph runs past the next timestamp, the next one is pushed later and you get a warning.

PRONUNCIATIONS
  pronunciations.txt next to the script, or in ~/.config/harkio/, or next to this tool:
      Godot = Gaw-doh
      SQL = sequel
  Fixes apply to the audio only; subtitles keep your original spelling.

USAGE
  harkio script.txt [-o folder] [--rate 175] [--gap 0.6] [--sentence-gap 0.25] [--voice NAME]
  (--voice is optional; by default the System Voice is used, which is how Siri voices work.)
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile
import wave
from concurrent.futures import ThreadPoolExecutor

SAMPLE_RATE = 48000          # matches standard video audio
SAMPLE_WIDTH = 2             # 16-bit
CHANNELS = 1

TIMESTAMP_RE = re.compile(r"^\s*\[(\d+(?::\d+){0,2}(?:\.\d+)?)\]\s*")
PAUSE_RE = re.compile(r"\[pause\s+(\d+(?:\.\d+)?)\s*(ms|s)?\s*\]", re.IGNORECASE)
MARKER_RE = re.compile(r"\[(pause|rate)\s+([^\]]+?)\s*\]", re.IGNORECASE)
SENTENCE_RE = re.compile(r"(?<=[.!?…])[\"')\]]*\s+")


def die(msg):
    print("narrate: " + msg, file=sys.stderr)
    sys.exit(1)


def parse_timestamp(ts):
    parts = [float(p) for p in ts.split(":")]
    seconds = 0.0
    for p in parts:
        seconds = seconds * 60 + p
    return seconds


def fmt_time(seconds):
    m, s = divmod(seconds, 60)
    h, m = divmod(int(m), 60)
    return f"{h}:{m:02d}:{s:04.1f}" if h else f"{m}:{s:04.1f}"


def srt_time(seconds):
    ms = int(round(seconds * 1000))
    h, ms = divmod(ms, 3600000)
    m, ms = divmod(ms, 60000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def wrap_subtitle(text, width=42):
    """Wrap to at most two balanced lines when it's long."""
    if len(text) <= width:
        return text
    words = text.split()
    best, best_diff = None, None
    for i in range(1, len(words)):
        a, b = " ".join(words[:i]), " ".join(words[i:])
        diff = abs(len(a) - len(b))
        if best_diff is None or diff < best_diff:
            best, best_diff = (a, b), diff
    return "\n".join(best) if best else text


def load_pronunciations(script_path, explicit):
    candidates = [explicit] if explicit else [
        os.path.join(os.path.dirname(os.path.abspath(script_path)), "pronunciations.txt"),
        os.path.expanduser("~/.config/harkio/pronunciations.txt"),
        os.path.join(os.path.dirname(os.path.realpath(__file__)), "pronunciations.txt"),
    ]
    for path in candidates:
        if path and os.path.isfile(path):
            rules = []
            with open(path, encoding="utf-8") as f:
                for n, line in enumerate(f, 1):
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    if "=" not in line:
                        print(f"narrate: {path}:{n}: skipped (needs 'word = how to say it')", file=sys.stderr)
                        continue
                    word, say_as = (x.strip() for x in line.split("=", 1))
                    if word:
                        pattern = re.compile(r"(?<!\w)" + re.escape(word) + r"(?!\w)", re.IGNORECASE)
                        rules.append((pattern, say_as))
            # Longest words first so "Godot Engine" wins over "Godot".
            rules.sort(key=lambda r: -len(r[0].pattern))
            return rules, path
        if explicit:
            die(f"can't find pronunciation file {explicit}")
    return [], None


def apply_pronunciations(text, rules):
    for pattern, say_as in rules:
        text = pattern.sub(say_as, text)
    return text


def parse_script(path):
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    lines = [l for l in raw.splitlines() if not l.lstrip().startswith("#")]
    blocks, current = [], []
    for line in lines + [""]:
        if line.strip():
            current.append(line.strip())
        elif current:
            blocks.append(" ".join(current))
            current = []

    parsed = []
    for i, text in enumerate(blocks, 1):
        start = None
        m = TIMESTAMP_RE.match(text)
        if m:
            start = parse_timestamp(m.group(1))
            text = text[m.end():]
        # Split into ("say", sentence), ("pause", seconds) and ("rate", wpm or None) items.
        items, pos = [], 0
        for mm in MARKER_RE.finditer(text):
            items += [("say", s) for s in split_sentences(text[pos:mm.start()])]
            kind, arg = mm.group(1).lower(), mm.group(2).strip().lower()
            if kind == "pause":
                pm = re.fullmatch(r"(\d+(?:\.\d+)?)\s*(ms|s)?", arg)
                if not pm:
                    die(f"paragraph {i}: can't read [{mm.group(1)} {mm.group(2)}] - use [pause 1s] or [pause 400ms]")
                amount = float(pm.group(1))
                items.append(("pause", amount / 1000 if pm.group(2) == "ms" else amount))
            else:
                if arg in ("default", "normal", "reset"):
                    items.append(("rate", None))
                elif arg.isdigit():
                    items.append(("rate", int(arg)))
                else:
                    die(f"paragraph {i}: can't read [{mm.group(1)} {mm.group(2)}] - use [rate 160] or [rate default]")
            pos = mm.end()
        items += [("say", s) for s in split_sentences(text[pos:])]
        if not any(kind == "say" for kind, _ in items):
            print(f"narrate: paragraph {i} has no text to speak; skipping it", file=sys.stderr)
            continue
        parsed.append({"index": i, "start": start, "items": items})
    return parsed


def split_sentences(text):
    text = " ".join(text.split())
    return [s.strip() for s in SENTENCE_RE.split(text) if s.strip()]


DEFAULT_WPM = 175            # say's normal speaking rate
TEMPO = os.path.join(os.path.dirname(os.path.realpath(__file__)), "tempo")
_warned_no_tempo = False
TEMPO_OK = False


def tempo_works():
    try:
        r = subprocess.run([TEMPO], capture_output=True, text=True)
        return "usage" in (r.stderr + r.stdout)
    except OSError:        # missing, or built for a different kind of Mac
        return False


def ensure_tempo():
    """Make sure the speed tool runs on this Mac, building it from tempo.swift if needed."""
    if tempo_works():
        return True
    source = TEMPO + ".swift"
    if not os.path.isfile(source):
        return False
    print("Building the speed tool for this Mac (one time)...")
    try:
        subprocess.run(["swiftc", "-O", source, "-o", TEMPO], check=True, capture_output=True, text=True)
    except (OSError, subprocess.CalledProcessError) as e:
        detail = getattr(e, "stderr", "") or str(e)
        print("narrate: couldn't build the speed tool (are Apple's command line tools installed? "
              "run: xcode-select --install)\n" + detail.strip()[:500], file=sys.stderr)
        return False
    return tempo_works()


def render(text, tmpdir, rate, voice):
    """Render text with `say` and return raw 16-bit mono PCM at SAMPLE_RATE.

    Speed changes are done by time-stretching the normal-speed recording with the
    `tempo` tool (pitch stays the same), because Siri voices barely follow say -r.
    """
    global _warned_no_tempo
    tmpdir = tempfile.mkdtemp(dir=tmpdir)
    txt = os.path.join(tmpdir, "line.txt")
    out = os.path.join(tmpdir, "line.wav")
    with open(txt, "w", encoding="utf-8") as f:
        f.write(text)
    cmd = ["say", "-f", txt, "-o", out, "--file-format=WAVE", f"--data-format=LEI16@{SAMPLE_RATE}"]
    if voice:
        cmd += ["-v", voice]
    stretch = rate and rate != DEFAULT_WPM
    if stretch and not TEMPO_OK:
        if not _warned_no_tempo:
            print("narrate: the speed tool isn't available, so speed changes use say -r, "
                  "which Siri voices mostly ignore.", file=sys.stderr)
            _warned_no_tempo = True
        cmd += ["-r", str(rate)]
        stretch = False
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True)
        if stretch:
            stretched = os.path.join(tmpdir, "line_tempo.wav")
            subprocess.run([TEMPO, out, stretched, f"{rate / DEFAULT_WPM:.4f}"],
                           check=True, capture_output=True, text=True)
            out = stretched
    except FileNotFoundError:
        die("the `say` command wasn't found - this tool needs macOS")
    except subprocess.CalledProcessError as e:
        die(f"{e.cmd[0]} failed on: {text!r}\n{e.stderr.strip()}")
    with wave.open(out, "rb") as w:
        if (w.getnchannels(), w.getsampwidth(), w.getframerate()) != (CHANNELS, SAMPLE_WIDTH, SAMPLE_RATE):
            die(f"unexpected audio format: {w.getparams()}")
        return trim_silence(w.readframes(w.getnframes()))


def trim_silence(pcm, threshold=200, keep=0.03):
    """Trim near-silent padding from both ends so timestamps land on the first word."""
    n = len(pcm) // SAMPLE_WIDTH
    if n == 0:
        return pcm
    samples = memoryview(pcm).cast("h")
    first = next((i for i in range(n) if abs(samples[i]) > threshold), None)
    if first is None:
        return b""
    last = next(i for i in range(n - 1, -1, -1) if abs(samples[i]) > threshold)
    pad = int(keep * SAMPLE_RATE)
    first, last = max(0, first - pad), min(n - 1, last + pad)
    return bytes(pcm[first * SAMPLE_WIDTH:(last + 1) * SAMPLE_WIDTH])


def silence(seconds):
    return b"\x00" * (int(round(seconds * SAMPLE_RATE)) * SAMPLE_WIDTH)


def write_wav(path, pcm):
    with wave.open(path, "wb") as w:
        w.setnchannels(CHANNELS)
        w.setsampwidth(SAMPLE_WIDTH)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm)


def main(argv=None, prog=None):
    ap = argparse.ArgumentParser(prog=prog, description="Render a narration script to timed WAV + SRT.")
    ap.add_argument("script")
    ap.add_argument("-o", "--out", help="output folder (default: <script>_narration next to the script)")
    ap.add_argument("--rate", type=int, help="speaking rate in words per minute (default: voice's own)")
    ap.add_argument("--voice", help="voice name for say -v (default: your System Voice)")
    ap.add_argument("--gap", type=float, default=0.6, help="seconds between untimed paragraphs (default 0.6)")
    ap.add_argument("--sentence-gap", type=float, default=0.25, help="seconds between sentences (default 0.25)")
    ap.add_argument("--jobs", type=int, help="sentences to render at once (default: up to 8)")
    ap.add_argument("--pron", help="pronunciation file (default: pronunciations.txt next to the script or tool)")
    args = ap.parse_args(argv)

    if not os.path.isfile(args.script):
        die(f"can't find {args.script}")
    out_dir = args.out or os.path.splitext(os.path.abspath(args.script))[0] + "_narration"
    clips_dir = os.path.join(out_dir, "clips")
    os.makedirs(clips_dir, exist_ok=True)
    for old in os.listdir(clips_dir):
        if re.fullmatch(r"clip_\d+\.wav", old):
            os.remove(os.path.join(clips_dir, old))

    rules, pron_path = load_pronunciations(args.script, args.pron)
    if pron_path:
        print(f"Using {len(rules)} pronunciation fix(es) from {pron_path}")
    blocks = parse_script(args.script)
    if not blocks:
        die("the script has nothing to say")

    track = bytearray()
    subtitles = []
    warnings = []
    cursor = 0.0            # seconds: end of audio so far

    # Work out each sentence's speed, then render them all in parallel.
    jobs, rate = [], args.rate
    for block in blocks:
        for kind, value in block["items"]:
            if kind == "rate":
                rate = value if value is not None else args.rate
            elif kind == "say":
                jobs.append((value, rate))
    global TEMPO_OK
    if any(r and r != DEFAULT_WPM for _, r in jobs):
        TEMPO_OK = ensure_tempo()
    workers = args.jobs or min(8, os.cpu_count() or 4)
    print(f"Rendering {len(jobs)} sentence(s) using {workers} at a time...")
    with tempfile.TemporaryDirectory() as tmp:
        with ThreadPoolExecutor(max_workers=workers) as pool:
            rendered = list(pool.map(
                lambda job: render(apply_pronunciations(job[0], rules), tmp, job[1], args.voice), jobs))
    rendered.reverse()          # pop() from the end = original order

    if True:
        for b_num, block in enumerate(blocks, 1):
            # Where does this paragraph start?
            if block["start"] is not None:
                start = block["start"]
                if start < cursor - 0.01:
                    warnings.append(
                        f"Paragraph {block['index']} is marked [{fmt_time(start)}] but the one before it "
                        f"runs until {fmt_time(cursor)}; it starts {cursor - start:.1f}s late.")
                    start = cursor
            else:
                start = cursor + (args.gap if b_num > 1 else 0)
            track += silence(start - len(track) / SAMPLE_WIDTH / SAMPLE_RATE)

            clip = bytearray()
            items = block["items"]
            for k, (kind, value) in enumerate(items):
                if kind == "pause":
                    clip += silence(value)
                    continue
                if kind == "rate":
                    continue
                pcm = rendered.pop()
                t0 = start + len(clip) / SAMPLE_WIDTH / SAMPLE_RATE
                clip += pcm
                t1 = start + len(clip) / SAMPLE_WIDTH / SAMPLE_RATE
                subtitles.append((t0, t1, value))
                if next((k2 for k2, _ in items[k + 1:] if k2 != "rate"), None) == "say":
                    clip += silence(args.sentence_gap)

            track += clip
            cursor = len(track) / SAMPLE_WIDTH / SAMPLE_RATE
            clip_path = os.path.join(clips_dir, f"clip_{b_num:03d}.wav")
            write_wav(clip_path, bytes(clip))
            print(f"[{b_num}/{len(blocks)}] {fmt_time(start)}-{fmt_time(cursor)}  {clip_path}")

    write_wav(os.path.join(out_dir, "narration.wav"), bytes(track))
    with open(os.path.join(out_dir, "narration.srt"), "w", encoding="utf-8") as f:
        for n, (t0, t1, text) in enumerate(subtitles, 1):
            f.write(f"{n}\n{srt_time(t0)} --> {srt_time(t1)}\n{wrap_subtitle(text)}\n\n")

    print(f"\nDone - {fmt_time(cursor)} of narration in {out_dir}/")
    print("  narration.wav  full timed track (drop it at the very start of your timeline)")
    print("  narration.srt  subtitles")
    print("  clips/         one file per paragraph")
    for w in warnings:
        print("Warning: " + w)


if __name__ == "__main__":
    main()
