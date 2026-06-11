#!/usr/bin/env python
"""
phinder integrated summary — SCAFFOLD.

REVIEW: This is a generated placeholder. Port the real per-tool parsing and the
publication-quality HTML layout from the original PHINDER repo's bin/ here. It
currently does a tolerant concat of every *.tsv it finds per tool directory and
writes a flat combined table + a minimal HTML wrapper, so the pipeline wires and
runs end-to-end; the science of the summary still needs the original logic.
"""
import argparse
import glob
import os
import sys

try:
    import pandas as pd
except ImportError:  # keep the scaffold runnable even without pandas
    pd = None


def collect(tool_dir):
    """Read every .tsv under tool_dir into a tagged DataFrame list."""
    frames = []
    for path in sorted(glob.glob(os.path.join(tool_dir, "**", "*.tsv"), recursive=True)):
        if pd is None:
            continue
        try:
            df = pd.read_csv(path, sep="\t")
            df.insert(0, "tool", os.path.basename(tool_dir.rstrip("/")))
            df.insert(1, "source_file", os.path.basename(path))
            frames.append(df)
        except Exception as exc:  # noqa: BLE001 - tolerant by design in the scaffold
            print(f"WARN: could not parse {path}: {exc}", file=sys.stderr)
    return frames


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkv")
    ap.add_argument("--quast")
    ap.add_argument("--pharokka")
    ap.add_argument("--bacphlip")
    ap.add_argument("--vibrant")
    ap.add_argument("--out-tsv", required=True)
    ap.add_argument("--out-html", required=True)
    args = ap.parse_args()

    tool_dirs = [d for d in (args.checkv, args.quast, args.pharokka, args.bacphlip, args.vibrant) if d]

    if pd is None:
        # Degraded mode: still emit the expected outputs so downstream wiring holds.
        with open(args.out_tsv, "w") as fh:
            fh.write("tool\tsource_file\tnote\n")
            fh.write("NA\tNA\tpandas unavailable; scaffold ran in degraded mode\n")
        with open(args.out_html, "w") as fh:
            fh.write("<html><body><h1>phinder summary (scaffold)</h1>"
                     "<p>pandas unavailable — port real logic in bin/summarize_phinder.py</p></body></html>")
        return

    frames = []
    for d in tool_dirs:
        frames.extend(collect(d))

    combined = pd.concat(frames, ignore_index=True) if frames else pd.DataFrame(
        columns=["tool", "source_file", "note"]
    )
    combined.to_csv(args.out_tsv, sep="\t", index=False)

    html = ["<html><head><meta charset='utf-8'><title>phinder summary</title></head><body>",
            "<h1>phinder integrated summary (scaffold)</h1>",
            "<p>REVIEW: replace with the original PHINDER report layout.</p>",
            combined.to_html(index=False),
            "</body></html>"]
    with open(args.out_html, "w") as fh:
        fh.write("\n".join(html))


if __name__ == "__main__":
    main()
