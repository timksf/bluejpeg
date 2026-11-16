#!/usr/bin/env python3
"""Regenerate the encoder register map in README.md from the BlueCSR definition.

    python3 hdl/docgen/regmap.py            # run inside the Nix shell, needs bsc
    python3 hdl/docgen/regmap.py --print    # print the table instead of editing README.md

Elaborates RegDoc.bsv (doc_blue_csr_markdown over blue_jpeg_csrs), formats the result as an aligned
text table and replaces the text between the <!-- regmap:begin --> and <!-- regmap:end --> markers.
Nothing is synthesized.
"""
import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BEGIN, END = "<!-- regmap:begin -->", "<!-- regmap:end -->"


def generate():
    paths = [ROOT / "hdl/src/encoder", ROOT / "hdl/libraries/bluecsr/src"]
    with tempfile.TemporaryDirectory() as tmp:
        cmd = ["bsc", "-verilog", "-u", "-g", "mkRegDoc", "-bdir", tmp, "-vdir", tmp, "-info-dir", tmp,
               "-p", ":".join(str(p) for p in paths) + ":+", str(HERE / "RegDoc.bsv")]
        res = subprocess.run(cmd, capture_output=True, text=True)
    log = res.stdout + res.stderr
    m = re.search(r"REGDOC_BEGIN\n(.*?)\nREGDOC_END", log, re.S)
    if res.returncode != 0 or not m:
        sys.exit(f"bsc failed:\n{log}")
    return m.group(1).strip()


def to_text_block(markdown):
    """Turn the exporter's Markdown table into an aligned plain-text table in a code block.

    GitHub wraps long cells in Markdown tables. A code block keeps one line per field and scrolls
    horizontally instead, so the map stays dense and every column lines up.
    """
    rows = [[c.strip() for c in line.strip().strip("|").split("|")]
            for line in markdown.splitlines() if line.startswith("|") and not line.startswith("| ---")]
    #table regions have no fields, their description goes to the last column to keep the others narrow
    body = [r if any(r[3:]) else r[:2] + [""] * 5 + [r[2]] for r in rows[1:]]
    header = ["Offset", "Register", "Description", "Field", "Bits", "Access", "Reset", "Field description"]
    widths = [max(len(r[i]) for r in [header] + body) for i in range(len(header))]
    lines = ["  ".join(c.ljust(w) for c, w in zip(r, widths)).rstrip() for r in [header] + body]
    return "```text\n" + "\n".join(lines) + "\n```"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--print", action="store_true", help="print the table, leave README.md alone")
    args = ap.parse_args()
    table = to_text_block(generate())
    if args.print:
        print(table)
        return
    readme = ROOT / "README.md"
    text = readme.read_text()
    if BEGIN not in text or END not in text:
        sys.exit(f"{readme} has no {BEGIN} / {END} markers")
    head, rest = text.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    readme.write_text(f"{head}{BEGIN}\n{table}\n{END}{tail}")
    print(f"updated {readme}")


if __name__ == "__main__":
    main()
