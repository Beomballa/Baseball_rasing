#!/usr/bin/env python3
"""Inspect staged blobs, including forced additions; never print matched values."""
from pathlib import PurePosixPath
import re
import hashlib
import subprocess
import sys

EXACT_PATHS = {
    "BM/Resources/PrivacyInfo.xcprivacy",
    ".gitignore", ".gitattributes", "AGENTS.md", "README.md", "docs/implementation-history.md",
    "BM/Resources/schools.json", "BM.xcodeproj/project.pbxproj",
    "BM.xcodeproj/xcshareddata/xcschemes/BM.xcscheme",
    ".githooks/pre-commit", ".githooks/commit-msg",
    "scripts/preview_field_sprites.html", "scripts/test_field_sprites.py",
    "BM/Resources/MatchArt/fielders-v1.json", "BM/Resources/MatchArt/field-runtime-v1.json",
    "BM.xcodeproj/xcshareddata/xcschemes/BM-QA.xcscheme",
    "BM/Resources/Assets.xcassets/Contents.json",
    "BM/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
    "BM/Resources/Assets.xcassets/AppIconQA.appiconset/Contents.json",
    "scripts/check_staged.py", "scripts/check_commit_message.py", "scripts/test_git_security.py",
    "scripts/summarize_match_rendering.py", "scripts/test_match_rendering_summary.py",
}
ART_HASHES = {'BM/Resources/MatchArt/opponent-avatar-v1.png': '7ce1e3b33f8d5a0ead0e9eab213876ecf62b84e2a1e1d04dee842807af679113', 'BM/Resources/MatchArt/catcher-run-v1.png': '523550cbfca1545bfcdd52ac317229f54038b07b16b7adfe05830b06f0ab1f33', 'BM/Resources/MatchArt/fielder-transfer-v1.png': '81fd4b58749b45974e660a7b81ae128011189342bee179b26a70d1cc44e85598', 'BM/Resources/MatchArt/fielder-misplay-v1.png': '3e46024ed110111963abf08300d55d7270a16e2865509c6146324c66c2b644f2', 'BM/Resources/MatchArt/catcher-misplay-v1.png': '9369db3e85c227baad45aff94b336f48a998e08125a28b61438e92559ab309ad', 'BM/Resources/MatchArt/runner-arrival-v1.png': '6c25784396f1b1dd4fe79d6793776f4af625519e0e4ad58de47c4eb83ba82eae', 'BM/Resources/MatchArt/fielder-arrival-v1.png': '3e604efcb3726d69b215a9eb4d70d2bd6f15b2a0cc87546b291b359dc954be2a', 'BM/Resources/MatchArt/catcher-arrival-v1.png': 'beca9b25f9db1fafc5e3813a3d3e6c4e54114d40f210bb4d52b3263a5956498b', 'BM/Resources/MatchArt/catcher-catch-v1.png': 'cd4b49984ae6d7cb1cae86b1c5681e2740f1b7276909a46334f0c21990506b78', 'BM/Resources/MatchArt/catcher-gather-v1.png': '99bdcfea6ae54835a3bad9124da8f9cd42558155e82327595e5ab63667b6e8d5', 'BM/Resources/MatchArt/catcher-ready-v1.png': '2bf3b0111abf716e750f97d4b14559234086bfab81ad3c8fc5de39994def8440', 'BM/Resources/MatchArt/catcher-release-v1.png': 'a7007f77c29a2276b7f78e66314a806faed69217e51c3d226db8a9216a6dc9e3', 'BM/Resources/MatchArt/catcher-windup-v1.png': 'eccba6f626664fb04c8379dd762048a29c54763c22fe4141a990df348934fdfc', 'BM/Resources/MatchArt/fielder-air-v1.png': '4630ddd3133c045909d2fe45835aa479423326165e2a03a27eae821b61394090', 'BM/Resources/MatchArt/runner-ready-v1.png': '433da2684d3c6b409a745144ef005abefbcc1c72dd424be42b79784d4c84ee51', 'BM/Resources/MatchArt/runner-run-a-v1.png': 'e330f547fb6287b308fc0afc86946e112ccde510ead42fdd33b9a6331009c7d5', 'BM/Resources/MatchArt/runner-run-b-v1.png': '1adc9660ed67bca1e1f03addb141266bb92ae82005cc34430ef16c8b8a83f914', 'BM/Resources/MatchArt/fielder-e-v1.png': '1d7cdf3c492e0105d6bd8a56e59273a428bbadd9452f1874f80da9bb725e51b8', 'BM/Resources/MatchArt/fielder-n-v1.png': 'ed369a4bf9541d0937b82a648535e71f0ace3b7856ddcfedfbac749ae881d453', 'BM/Resources/MatchArt/fielder-ne-v1.png': 'fb3b7c8d1a34d771b1192e3f79fe0c571bebed3d3c2a3219c7090357d004f1b0', 'BM/Resources/MatchArt/fielder-nw-v1.png': 'c619c4fb55175aa0f691a504abae54f90b34289bd530fea5251dc82167241aad', 'BM/Resources/MatchArt/fielder-s-v1.png': '63acd6d8099ce77c336a4d6c054070e21b7a864f5b0d1e51c0c923386e3ebe3f', 'BM/Resources/MatchArt/fielder-se-v1.png': '12bab5777ebc7aca5309a92049620901699f1235a24d357c93d166b4c6f60966', 'BM/Resources/MatchArt/fielder-sw-v1.png': 'df90ccad9a4712c74d6b8d2e2771cd38b96db5edd4ce1876689f727667fc8953', 'BM/Resources/MatchArt/fielder-w-v1.png': 'c3379d650728f5abeb4d1cb52fe40f4507faa9d6bdf4e21fabc37418dd00bdf0', 'BM/Resources/MatchArt/inplay-stadium-arcade-v1.png': '88f437ed3272eaf621d3cb58072c197c6d1b1e524e9817791f4ea33c21af73ef', 'BM/Resources/MatchArt/inplay-stadium-sunset-v1.png': '99729c4289b1dcf763cc1320713488041d4cedcb38de470b4160cb1bca82dec6', 'BM/Resources/MatchArt/scout-office-v1.png': '2a7fa75c3ee3f1196459eb424a89a3d18c0f1732d4ca49d002838c5ab1e351fa', 'BM/Resources/MatchArt/batter-actions.png': '0b354869384a10785639dda556adebf9f11a587b73b0be31d80456e5d57310cf', 'BM/Resources/MatchArt/batter-view-clean.png': 'b2fcd03304f72554e80c34510dc7d4b3920e70c389ef9c4c8a6cc145b6bcddff', 'BM/Resources/MatchArt/catcher-parts.png': '6692da8e7cce7aacad190d561c202216772e5b00eaabb3694e951d849e5f60b9', 'BM/Resources/MatchArt/grip-changeup.png': 'f5bbbe6e35cb8d2334faf6741e4d4a6481ce4b65c8e6a28475a44ea0dcdf8e31', 'BM/Resources/MatchArt/grip-fastball.png': '0bba0ab9e03bf7e9c692067a1300233c464f6dfc0acea063a4bbf6a382e2286c', 'BM/Resources/MatchArt/grip-slider.png': '96c9d030c8e829abdd27ed85a175f3ef4035d619340f518738c1f5e9dc72455f', 'BM/Resources/MatchArt/grips-extra.png': '951a93adcff9fc9ed2dbc11a77754957ee077745709f552b6001ca23f91ada7d', 'BM/Resources/MatchArt/pitcher-delivery-v2.png': '10d16f1abb936751dbcb3ddaf428331062547b7fad5e983273920219e49d67dc', 'BM/Resources/MatchArt/stadium-clean.png': '5c977592c6d8caa69a567ecdd86dffdaf1d56eef858bb49571adbb0e82a392fb'}

