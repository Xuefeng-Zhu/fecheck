#!/usr/bin/env python3
"""Keeps the case embedded in a Fe test in step with a .case file.

`fe test` on the EVM has no filesystem effect (`std::fs::Fs` doesn't exist
on that target), so a test can't open a .case file. Instead the file's lines
are generated into a Fe function, `native_case_text()`, as one `writeln!`
per line.

    scripts/embed-case.py --write CASE FE_FILE   regenerate the function body
    scripts/embed-case.py --check CASE FE_FILE   fail if it differs from CASE
"""
import json, os, re, shutil, subprocess, sys

START = "pub fn native_case_text() -> MemBuffer {\n"
END = "\n    out\n}\n"


def fe_string(s):
    # JSON escaping covers the escapes Fe accepts (\\, \", \n, \t).
    return json.dumps(s, ensure_ascii=False)


def generate(case_text):
    out = ["    var out = MemBuffer::new(0)"]
    for line in case_text.splitlines():
        lit = fe_string(line)
        if len("    writeln!(mut out, ") + len(lit) + 1 <= 100:
            out.append(f"    writeln!(mut out, {lit})")
        else:
            out.append(f"    writeln!(\n        mut out,\n        {lit},\n    )")
    return "\n".join(out)


def main():
    mode, case_path, fe_path = sys.argv[1:4]
    case_text = open(case_path).read()
    src = open(fe_path).read()
    a = src.index(START) + len(START)
    b = src.index(END, a)
    body = src[a:b]
    if mode == "--write":
        open(fe_path, "w").write(src[:a] + generate(case_text) + src[b:])
        fe = os.environ.get("FE", "fe")
        if shutil.which(fe):
            # Let `fe fmt` choose the line breaks; the check ignores them.
            ingot = os.path.dirname(os.path.dirname(os.path.abspath(fe_path)))
            subprocess.run([fe, "fmt", ingot], check=True, stdout=subprocess.DEVNULL)
        print(f"wrote native_case_text() in {fe_path} from {case_path}")
        return
    lines = re.findall(r'writeln!\(\s*mut out,\s*("(?:[^"\\]|\\.)*")', body)
    embedded = "".join(json.loads(l) + "\n" for l in lines)
    if embedded != case_text:
        sys.exit(f"embed-case: the case in {fe_path} differs from {case_path}; "
                 f"run scripts/embed-case.py --write {case_path} {fe_path}")
    print(f"identical: {case_path} and native_case_text() in {fe_path}")


main()
