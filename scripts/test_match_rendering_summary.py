import unittest
from summarize_match_rendering import percentile, summarize


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


if __name__ == "__main__":
    unittest.main()
