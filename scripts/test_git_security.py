#!/usr/bin/env python3
"""Run privacy-hook checks against disposable Git repositories, never user saves."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from check_commit_message import valid_subject
from check_staged import allowed_path, content_issues, blob_issues, ART_HASHES

ROOT = Path(__file__).resolve().parent.parent


class GitPrivacyTests(unittest.TestCase):
    def test_only_reviewed_game_art_is_allowed(self):
        for path in ART_HASHES:
            self.assertTrue(allowed_path(path))
            self.assertEqual(blob_issues(path, (ROOT / path).read_bytes()), [])
            self.assertEqual(blob_issues(path, b"unreviewed"), ["unreviewed-game-art"])
        self.assertFalse(allowed_path("BM/Resources/MatchArt/private.png"))
        self.assertFalse(allowed_path("qa/screenshot.png"))

    def test_required_source_paths_only(self):
        for path in ["BM/App/BMApp.swift", "BMTests/CareerStoreTests.swift", "BM/Resources/schools.json",
                     "BM.xcodeproj/project.pbxproj", ".githooks/pre-commit"]:
            self.assertTrue(allowed_path(path), path)
        for path in ["qa/result.json", "BM/Secrets/Credentials.swift", "BM/.env.swift", "BM/data.json",
                     "BM.xcodeproj/xcuserdata/user.xcuserdatad/UserInterfaceState.xcuserstate", "BM/avatar.png"]:
            self.assertFalse(allowed_path(path), path)

    def test_tool_metadata_and_generated_swift_are_not_source(self):
        for path in ["BM/.claude/config.swift", "BM/.omc/session.swift", "BM/.omx/session.swift",
                     "BM/.codex/state.swift", "BM/.worktrees/local/Test.swift", "BM/generated/Client.swift",
                     "BM/Domain/.private/Notes.swift", "BMTests/generated/Test.swift",
                     "BMUITests/.cache/Session.swift"]:
            self.assertFalse(allowed_path(path), path)
        self.assertTrue(allowed_path(".githooks/pre-commit"))
        self.assertTrue(allowed_path("BMTests/CareerStoreTests.swift"))
        self.assertTrue(allowed_path("AGENTS.md"))

    def test_secret_and_personal_values_are_detected(self):
        cases = [
            ("private-key", "-----BEGIN " + "PRIVATE KEY-----"),
            ("github-token", "ghp_" + "x" * 36),
            ("aws-access-id", "AKIA" + "A" * 16),
            ("credential-literal", "pass" + 'word = "not-a-real-credential"'),
            ("personal-home-path", "/" + "Users" + "/someone/project/"),
            ("email-address", "private" + "@" + "example.invalid"),
            ("signing-team", "DEVELOPMENT_" + "TEAM = ABC1234567;"),
        ]
        for kind, value in cases:
            self.assertIn(kind, content_issues(value.encode()), kind)
        self.assertEqual(content_issues(b"\x00binary"), ["binary-content"])

    def test_public_build_identifier_is_allowed(self):
        self.assertEqual(content_issues(b'PRODUCT_BUNDLE_IDENTIFIER = "dev.bm.career";'), [])

    def test_calendar_commit_subject(self):
        self.assertTrue(valid_subject("2026.10.19 iOS 기본 구조 테스트 커밋 작업 수행"))
        self.assertTrue(valid_subject("2028.02.29 선수 홈 작업 수행"))
        for subject in ["test commit", "2026.02.30 저장 작업 수행", "2026.10.19 작업 수행", "2026-10-19 저장 작업 수행"]:
            self.assertFalse(valid_subject(subject), subject)

    def test_ignore_and_hooks_block_forced_private_file(self):
        with tempfile.TemporaryDirectory(prefix="bm-git-hook-") as directory:
            repo = Path(directory)
            env = os.environ.copy()
            for key in ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_AUTHOR_EMAIL", "GIT_COMMITTER_EMAIL"]:
                env.pop(key, None)
            def git(*args):
                return subprocess.run(["git", *args], cwd=repo, env=env, capture_output=True)
            self.assertEqual(git("init", "-q").returncode, 0)
            git("config", "user.name", "Hook Test")
            git("config", "user.email", "hook" + "@" + "users.noreply.github.com")
            git("config", "core.hooksPath", ".githooks")
            shutil.copy(ROOT / ".gitignore", repo / ".gitignore")
            shutil.copytree(ROOT / ".githooks", repo / ".githooks")
            shutil.copytree(ROOT / "scripts", repo / "scripts", ignore=shutil.ignore_patterns("__pycache__"))
            (repo / "BM").mkdir()
            good = repo / "BM/Good.swift"; good.write_text("struct Safe {}\n")
            for path in ["qa/record.json", "BM/.env", "Signing.local.xcconfig", "BM/secrets/key.swift", "BM/db.store",
                         "BM/.claude/config.swift", "BM/Domain/.private/Notes.swift", "BM/.omc/session.swift",
                         "BM/.omx/session.swift", "BM/.codex/state.swift", "BM/.worktrees/local/Test.swift",
                         "BM/generated/Client.swift", "BM/local.sql", "BM/local.iml"]:
                self.assertEqual(git("check-ignore", "-q", path).returncode, 0, path)
            for path in ["BM/Good.swift", "BMTests/CareerStoreTests.swift", "AGENTS.md", "README.md",
                         ".githooks/pre-commit", ".githooks/commit-msg"]:
                self.assertEqual(git("check-ignore", "-q", path).returncode, 1, path)
            (repo / "qa").mkdir(); (repo / "qa/record.json").write_text("{}")
            git("add", "BM/Good.swift"); git("add", "-f", "qa/record.json")
            result = git("commit", "-m", "2026.10.19 검사 작업 수행")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"not-in-source-allowlist", result.stderr)
            self.assertNotEqual(git("rev-parse", "--verify", "HEAD").returncode, 0)
            git("rm", "--cached", "qa/record.json")
            (repo / "BM/generated").mkdir()
            (repo / "BM/generated/Client.swift").write_text("struct Generated {}")
            git("add", "-f", "BM/generated/Client.swift")
            result = git("commit", "-m", "2026.10.19 검사 작업 수행")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"not-in-source-allowlist", result.stderr)
            git("rm", "--cached", "BM/generated/Client.swift")
            value = "ghp_" + "z" * 36
            (repo / "BM/Hidden.swift").write_text('let key = "' + value + '"')
            git("add", "BM/Hidden.swift")
            result = git("commit", "-m", "2026.10.19 검사 작업 수행")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"github-token", result.stderr)
            self.assertNotIn(value.encode(), result.stderr)
            git("rm", "--cached", "BM/Hidden.swift")
            self.assertNotEqual(git("commit", "-m", "wrong format").returncode, 0)
            self.assertEqual(git("commit", "-m", "2026.10.19 검사 작업 수행").returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
