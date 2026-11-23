#!/usr/bin/env python3
"""Render a terminal-style demo video from real captured command output.

    python3 scripts/render_demo.py docs/media/fecheck-demo.mp4 out/rec [min.json]

min.json (optional, written by scripts/narrate_demo.py) maps scene keys to a
minimum scene length in seconds; a scene that would end sooner holds its last
frame until then, so narration never has to be sped up. Scene starts are
written to <rec>/scenes.txt and <rec>/scenes.json.

out/rec holds what scripts/record-demo.sh captured: NN.cmd (the command
line), NN.out (stdout+stderr), NN.rc (exit code) and NN.ms (wall clock).
Commands are typed; output lines appear exactly as captured. The only
non-captured text is captions (lines starting with `#`), the title and end
cards, and a dim `[... N lines omitted ...]` marker where long output is
trimmed for pacing. Trimming only ever drops lines; it never edits one.
"""
import json
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

W, H, FPS = 1280, 720, 30
FD = "/usr/share/fonts/truetype/dejavu/"
FONT = ImageFont.truetype(FD + "DejaVuSansMono.ttf", 17)
BOLD = ImageFont.truetype(FD + "DejaVuSansMono-Bold.ttf", 17)
CAP = ImageFont.truetype(FD + "DejaVuSans-Bold.ttf", 21)
BIG = ImageFont.truetype(FD + "DejaVuSansMono-Bold.ttf", 52)
MID = ImageFont.truetype(FD + "DejaVuSans.ttf", 27)
SMALL = ImageFont.truetype(FD + "DejaVuSans.ttf", 19)
CW = FONT.getlength("M")
LH = 22
TOP = 50
ROWS = (H - TOP - 14) // LH
MAXCH = int((W - 32) // CW)
BG = (22, 24, 30)
BAR = (38, 41, 50)
FG = (215, 218, 224)
DIM = (130, 136, 150)
GREEN = (120, 220, 140)
RED = (255, 110, 110)
YELLOW = (240, 200, 90)
CYAN = (110, 200, 240)
CAPC = (250, 214, 120)


def load(rec, key):
    def rd(ext):
        p = os.path.join(rec, f"{key}.{ext}")
        return open(p).read() if os.path.exists(p) else ""
    out = rd("out").rstrip("\n")
    return {
        "cmd": rd("cmd").strip(),
        "out": out.split("\n") if out else [],
        "rc": rd("rc").strip(),
        "ms": rd("ms").strip(),
    }


def wrap(line):
    """Terminal-style hard wrap of one captured line (no characters dropped)."""
    if len(line) <= MAXCH:
        return [("out", line)]
    c = color_for(line)
    rows = [("out", line[:MAXCH])]
    for i in range(MAXCH, len(line), MAXCH):
        rows.append(("wrap", (c, line[i:i + MAXCH])))
    return rows


def expand(body):
    rows = []
    for kind, text in body:
        rows.extend(wrap(text) if kind == "out" else [(kind, text)])
    return rows


def find(lines, pred, start=0):
    for i in range(start, len(lines)):
        if pred(lines[i]):
            return i
    return -1


def color_for(line):
    s = line.strip()
    if "<-- violation" in line or s.startswith("Property failed") or s.startswith("FAIL") \
            or s.startswith("REPRODUCED"):
        return RED
    if s.startswith("NOT REPRODUCED") or s.startswith("PASS") or s.startswith("test result: ok") \
            or s.startswith("Property passed") or s.startswith("native: "):
        return GREEN
    if s.startswith("Shrunk:") or s.startswith("Original:"):
        return YELLOW
    if s.startswith("FeCheck - ") or s.startswith("== ") or s.startswith("fe ") \
            or s.startswith("fecheck "):
        return CYAN
    return FG


KEY = ("Property failed", "Shrunk:", "<-- violation", "REPRODUCED", "NOT REPRODUCED",
       "test result:", "Property passed", "native: ", "PASS")


def is_key(line):
    s = line.strip()
    return "<-- violation" in line or any(s.startswith(k) for k in KEY)


class Video:
    def __init__(self, out, title, mins=None):
        self.title = title
        self.mins = mins or {}
        self.last = None
        self.p = subprocess.Popen(
            ["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
             "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-c:v", "libx264",
             "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p",
             "-movflags", "+faststart", out], stdin=subprocess.PIPE)
        self.n = 0
        self.marks = []

    def pad(self):
        """Hold the previous scene's last frame up to its minimum length."""
        if not self.marks or self.last is None:
            return
        start, key, _ = self.marks[-1]
        need = int(round((start + self.mins.get(key, 0)) * FPS)) - self.n
        if need > 0:
            self.emit(self.last, frames=need)

    def mark(self, key, name):
        self.pad()
        self.marks.append((self.n / FPS, key, name))

    def emit(self, img, secs=None, frames=None):
        self.last = img
        k = frames if frames is not None else max(1, int(round(secs * FPS)))
        b = img.tobytes()
        for _ in range(k):
            self.p.stdin.write(b)
        self.n += k

    def close(self):
        self.pad()
        self.p.stdin.close()
        return self.p.wait()

    def base(self):
        img = Image.new("RGB", (W, H), BG)
        d = ImageDraw.Draw(img)
        d.rectangle([0, 0, W, 34], fill=BAR)
        for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
            d.ellipse([14 + i * 22, 11, 26 + i * 22, 23], fill=c)
        tw = d.textlength(self.title, font=FONT)
        d.text(((W - tw) / 2, 8), self.title, font=FONT, fill=DIM)
        return img, d

    def term(self, lines, cursor=False):
        img, d = self.base()
        view = lines[-ROWS:]
        y = TOP
        for kind, text in view:
            if kind == "cmd":
                d.text((16, y), "$ ", font=BOLD, fill=GREEN)
                d.text((16 + 2 * CW, y), text, font=BOLD, fill=FG)
            elif kind == "cap":
                d.text((16, y - 1), text, font=CAP, fill=CAPC)
            elif kind == "omit":
                d.text((16, y), text, font=FONT, fill=DIM)
            elif kind == "rc":
                d.text((16, y), text, font=FONT, fill=DIM)
            elif kind == "wrap":
                d.text((16, y), text[1], font=FONT, fill=text[0])
            else:
                d.text((16, y), text, font=FONT, fill=color_for(text))
            y += LH
        if cursor and view:
            kind, text = view[-1]
            text = text if isinstance(text, str) else text[1]
            n = len(text) + (2 if kind == "cmd" else 0)
            cy = TOP + (len(view) - 1) * LH
            d.rectangle([16 + n * CW, cy + 2, 16 + n * CW + 9, cy + 19], fill=FG)
        return img

    def card(self, rows):
        img, d = self.base()
        total = sum(h for _, _, _, h in rows)
        y = (H - total) / 2
        for t, f, c, h in rows:
            tw = d.textlength(t, font=f)
            d.text(((W - tw) / 2, y), t, font=f, fill=c)
            y += h
        return img


def scene(v, caption, step, show=None, line_frames=3, hold=3.0, clear=True, lines=None):
    """Caption, typed command, then output (a list of (kind, text) or the
    full captured output). Returns the screen lines for a continued scene."""
    if clear or lines is None:
        lines = []
    lines.append(("cap", caption))
    v.emit(v.term(lines), 1.4)
    lines.append(("cmd", ""))
    cmd = step["cmd"]
    for i in range(1, len(cmd) + 1):
        lines[-1] = ("cmd", cmd[:i])
        v.emit(v.term(lines, cursor=True), frames=1 if len(cmd) > 40 else 2)
    v.emit(v.term(lines, cursor=True), 0.5)
    body = expand(show if show is not None else [("out", ln) for ln in step["out"]])
    for kind, text in body:
        lines.append((kind, text))
        v.emit(v.term(lines), frames=line_frames)
        if kind == "out" and is_key(text):
            v.emit(v.term(lines), 1.3)
        if kind == "omit":
            v.emit(v.term(lines), 0.8)
    lines.append(("rc", f"[exit {step['rc']}]"))
    v.emit(v.term(lines), hold)
    return lines


def trim_run(out):
    """`fecheck run` output: everything through the reproduce command, then
    the regression test it prints (head only)."""
    rep = find(out, lambda s: s.startswith("Reproduce with:"))
    end = rep + 2 if rep >= 0 else min(len(out), ROWS - 3)
    first = [("out", ln) for ln in out[:end]]
    rest = out[end:]
    while rest and not rest[0].strip():
        rest = rest[1:]
    return first, rest


def main(dst, rec, mins_path=None):
    mins = json.load(open(mins_path)) if mins_path else {}
    s = {k: load(rec, k) for k in ("01", "02", "03", "04", "05", "06", "07")}
    fe_ver = s["01"]["out"][0].split(" (")[0] if s["01"]["out"] else "fe"
    fc = next((ln for ln in s["03"]["out"] if ln.startswith("fecheck ")), "fecheck")
    sha = open(os.path.join(rec, "sha")).read().strip() if os.path.exists(os.path.join(rec, "sha")) else ""
    title = f"{fc}  ·  {fe_ver}  ·  real captured output" + (f"  ·  {sha}" if sha else "")
    v = Video(dst, title, mins)

    v.mark("title", "Title card")
    v.emit(v.card([("FeCheck", BIG, CYAN, 84),
                   ("Property-based testing for Fe", MID, FG, 56),
                   ("Find the failure. Shrink the story. Replay the proof.", MID, CAPC, 60),
                   (f"{fc}  ·  {fe_ver}", SMALL, DIM, 30)]), 4.0)

    v.mark("version", "fe --version")
    scene(v, "# The compiler: Fe 26.6.0", s["01"], hold=1.8)

    v.mark("run", "fecheck run permissions")
    first, rest = trim_run(s["02"]["out"])
    lines = scene(v, "# 1. Search 1,000 random operation sequences against a permission system (exit 1 = failure found)",
                  s["02"], show=first, hold=4.0)
    if rest:
        v.mark("regtest", "regression test printed by run")
        HEAD, TAIL = 7, 5
        if len(rest) > HEAD + TAIL + 1:
            body = [("out", ln) for ln in rest[:HEAD]]
            body.append(("omit", f"      [... {len(rest) - HEAD - TAIL} lines omitted for the video ...]"))
            body += [("out", ln) for ln in rest[-TAIL:]]
        else:
            body = [("out", ln) for ln in rest]
        lines = [("cap", "# run also prints a regression test you can paste into fe test")]
        v.emit(v.term(lines), 1.4)
        for kind, text in expand(body):
            lines.append((kind, text))
            v.emit(v.term(lines), frames=3)
            if kind == "omit":
                v.emit(v.term(lines), 0.8)
        v.emit(v.term(lines), 4.0)

    v.mark("case", "saved case header")
    lines = scene(v, "# 2. The saved case pins the compiler and FeCheck versions", s["03"], hold=2.6)

    v.mark("replay", "replay (buggy)")
    lines = scene(v, "# 3. Replay it against the same buggy system", s["04"], hold=3.0)
    v.mark("fixed", "replay --against permissions-fixed")
    lines = scene(v, "# 4. ... and against the fixed system (exit 3 = not reproduced)", s["05"], hold=3.5)

    v.mark("native_evm", "native-to-EVM")
    out6 = s["06"]["out"]
    show6 = [("out", ln) for ln in out6]
    if len(show6) > ROWS - 4:
        keep = [ln for ln in out6 if ln.startswith("== ") or is_key(ln)]
        show6 = [("out", ln) for ln in keep]
        show6.insert(0, ("omit", f"[{len(out6) - len(keep)} of {len(out6)} lines omitted; headings and results shown]"))
    scene(v, "# 5. Found natively, confirmed on the fe test EVM, then 1,000,000 native cases",
          s["06"], show=show6, line_frames=6, hold=5.0)

    v.mark("erc20", "erc20 mutant")
    scene(v, "# 6. Demo E: a one-line ERC-20 mutant is caught (these tests pass only if it is)",
          s["07"], hold=3.5)

    v.mark("end", "End card")
    v.emit(v.card([("Found. Shrunk. Replayed. Confirmed on the EVM.", MID, GREEN, 70),
                   ("github.com/Xuefeng-Zhu/fecheck", BIG, CYAN, 80),
                   ("181 EVM tests + native suites  ·  Fe 26.6.0", MID, FG, 50)]), 5.0)
    rc = v.close()
    with open(os.path.join(rec, "scenes.txt"), "w") as f:
        for t, _, name in v.marks:
            f.write(f"{int(t // 60)}:{t % 60:05.2f}  {name}\n")
        f.write(f"total {v.n / FPS:.2f} s\n")
    with open(os.path.join(rec, "scenes.json"), "w") as f:
        json.dump({"scenes": [{"key": k, "name": nm, "start": round(t, 3)} for t, k, nm in v.marks],
                   "total": round(v.n / FPS, 3)}, f, indent=1)
    sys.exit(rc)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "out/rec",
         sys.argv[3] if len(sys.argv) > 3 else None)
