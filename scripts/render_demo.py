#!/usr/bin/env python3
"""Render a terminal-style video from real captured command outputs.
Commands are typed; output appears line by line exactly as captured."""
import subprocess, sys, os
from PIL import Image, ImageDraw, ImageFont

R = os.path.dirname(os.path.abspath(__file__))
W, H, FPS = 1280, 720, 30
FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 17)
BOLD = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf", 17)
BIG = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf", 44)
MID = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 24)
LH = 22
TOP = 46
ROWS = (H - TOP - 12) // LH
BG = (22, 24, 30)
FG = (215, 218, 224)
DIM = (130, 136, 150)
GREEN = (120, 220, 140)
RED = (255, 110, 110)
YELLOW = (240, 200, 90)
CYAN = (110, 200, 240)

STEPS = [
    ("# FeCheck: property-based testing for Fe", None),
    ("fe --version", "01"),
    ("# 1. Search 1,000 random operation sequences against a permission system", None),
    ("fecheck run permissions --seed 12345", "02"),
    ("# 2. Replay the saved case against the same buggy system", None),
    ("fecheck replay failures/permissions.case", "03"),
    ("# 3. Replay it against the fixed system", None),
    ("fecheck replay failures/permissions.case --against permissions-fixed", "04"),
    ("# 4. A bounded ring-buffer queue with a wrap-around bug", None),
    ("fecheck run queue --seed 12345", "05"),
    ("fecheck replay failures/queue.case --against queue-fixed", "06"),
    ("# 5. The same engine testing a deployed EVM contract inside fe test", None),
    ("fe test examples/contract", "07"),
]

def color_for(line):
    if "<-- violation" in line or line.startswith("Property failed") or line.startswith("FAIL"):
        return RED
    if line.startswith("NOT REPRODUCED") or line.startswith("PASS") or line.startswith("test result: ok"):
        return GREEN
    if line.startswith("REPRODUCED") or line.startswith("Shrunk:"):
        return YELLOW
    if line.startswith("FeCheck - "):
        return CYAN
    return FG

def frame(lines, cursor=False, banner=None):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    # title bar
    d.rectangle([0, 0, W, 32], fill=(38, 41, 50))
    for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        d.ellipse([14 + i * 22, 10, 26 + i * 22, 22], fill=c)
    d.text((W // 2 - 150, 7), "fecheck - Fe 26.6.0 - real output", font=FONT, fill=DIM)
    view = lines[-ROWS:]
    y = TOP
    for kind, text in view:
        if kind == "cmd":
            d.text((16, y), "$ ", font=BOLD, fill=GREEN)
            d.text((16 + 2 * 10.2, y), text, font=BOLD, fill=FG)
        elif kind == "comment":
            d.text((16, y), text, font=FONT, fill=DIM)
        elif kind == "rc":
            d.text((16, y), text, font=FONT, fill=GREEN if text.endswith(" 0]") else YELLOW)
        else:
            d.text((16, y), text, font=FONT, fill=color_for(text))
        y += LH
    if cursor:
        last = view[-1] if view else ("cmd", "")
        n = len(last[1]) + (2 if last[0] == "cmd" else 0)
        cy = TOP + (len(view) - 1) * LH
        d.rectangle([16 + n * 10.2, cy + 2, 16 + n * 10.2 + 9, cy + 19], fill=FG)
    if banner:
        d.rectangle([0, H // 2 - 80, W, H // 2 + 80], fill=(30, 33, 42))
        for i, (t, f, c) in enumerate(banner):
            tw = d.textlength(t, font=f)
            d.text(((W - tw) / 2, H // 2 - 60 + i * 60), t, font=f, fill=c)
    return img

def main(out):
    p = subprocess.Popen(["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                          "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-c:v", "libx264",
                          "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p",
                          "-movflags", "+faststart", out], stdin=subprocess.PIPE)
    def emit(img, n=1):
        b = img.tobytes()
        for _ in range(n):
            p.stdin.write(b)
    # title card
    emit(frame([], banner=[("FeCheck", BIG, CYAN),
                           ("Find the failure. Shrink the story. Replay the proof.", MID, FG)]), FPS * 3)
    lines = []
    for text, key in STEPS:
        if key is None:
            lines.append(("comment", text))
            emit(frame(lines), int(FPS * 0.9))
            continue
        lines.append(("cmd", ""))
        for i in range(1, len(text) + 1):
            lines[-1] = ("cmd", text[:i])
            emit(frame(lines, cursor=True), 1)
        emit(frame(lines, cursor=True), int(FPS * 0.4))
        out_lines = open(os.path.join(R, key + ".out")).read().rstrip("\n").split("\n")
        rc = open(os.path.join(R, key + ".rc")).read().strip()
        for ln in out_lines:
            lines.append(("out", ln))
            emit(frame(lines), 2)
            if "<-- violation" in ln or ln.startswith("Shrunk:"):
                emit(frame(lines), int(FPS * 2.2))
        lines.append(("rc", f"[exit {rc}]"))
        hold = 4.5 if key in ("02", "04", "05") else 2.5
        emit(frame(lines), int(FPS * hold))
        lines.append(("out", ""))
    emit(frame(lines, banner=[("Found. Shrunk. Replayed. Fixed.", BIG, GREEN),
                              ("github.com/Xuefeng-Zhu/fecheck", MID, FG)]), FPS * 4)
    p.stdin.close()
    p.wait()
    sys.exit(p.returncode)

if __name__ == "__main__":
    main(sys.argv[1])