# Individually reviewed normal and QA application artwork.
ART_HASHES.update({'BM/Resources/Assets.xcassets/AppIconQA.appiconset/AppIconQA.png': 'd7268e9dbf30d216574638782d616042b5f309b307c7225f8d1a581983a28f0f', 'BM/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png': 'ce3f1f1922c8b384d6c2170c7390b169bf9711b3e41db029e94d4edd11f52703'})
EXACT_PATHS.update({'BM/Resources/Assets.xcassets/BullpenRoomV62.imageset/Contents.json', 'BM/Resources/Assets.xcassets/StadiumRoomV62.imageset/Contents.json', 'BM/Resources/Assets.xcassets/BattingRoomV62.imageset/Contents.json'})
ART_HASHES.update({'BM/Resources/Assets.xcassets/BattingRoomV62.imageset/room.png': 'f1b8c2c71036db244b7f88608dd5f15c683a24370e3a97617bc615c19ccfbca6', 'BM/Resources/Assets.xcassets/BullpenRoomV62.imageset/room.png': 'e49490d20636bc456bd7ad8e4557fb307c444e98a4cac7b4e4e140e942d8f1e3', 'BM/Resources/Assets.xcassets/StadiumRoomV62.imageset/room.png': '2b50995cf1ea5e3fe264ac9073a9ef5f24fe40e71f3d4152b87bf9a783ae9270'})

