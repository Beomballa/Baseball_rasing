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


def summarize_live(report):
    """Real CareerGameView, including its covered SpriteView; no GPU FPS inference."""
    preparations = report["preparations"]
    ready = max((p["endedAt"] for p in preparations), default=0)
    frames = [f for f in report["frames"] if f["at"] >= ready]
    field = sorted((f for f in frames if f["kind"] in ("field", "homeRun", "groundSprite", "fieldSprite", "homeRunSprite")), key=lambda f: f["at"])
    if not field or not report["memory"]:
        raise ValueError("Incomplete live render report")
    costs = [f["milliseconds"] for f in field]
    gaps = [(b["at"]-a["at"])*1000 for a, b in zip(field, field[1:])]
    memory = sorted(report["memory"], key=lambda m: m["at"])
    playback = [f["playbackTime"] for f in field if f.get("playbackTime") is not None]
    return {
        "role": report["role"], "fieldCallbacks": len(field),
        "motionPolicy": report.get("motionPolicy"),
        "playbackClock": {"samples": len(playback), "distinctTimes": len(set(playback)),
                          "advanceSeconds": round(max(playback)-min(playback), 4) if playback else None},
        "cpuCommandMs": {k: percentile(costs, p) for k, p in [("p50", .5), ("p95", .95), ("p99", .99), ("max", 1)]},
        "callbackIntervalMs": {k: percentile(gaps, p) for k, p in [("p50", .5), ("p95", .95), ("p99", .99), ("max", 1)]},
        "cpuCommandsOver33Ms": sum(v > 33.333 for v in costs),
        "coveredSpriteUpdatesAfterReady": sum(f["kind"] == "spriteUpdate" for f in frames),
        "preparedHits": report["preparedHits"], "preparedMisses": report["preparedMisses"],
        "spriteTextures": {"count": report.get("spriteTextureCount", 0), "swaps": report.get("spriteTextureSwaps", 0), "fallbacks": report.get("spriteFallbacks", 0)},
        "rendererCallbacks": {kind: sum(f["kind"] == kind for f in field) for kind in ("field", "homeRun", "groundSprite", "fieldSprite", "homeRunSprite")},
        "preparation": [{"seconds": round(p["seconds"], 3), "images": p["images"], "pixelMiB": round(p["bytes"]/2**20, 3)} for p in preparations],
        "footprintMiB": {"start": round(memory[0]["bytes"]/2**20, 3), "end": round(memory[-1]["bytes"]/2**20, 3), "peakSampled": round(max(m["bytes"] for m in memory)/2**20, 3)},
        "note": "Real gameplay screen in simulator -O diagnostic build. Canvas command or SpriteKit update duration/callback interval is not GPU presentation or physical-device FPS. Preparation is asynchronous wall time. Memory sampled at entry/3s/exit, not a leak or thermal test.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    reports = {path.stem: json.loads(path.read_text()) for path in args.inputs}
    result = {name: (summarize_live(report) if "preparations" in report else summarize(report)) for name, report in reports.items()}
    text = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        args.output.write_text(text + "\n")
    else:
        print(text)


if __name__ == "__main__":
    main()
