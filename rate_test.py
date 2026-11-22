#!/usr/bin/env python3
"""Measure how the current System Voice responds to say -r. Plays nothing out loud."""
import os, subprocess, tempfile, wave

SENTENCES = [
    "Open the project manager, then click New Project, and give it a name.",
    "This is a short test of the narration speed.",
]
RATES = [None, 90, 120, 150, 175, 200, 250, 300]

with tempfile.TemporaryDirectory() as tmp:
    print(f"{'rate':>8}  " + "  ".join(f"sentence {i + 1}" for i in range(len(SENTENCES))))
    for r in RATES:
        row = []
        for s in SENTENCES:
            out = os.path.join(tmp, "t.wav")
            cmd = ["say", "-o", out, "--file-format=WAVE", "--data-format=LEI16@48000", s]
            if r:
                cmd[1:1] = ["-r", str(r)]
            subprocess.run(cmd, check=True)
            with wave.open(out) as w:
                row.append(w.getnframes() / w.getframerate())
        print(f"{str(r or 'default'):>8}  " + "  ".join(f"{d:9.2f}s " for d in row))
print("\nPaste this table back to Claude.")
