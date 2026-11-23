#!/usr/bin/env python3
"""Narrate the demo video: TTS per scene, re-render with scene holds, mux.

    python3 scripts/narrate_demo.py <rec-dir> <voice.onnx> <out.mp4> [workdir]

<rec-dir> is the captured out/rec (CI artifact of record-demo.sh).
<voice.onnx> is a Piper voice (we use en_US-lessac-high from
huggingface.co/rhasspy/piper-voices); needs `pip install piper-tts`.

Steps: speak each `[key] text` segment of scripts/demo-narration.txt into
its own clip, give every scene a minimum length of LEAD + clip + TAIL,
render the video with scripts/render_demo.py, place each clip LEAD seconds
after its scene starts, loudness-normalize to -16 LUFS, write an .srt next
to the output, and mux video + AAC audio + a soft mov_text subtitle track.
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LEAD, TAIL = 0.3, 0.6

# Spoken forms only; the script and subtitles keep the written forms.
SAY = [(r"\bFeCheck\b", "Fee Check"), (r"\b[Ff]e\b", "Fee"), (r"\bEVM\b", "E V M"),
       (r"\bERC-20\b", "E R C twenty")]


def segments(path):
    segs = []
    for ln in open(path):
        m = re.match(r"\[(\w+)\]\s+(.*\S)", ln)
        if m:
            segs.append((m.group(1), m.group(2)))
    return segs


def spoken(text):
    for pat, rep in SAY:
        text = re.sub(pat, rep, text)
    return text


def dur(path):
    return float(subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path]))


def ts(t):
    ms = int(round(t * 1000))
    return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d},{ms % 1000:03d}"


def main(rec, voice, out, work):
    os.makedirs(work, exist_ok=True)
    segs = segments(os.path.join(HERE, "demo-narration.txt"))
    clips = {}
    for key, text in segs:
        wav = os.path.join(work, f"{key}.wav")
        subprocess.run([sys.executable, "-m", "piper", "-m", voice, "-f", wav,
                        "--sentence-silence", "0.25"], input=spoken(text).encode(), check=True,
                       stderr=subprocess.DEVNULL)
        clips[key] = dur(wav)
    mins = {k: round(LEAD + d + TAIL, 3) for k, d in clips.items()}
    json.dump({"lead": LEAD, "tail": TAIL, "clips": clips, "min_scene": mins},
              open(os.path.join(work, "narration.json"), "w"), indent=1)
    json.dump(mins, open(os.path.join(work, "min.json"), "w"))

    silent = os.path.join(work, "video.mp4")
    subprocess.run([sys.executable, os.path.join(HERE, "render_demo.py"), silent, rec,
                    os.path.join(work, "min.json")], check=True)
    sc = json.load(open(os.path.join(rec, "scenes.json")))
    starts = {s["key"]: s["start"] for s in sc["scenes"]}
    total = sc["total"]

    cmd = ["ffmpeg", "-y", "-v", "error"]
    parts = []
    for i, (key, _) in enumerate(segs):
        cmd += ["-i", os.path.join(work, f"{key}.wav")]
        d = int(round((starts[key] + LEAD) * 1000))
        parts.append(f"[{i}:a]aresample=48000,adelay={d}|{d}[a{i}]")
    mix = "".join(f"[a{i}]" for i in range(len(segs)))
    graph = ";".join(parts) + f";{mix}amix=inputs={len(segs)}:normalize=0:dropout_transition=0," \
        f"apad,atrim=0:{total},loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000[out]"
    track = os.path.join(work, "narration.wav")
    subprocess.run(cmd + ["-filter_complex", graph, "-map", "[out]", "-ac", "1", track], check=True)

    srt = os.path.splitext(out)[0] + ".srt"
    with open(srt, "w") as f:
        for i, (key, text) in enumerate(segs, 1):
            a = starts[key] + LEAD
            f.write(f"{i}\n{ts(a)} --> {ts(a + clips[key])}\n{text}\n\n")

    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", silent, "-i", track, "-i", srt,
                    "-map", "0:v", "-map", "1:a", "-map", "2:s", "-c:v", "copy",
                    "-c:a", "aac", "-b:a", "128k", "-c:s", "mov_text",
                    "-metadata:s:a:0", "language=eng", "-metadata:s:s:0", "language=eng",
                    "-t", str(total), "-movflags", "+faststart", out], check=True)
    for key, _ in segs:
        a = starts[key] + LEAD
        print(f"{key:11s} scene {starts[key]:7.2f}  voice {a:7.2f}-{a + clips[key]:7.2f}")
    print(f"total {total:.2f} s")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else "out/narration")
