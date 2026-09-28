#!/usr/bin/env python3
"""Compare two benchmark result folders and print a markdown table.

usage: bench-compare.py bench/results/baseline bench/results/final
"""
import json
import pathlib
import sys

LOWER_IS_BETTER = True


def load(folder):
    out = {}
    for f in sorted(pathlib.Path(folder).glob("*.json")):
        report = json.loads(f.read_text())
        out[report["scenario"]] = report
    return out


def fmt(v):
    if v == 0:
        return "0"
    if abs(v) >= 100:
        return f"{v:,.0f}"
    if abs(v) >= 10:
        return f"{v:.1f}"
    return f"{v:.2f}"


def delta(before, after):
    if before == after:
        return "="
    if before == 0:
        return "new"
    change = (after - before) / before * 100
    if after == 0:
        return "−100%"
    ratio = before / after if after else float("inf")
    sign = "−" if change < 0 else "+"
    suffix = f" ({ratio:.0f}× less)" if ratio >= 3 else ""
    return f"{sign}{abs(change):.0f}%{suffix}"


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    base, new = load(sys.argv[1]), load(sys.argv[2])
    print(f"| scenario | metric | {pathlib.Path(sys.argv[1]).name} p50 | {pathlib.Path(sys.argv[2]).name} p50 | Δ p50 | before p95 | after p95 |")
    print("|---|---|---:|---:|---:|---:|---:|")
    for scenario in sorted(set(base) | set(new)):
        b = base.get(scenario, {}).get("metrics", {})
        n = new.get(scenario, {}).get("metrics", {})
        for metric in sorted(set(b) | set(n)):
            bp50 = b.get(metric, {}).get("p50")
            np50 = n.get(metric, {}).get("p50")
            bp95 = b.get(metric, {}).get("p95")
            np95 = n.get(metric, {}).get("p95")
            d = delta(bp50, np50) if bp50 is not None and np50 is not None else "—"
            cells = [fmt(x) if x is not None else "—" for x in (bp50, np50)]
            tails = [fmt(x) if x is not None else "—" for x in (bp95, np95)]
            print(f"| {scenario} | {metric} | {cells[0]} | {cells[1]} | {d} | {tails[0]} | {tails[1]} |")
    for label, reports in (("before", base), ("after", new)):
        commits = sorted({r.get("commit", "?") for r in reports.values()})
        machines = sorted({r.get("machine", "?") for r in reports.values()})
        print(f"\n{label}: commit {', '.join(commits)} · {', '.join(machines)}")


if __name__ == "__main__":
    main()