# Reviewed management foundation assets; no other catalog files are allowed.
EXACT_PATHS.update({'BM/Resources/Assets.xcassets/ClubhouseV1.imageset/Contents.json', 'BM/Resources/Assets.xcassets/NavCareerV1.imageset/Contents.json', 'BM/Resources/Assets.xcassets/NavGameV1.imageset/Contents.json', 'BM/Resources/Assets.xcassets/NavTrainingV1.imageset/Contents.json', 'BM/Resources/Assets.xcassets/NavPlayerV1.imageset/Contents.json', 'BM/Resources/Assets.xcassets/NavHomeV1.imageset/Contents.json'})
ART_HASHES.update({'BM/Resources/Assets.xcassets/NavTrainingV1.imageset/icon-nav-training-v1-2x.png': '171b05f070a793664503b227ca4e51db0cad393fb85c044d01e17c33479322cb', 'BM/Resources/Assets.xcassets/NavTrainingV1.imageset/icon-nav-training-v1-3x.png': '76c643894fc781e43c6a781fc932db046a9a4b841a41d80c7f2213d5f3fd3b5c', 'BM/Resources/Assets.xcassets/NavPlayerV1.imageset/icon-nav-player-v1-2x.png': '61239e4e0971299ad49ae431cd4c82c2db668e5c255b18c20d5516c9ec8bc44b', 'BM/Resources/Assets.xcassets/NavPlayerV1.imageset/icon-nav-player-v1-3x.png': 'f9f0171c39098223520a8f55f2491ff8bcfdfbfca6226bcdb914f98b9d010d12', 'BM/Resources/Assets.xcassets/NavGameV1.imageset/icon-nav-game-v1-2x.png': 'f13cfa899c61c0f7f8bf2e4041af570bd85190d8fe4a1c6135f34bf6f793c4dc', 'BM/Resources/Assets.xcassets/NavGameV1.imageset/icon-nav-game-v1-3x.png': '109c2099332feb296bd298c43922bdd30dbdbe1f7a9b35eac65a77d8eae64338', 'BM/Resources/Assets.xcassets/NavCareerV1.imageset/icon-nav-career-v1-2x.png': '6aacb7d2328af79d2a88760a7aa6f3cf79c5aa920942ceb295c1e08770692405', 'BM/Resources/Assets.xcassets/NavCareerV1.imageset/icon-nav-career-v1-3x.png': 'fdfbb81e67dbf5307630274402e572415e9a21d048a3804f142b2b3463516236', 'BM/Resources/Assets.xcassets/NavHomeV1.imageset/icon-nav-home-v1-3x.png': 'f1c9c20e95d742bb20b47370a16ce92c578350597a016c9ed967c82197030eca', 'BM/Resources/Assets.xcassets/NavHomeV1.imageset/icon-nav-home-v1-2x.png': '9b2ef40e7d357e520a3b1c7dcbc21408805625ddcc64fd93e34befc42416e026', 'BM/Resources/Assets.xcassets/ClubhouseV1.imageset/bg-clubhouse-v1.png': 'c8efb71636b01558ca0fa53f5c6dd47f12e917804add68684b10b7ab6f5ff986'})

