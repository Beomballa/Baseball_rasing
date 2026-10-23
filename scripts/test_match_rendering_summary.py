import unittest
from summarize_match_rendering import percentile, summarize, summarize_live


class RenderingSummaryTests(unittest.TestCase):
    def test_nearest_rank_and_invalid_samples(self):
        self.assertEqual(percentile([4, 1, 3, 2], .95), 4)
        self.assertIsNone(percentile([], .95))
        with self.assertRaises(ValueError):
            percentile([float("nan")], .5)

    def test_memory_cache_and_callback_cost_are_not_conflated(self):
        report = {"kind": "sample", "elapsed": 2, "frames": [
            {"at": 1, "milliseconds": 1}, {"at": 1.033, "milliseconds": 3}],
            "memory": [{"seconds": 0, "footprint": 2**20}, {"seconds": 2, "footprint": 3*2**20}],
            "cache": {"bytes": 123}}
        result = summarize(report)
        self.assertEqual(result["footprintMiB"]["peakSampled"], 3)
        self.assertEqual(result["cache"]["bytes"], 123)
        self.assertEqual(result["cpuCommandMs"]["p95"], 3)
        self.assertEqual(result["callbackIntervalMs"]["p95"], 33)
        self.assertIsNone(result["optimized"])

    def test_incomplete_report_is_not_a_zero_cost_success(self):
        with self.assertRaises(ValueError):
            summarize({"frames": [], "memory": [], "elapsed": 1})

    def test_live_filters_preparation_and_does_not_mix_covered_scene_callbacks(self):
        report = {"role": "pitcher", "preparations": [{"endedAt": 2, "seconds": .4, "images": 3, "bytes": 2**20}],
                  "frames": [{"kind": "field", "at": 1, "milliseconds": 80}, {"kind": "spriteUpdate", "at": 1.5, "milliseconds": .1},
                             {"kind": "field", "at": 2.01, "milliseconds": 1}, {"kind": "field", "at": 2.043, "milliseconds": 2}],
                  "preparedHits": 50, "preparedMisses": 0, "memory": [{"at": 1, "bytes": 2**20}, {"at": 3, "bytes": 3*2**20}]}
        result = summarize_live(report)
        self.assertEqual(result["fieldCallbacks"], 2)
        self.assertEqual(result["cpuCommandMs"]["max"], 2)
        self.assertEqual(result["callbackIntervalMs"]["max"], 33)
        self.assertEqual(result["coveredSpriteUpdatesAfterReady"], 0)
        self.assertEqual(result["preparation"][0]["seconds"], .4)
        report["preparations"] = []
        result = summarize_live(report)
        self.assertEqual(result["cpuCommandsOver33Ms"], 1)
        self.assertEqual(result["coveredSpriteUpdatesAfterReady"], 1)


if __name__ == "__main__":
    unittest.main()
