"""Summarize exported XCTest render diagnostics; CPU callbacks are not GPU frames."""
import argparse
import json
import math
from pathlib import Path


def percentile(values, fraction):
    ordered = sorted(values)
    if not ordered:
        return None
    if not all(math.isfinite(v) and v >= 0 for v in ordered):
        raise ValueError("Non-finite or negative measurement")
    return round(ordered[max(0, math.ceil(len(ordered) * fraction) - 1)], 3)


def summarize(report):
    frames = sorted(report["frames"], key=lambda f: f["at"])
    if not frames or not report["memory"] or report["elapsed"] <= 0:
        raise ValueError("Incomplete render diagnostic report")
    costs = [frame["milliseconds"] for frame in frames]
    gaps = [(b["at"] - a["at"]) * 1000 for a, b in zip(frames, frames[1:]) if b["at"] - a["at"] > 0.005]
    memory = sorted(report["memory"], key=lambda sample: sample["seconds"])
    middle = min(memory, key=lambda s: abs(s["seconds"] - report["elapsed"] / 2))
    return {
        "kind": report["kind"], "optimized": report.get("optimized"),
        "elapsedSeconds": round(report["elapsed"], 3), "callbackCount": len(frames),
        "cpuCommandMs": {key: percentile(costs, p) for key, p in [("p50", .5), ("p95", .95), ("p99", .99), ("max", 1)]},
        "callbackIntervalMs": {key: percentile(gaps, p) for key, p in [("p50", .5), ("p95", .95), ("p99", .99), ("max", 1)]},
        "footprintMiB": {key: round(value / 2 ** 20, 3) for key, value in [
            ("start", memory[0]["footprint"]), ("midpoint", middle["footprint"]),
            ("end", memory[-1]["footprint"]), ("peakSampled", max(s["footprint"] for s in memory))]},
        "cache": report["cache"], "sourceCache": report.get("sourceCache"),
        "note": "Simulator CPU command/update callbacks, not GPU presentation or physical-device FPS. Cache pixel cost and process phys_footprint are distinct. One run does not prove absence of leaks.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = {path.stem: summarize(json.loads(path.read_text())) for path in args.inputs}
    text = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        args.output.write_text(text + "\n")
    else:
        print(text)


if __name__ == "__main__":
    main()
