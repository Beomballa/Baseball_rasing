#!/usr/bin/env python3
"""Inspect staged blobs, including forced additions; never print matched values."""
from pathlib import PurePosixPath
import re
import hashlib
import subprocess
import sys

EXACT_PATHS = {
    ".gitignore", ".gitattributes", "AGENTS.md", "README.md",
    "BM/Resources/schools.json", "BM.xcodeproj/project.pbxproj",
    "BM.xcodeproj/xcshareddata/xcschemes/BM.xcscheme",
    ".githooks/pre-commit", ".githooks/commit-msg",
    "scripts/check_staged.py", "scripts/check_commit_message.py", "scripts/test_git_security.py",
}
ART_HASHES = {'BM/Resources/MatchArt/inplay-stadium-arcade-v1.png': '88f437ed3272eaf621d3cb58072c197c6d1b1e524e9817791f4ea33c21af73ef', 'BM/Resources/MatchArt/inplay-stadium-sunset-v1.png': '99729c4289b1dcf763cc1320713488041d4cedcb38de470b4160cb1bca82dec6', 'BM/Resources/MatchArt/scout-office-v1.png': '2a7fa75c3ee3f1196459eb424a89a3d18c0f1732d4ca49d002838c5ab1e351fa', 'BM/Resources/MatchArt/batter-actions.png': '0b354869384a10785639dda556adebf9f11a587b73b0be31d80456e5d57310cf', 'BM/Resources/MatchArt/batter-view-clean.png': 'b2fcd03304f72554e80c34510dc7d4b3920e70c389ef9c4c8a6cc145b6bcddff', 'BM/Resources/MatchArt/catcher-parts.png': '6692da8e7cce7aacad190d561c202216772e5b00eaabb3694e951d849e5f60b9', 'BM/Resources/MatchArt/grip-changeup.png': 'f5bbbe6e35cb8d2334faf6741e4d4a6481ce4b65c8e6a28475a44ea0dcdf8e31', 'BM/Resources/MatchArt/grip-fastball.png': '0bba0ab9e03bf7e9c692067a1300233c464f6dfc0acea063a4bbf6a382e2286c', 'BM/Resources/MatchArt/grip-slider.png': '96c9d030c8e829abdd27ed85a175f3ef4035d619340f518738c1f5e9dc72455f', 'BM/Resources/MatchArt/grips-extra.png': '951a93adcff9fc9ed2dbc11a77754957ee077745709f552b6001ca23f91ada7d', 'BM/Resources/MatchArt/pitcher-delivery-v2.png': '10d16f1abb936751dbcb3ddaf428331062547b7fad5e983273920219e49d67dc', 'BM/Resources/MatchArt/stadium-clean.png': '5c977592c6d8caa69a567ecdd86dffdaf1d56eef858bb49571adbb0e82a392fb'}

BLOCKED_PARTS = {"secrets", "credentials", ".ssh", ".aws", ".idea", ".vscode", "xcuserdata", "__pycache__", "generated"}
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
    if path in EXACT_PATHS or path in ART_HASHES:
        return True
    return (len(parts) > 1 and parts[0] in {"BM", "BMTests", "BMUITests"}
            and not any(part.startswith(".") for part in parts[1:-1])
            and path.endswith(".swift"))


def content_issues(data: bytes) -> list[str]:
    if b"\0" in data:
        return ["binary-content"]
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return ["non-utf8-content"]
    return [label for label, pattern in PATTERNS if pattern.search(text)]


def blob_issues(path: str, data: bytes) -> list[str]:
    if path in ART_HASHES:
        return [] if hashlib.sha256(data).hexdigest() == ART_HASHES[path] else ["unreviewed-game-art"]
    return content_issues(data)


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
        for issue in blob_issues(path, git("cat-file", "blob", ":" + path)):
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
