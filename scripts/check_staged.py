#!/usr/bin/env python3
"""Inspect staged blobs, including forced additions; never print matched values."""
from pathlib import PurePosixPath
import re
import subprocess
import sys

EXACT_PATHS = {
    ".gitignore", ".gitattributes", "AGENTS.md", "README.md",
    "BM/Resources/schools.json", "BM.xcodeproj/project.pbxproj",
    "BM.xcodeproj/xcshareddata/xcschemes/BM.xcscheme",
    ".githooks/pre-commit", ".githooks/commit-msg",
    "scripts/check_staged.py", "scripts/check_commit_message.py", "scripts/test_git_security.py",
}
BLOCKED_PARTS = {"secrets", "credentials", ".ssh", ".aws", ".idea", ".vscode", "xcuserdata", "__pycache__"}
PATTERNS = [
    ("private-key", re.compile(r"-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----")),
    ("github-token", re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b")),
    ("aws-access-id", re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")),
    ("google-api-key", re.compile(r"\bAIza[A-Za-z0-9_-]{35}\b")),
    ("jwt-literal", re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b")),
    ("credential-literal", re.compile(r'''(?i)(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|passwd|secret[_-]?key|authorization)\s*[:=]\s*["'][^"'\n]{8,}["']''')),
    ("credential-url", re.compile(r"https?://[^/\s:@]+:[^/\s@]+@")),
    ("personal-home-path", re.compile("/" + "Users" + r"/[^/\s]+/|[A-Za-z]:\\" + r"Users\\[^\\\s]+\\")),
    ("signing-team", re.compile(r'''DEVELOPMENT_TEAM\s*=\s*["']?[A-Z0-9]{10}\b''')),
    ("email-address", re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")),
]


def allowed_path(path: str) -> bool:
    parts = PurePosixPath(path).parts
    if any(part.lower() in BLOCKED_PARTS or part.lower().startswith(".env") for part in parts):
        return False
    if path in EXACT_PATHS:
        return True
    return len(parts) > 1 and parts[0] in {"BM", "BMTests", "BMUITests"} and path.endswith(".swift")


def content_issues(data: bytes) -> list[str]:
    if b"\0" in data:
        return ["binary-content"]
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return ["non-utf8-content"]
    return [label for label, pattern in PATTERNS if pattern.search(text)]


def git(*args: str) -> bytes:
    return subprocess.check_output(["git", *args])


def main() -> int:
    names = git("diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z").split(b"\0")
    failures = []
    count = 0
    for raw in filter(None, names):
        path = raw.decode("utf-8", errors="surrogateescape")
        count += 1
        if not allowed_path(path):
            failures.append((path, "not-in-source-allowlist"))
            continue
        mode = git("ls-files", "--stage", "--", path).split(b" ", 1)[0]
        if mode not in {b"100644", b"100755"}:
            failures.append((path, "non-regular-file"))
            continue
        for issue in content_issues(git("cat-file", "blob", ":" + path)):
            failures.append((path, issue))
    # A local-only .gitconfig value keeps personal email out of commit metadata.
    for kind in ["AUTHOR", "COMMITTER"]:
        identity = git("var", "GIT_" + kind + "_IDENT").decode("utf-8")
        address = re.search(r"<([^>]+)>", identity)
        if not address or not address[1].endswith("@users.noreply.github.com"):
            failures.append(("commit-metadata", kind.lower() + "-email-is-not-github-noreply"))
    if failures:
        for path, reason in failures:
            print(f"차단: {path} [{reason}]", file=sys.stderr)
        print("민감 값은 출력하지 않았습니다. 원본 대신 로컬 설정/환경 변수를 사용하세요.", file=sys.stderr)
        return 1
    print(f"Staged source/privacy checks passed ({count} files).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