EXACT_PATHS.update({'BM/Resources/Assets.xcassets/LockerV1.imageset/Contents.json', 'BM/Resources/Assets.xcassets/BattingRoomV1.imageset/Contents.json', 'BM/Resources/Assets.xcassets/BullpenRoomV1.imageset/Contents.json'})
ART_HASHES.update({'BM/Resources/Assets.xcassets/LockerV1.imageset/bg-locker-v1.png': 'c108413ae9da738bbb65ffa980833db965f68927703649303b9f380f71d1b889', 'BM/Resources/Assets.xcassets/BattingRoomV1.imageset/bg-batting-room-v1.png': '0eb041bd665f475c6803861c20ba390751cb0243180202ca2ffc32bbc9477533', 'BM/Resources/Assets.xcassets/BullpenRoomV1.imageset/bg-bullpen-room-v1.png': '5600ff83371532b39af75c369f65a498a7081fc16431fa51466397489dfaeef9'})

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


EXACT_PATHS.update({"BM/Resources/Assets.xcassets/StadiumGateV1.imageset/Contents.json"})
ART_HASHES.update({"BM/Resources/Assets.xcassets/StadiumGateV1.imageset/bg-stadium-gate-v1.png":"e6c1be9d916a59e9c40e4f3b10f33612589bfd4d40e98afe186c54ce78c288b8"})

EXACT_PATHS.update({'BM/Resources/Assets.xcassets/RestRoomV1.imageset/Contents.json', 'BM/Resources/Assets.xcassets/ScoutRoomV1.imageset/Contents.json'})
ART_HASHES.update({'BM/Resources/Assets.xcassets/ScoutRoomV1.imageset/bg-scout-room-v1.png': 'dc0c5b15e2882e714be8fcce4c6c159d1f4ad7c9dbb9d0ed6874afbbb42d42e2', 'BM/Resources/Assets.xcassets/RestRoomV1.imageset/bg-rest-room-v1.png': '2ba4fb3d9192e59d28339286be05e4809fe6059bd4333de5bdd356c67e122d66'})

# Reviewed unlettered V17 room backgrounds.
EXACT_PATHS.update({'BM/Resources/Assets.xcassets/RestRoomV2.imageset/Contents.json', 'BM/Resources/Assets.xcassets/BattingRoomV2.imageset/Contents.json', 'BM/Resources/Assets.xcassets/LockerRoomV2.imageset/Contents.json', 'BM/Resources/Assets.xcassets/StadiumRoomV2.imageset/Contents.json', 'BM/Resources/Assets.xcassets/ClubhouseRoomV2.imageset/Contents.json', 'BM/Resources/Assets.xcassets/BullpenRoomV2.imageset/Contents.json', 'BM/Resources/Assets.xcassets/ScoutRoomV2.imageset/Contents.json'})
ART_HASHES.update({'BM/Resources/Assets.xcassets/ClubhouseRoomV2.imageset/room.png': '452d5952825dd846090301672084ca8ffd11dd63b6bf62cc46411d3e5bf42362', 'BM/Resources/Assets.xcassets/LockerRoomV2.imageset/room.png': '76762907adadd6bbb168fb7180ebebbe6a212a13956f89e2e62e7a576de7e5c8', 'BM/Resources/Assets.xcassets/BattingRoomV2.imageset/room.png': '6886c540590aea8e0a310b3c11b5280966d18d6cbc19f720395d6db2f4a46252', 'BM/Resources/Assets.xcassets/BullpenRoomV2.imageset/room.png': 'a8577bd6550b407c9b3e8654f284ca36ac4404c70a17f42ab7833c4239c4c2b3', 'BM/Resources/Assets.xcassets/StadiumRoomV2.imageset/room.png': 'fa4a954937579cb7e6fbc991aebf4d9c294ebfa544144f247ff911d5c34dc666', 'BM/Resources/Assets.xcassets/ScoutRoomV2.imageset/room.png': '3093d6f933a182b78c1b2b6067ef29cf188044f7c575525df93b8a025cf28fe8', 'BM/Resources/Assets.xcassets/RestRoomV2.imageset/room.png': 'a38a3554e4ccaeff4c0089aa296a3131755ae4cb3ee18f4f8a5f1c7862844107'})

# V51 original unlettered practice environments and transparent tee prop.
ART_HASHES.update({'BM/Resources/MatchArt/training-environments-v51.png': 'd24db8aec23b203258f4a33dc5cf8120d12d828764f9ecad5bea4fbed4a04bf4', 'BM/Resources/MatchArt/training-tee-v51.png': '4c982b5b8cd5d2870d7cb0ca484ec5fe9082cfbf5fef958ad414b02b41887d66'})

# V52 original separated gameplay backgrounds and opponent motion atlases.
ART_HASHES.update({'BM/Resources/MatchArt/batter-field-v52.png': 'eed2ed3029d972bedec8f8ff93f2e97de2ae32b4ebbf426425d949e367aae9b5', 'BM/Resources/MatchArt/pitcher-field-v52.png': '5903dc03813a6b1ff62463d1f4a9a8d13e69627d954b38132b4a545c2920c2e2', 'BM/Resources/MatchArt/opponent-pitcher-v52.png': '30674d027a7ca42a645e2c4de602d4de478b3203e9cd051f1e7132e1c7f35b3c', 'BM/Resources/MatchArt/opponent-batter-v52.png': '5a80ba6d7366eac47f3188ffad0dbb52b37c8650094d129a3ec24c948bcdd2b5'})

# Individually reviewed V60 room assets and official OFL distribution files.
EXACT_PATHS.update({'BM/Resources/Assets.xcassets/ManagementPixelFontV59.dataset/Contents.json', 'BM/Resources/Assets.xcassets/ClubhouseRoomV59.imageset/Contents.json', 'BM/Resources/Assets.xcassets/LockerRoomV59.imageset/Contents.json', 'BM/Resources/Assets.xcassets/ManagementPixelLicenseV59.dataset/Contents.json', 'BM/Resources/Assets.xcassets/ScoutRoomV59.imageset/Contents.json'})
ART_HASHES.update({'BM/Resources/Assets.xcassets/ClubhouseRoomV59.imageset/room.png': 'af30b326fc4530bfcbf7ce91a7196dc4f6e991c6dabf90a5aa95a5536cc8f97d', 'BM/Resources/Assets.xcassets/LockerRoomV59.imageset/room.png': '866705e794460649530359412d71d3b7cfba08570139545b8bea18261fa78be3', 'BM/Resources/Assets.xcassets/ScoutRoomV59.imageset/room.png': 'a87c7544c89145456010d7d01d4be40b430e2fc8226a098a3d1399dee46c5a23', 'BM/Resources/Assets.xcassets/ManagementPixelFontV59.dataset/neodgm.ttf': '77305267996073aae07bad9313dad2e306a4128e55bfafbed4c41558fee57b4d', 'BM/Resources/Assets.xcassets/ManagementPixelLicenseV59.dataset/OFL.txt': '4d3155f4caba9970c8b386064b398822c29d9181cfba07964ba7b07ccc6cca91'})

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
