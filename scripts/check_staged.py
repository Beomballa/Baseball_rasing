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

# V120 선택한 전신 원화와 재질/접지 정보. 실제 렌더 회귀와 원본을 로컬 QA에 보존한다.
ART_HASHES.update({'BM/Resources/MatchArt/pitcher-fullbody-v123.json': '7b5b3c34a90a647db6f323fbdb30c3d31957f619ceb97dd106788492f20a00d0'})
ART_HASHES.update({
    "BM/Resources/MatchArt/pitcher-fullbody-v124.json": "a181423d3e9f2df294fb159049e027858a56a538a7c9888446f5938d592ca23a",
    "BM/Resources/MatchArt/pitcher-depth-back-v124.png": "e58bb01a7876dd1d3c6fea9cb9aee7ed004057d2d04f1c8673322119a6b559d5",
})
ART_HASHES.update({
    'BM/Resources/MatchArt/pitcher-delivery-back-v143.json': '9cd75ed0a3307db8fc684ac9749132763a415d4dff5eb50131aa4c816bf67f25',
    'BM/Resources/MatchArt/pitcher-delivery-back-v143.png': '9a9d64762b549e84bcbffb24a6f059d4d535677fffdac655a6b69669a0dbf1b3',
    'BM/Resources/MatchArt/pitcher-delivery-back-v161.json': 'db82ad2de85b33dff7008bb8534bab646f6071f4156fa0d3f75f9f50ecf082f1',
    'BM/Resources/MatchArt/pitcher-delivery-back-v161.png': 'b5a268402110b111ccc0f5a4e677bd0df0f544412b45e80609bd7d771e133f09',
    'BM/Resources/MatchArt/pitcher-delivery-back-v171.json': 'ea93a7f01302c85a80bbcabd3d0b3ba3805f9c4cffd8c1ebf566dde9f46bd764',
    'BM/Resources/MatchArt/pitcher-delivery-back-v171.png': 'f25b8363d5a17c30adc854a27a3d789b3997e8a4549c56ea91fbcd112f503e36',
    'BM/Resources/MatchArt/pitcher-delivery-back-v171-prep-midpoints.json': '5fe3a92f993125cb245e6da9642bf810c1dbaf26edcbb50d708029afb8d1fc18',
    'BM/Resources/MatchArt/pitcher-delivery-back-v171-prep-midpoints.png': '01a979cdb9bcba17095c7bb88e5b1fef1d7431a750e1a809957ba3a813e4a8f1',
})
ART_HASHES.update({'BM/Resources/MatchArt/pitcher-fullbody-back-v120.png': 'e93eb19dec38889f77b63cc23042601964adb0205ce3b617b8a15f360d2489a3', 'BM/Resources/MatchArt/pitcher-fullbody-front-v120.png': '71c264acda0c3062e5923476c63968f96c1abdb9270a8ec646ebfc82ea6e086d', 'BM/Resources/MatchArt/pitcher-fullbody-v120.json': 'ae2eec9caa0a00b2d0a871950f78579bda03f26044c74257e76b5c49524ff294'})

# Individually reviewed normal and QA application artwork.
ART_HASHES.update({'BM/Resources/Assets.xcassets/AppIconQA.appiconset/AppIconQA.png': 'd7268e9dbf30d216574638782d616042b5f309b307c7225f8d1a581983a28f0f', 'BM/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png': 'ce3f1f1922c8b384d6c2170c7390b169bf9711b3e41db029e94d4edd11f52703'})
EXACT_PATHS.update({'BM/Resources/Assets.xcassets/BullpenRoomV62.imageset/Contents.json', 'BM/Resources/Assets.xcassets/StadiumRoomV62.imageset/Contents.json', 'BM/Resources/Assets.xcassets/BattingRoomV62.imageset/Contents.json'})
ART_HASHES.update({'BM/Resources/Assets.xcassets/BattingRoomV62.imageset/room.png': 'f1b8c2c71036db244b7f88608dd5f15c683a24370e3a97617bc615c19ccfbca6', 'BM/Resources/Assets.xcassets/BullpenRoomV62.imageset/room.png': 'e49490d20636bc456bd7ad8e4557fb307c444e98a4cac7b4e4e140e942d8f1e3', 'BM/Resources/Assets.xcassets/StadiumRoomV62.imageset/room.png': '2b50995cf1ea5e3fe264ac9073a9ef5f24fe40e71f3d4152b87bf9a783ae9270'})

# V83 original generated stadium interior, reviewed with native overlays.
EXACT_PATHS.add('BM/Resources/Assets.xcassets/StadiumInteriorV86.imageset/Contents.json')
ART_HASHES['BM/Resources/Assets.xcassets/StadiumInteriorV86.imageset/stadium.png'] = '800699a27cdb9a649e8a5905b149347fd9b5c05847790178b42bd798869309c9'
EXACT_PATHS.add('BM/Resources/Assets.xcassets/StadiumInteriorV83.imageset/Contents.json')
ART_HASHES['BM/Resources/Assets.xcassets/StadiumInteriorV83.imageset/stadium.png'] = '0cb0a6c580a7e18aeea1dcd50440d90babdcc217c9d191ddb1b92191b8f0ab49'

# Reviewed management foundation assets; no other catalog files are allowed.
EXACT_PATHS.update({'BM/Resources/Assets.xcassets/ClubhouseV1.imageset/Contents.json', 'BM/Resources/Assets.xcassets/NavCareerV1.imageset/Contents.json', 'BM/Resources/Assets.xcassets/NavGameV1.imageset/Contents.json', 'BM/Resources/Assets.xcassets/NavTrainingV1.imageset/Contents.json', 'BM/Resources/Assets.xcassets/NavPlayerV1.imageset/Contents.json', 'BM/Resources/Assets.xcassets/NavHomeV1.imageset/Contents.json'})
ART_HASHES.update({'BM/Resources/Assets.xcassets/NavTrainingV1.imageset/icon-nav-training-v1-2x.png': '171b05f070a793664503b227ca4e51db0cad393fb85c044d01e17c33479322cb', 'BM/Resources/Assets.xcassets/NavTrainingV1.imageset/icon-nav-training-v1-3x.png': '76c643894fc781e43c6a781fc932db046a9a4b841a41d80c7f2213d5f3fd3b5c', 'BM/Resources/Assets.xcassets/NavPlayerV1.imageset/icon-nav-player-v1-2x.png': '61239e4e0971299ad49ae431cd4c82c2db668e5c255b18c20d5516c9ec8bc44b', 'BM/Resources/Assets.xcassets/NavPlayerV1.imageset/icon-nav-player-v1-3x.png': 'f9f0171c39098223520a8f55f2491ff8bcfdfbfca6226bcdb914f98b9d010d12', 'BM/Resources/Assets.xcassets/NavGameV1.imageset/icon-nav-game-v1-2x.png': 'f13cfa899c61c0f7f8bf2e4041af570bd85190d8fe4a1c6135f34bf6f793c4dc', 'BM/Resources/Assets.xcassets/NavGameV1.imageset/icon-nav-game-v1-3x.png': '109c2099332feb296bd298c43922bdd30dbdbe1f7a9b35eac65a77d8eae64338', 'BM/Resources/Assets.xcassets/NavCareerV1.imageset/icon-nav-career-v1-2x.png': '6aacb7d2328af79d2a88760a7aa6f3cf79c5aa920942ceb295c1e08770692405', 'BM/Resources/Assets.xcassets/NavCareerV1.imageset/icon-nav-career-v1-3x.png': 'fdfbb81e67dbf5307630274402e572415e9a21d048a3804f142b2b3463516236', 'BM/Resources/Assets.xcassets/NavHomeV1.imageset/icon-nav-home-v1-3x.png': 'f1c9c20e95d742bb20b47370a16ce92c578350597a016c9ed967c82197030eca', 'BM/Resources/Assets.xcassets/NavHomeV1.imageset/icon-nav-home-v1-2x.png': '9b2ef40e7d357e520a3b1c7dcbc21408805625ddcc64fd93e34befc42416e026', 'BM/Resources/Assets.xcassets/ClubhouseV1.imageset/bg-clubhouse-v1.png': 'c8efb71636b01558ca0fa53f5c6dd47f12e917804add68684b10b7ab6f5ff986'})

EXACT_PATHS.update({'BM/Resources/Assets.xcassets/LockerV1.imageset/Contents.json', 'BM/Resources/Assets.xcassets/BattingRoomV1.imageset/Contents.json', 'BM/Resources/Assets.xcassets/BullpenRoomV1.imageset/Contents.json'})
ART_HASHES.update({'BM/Resources/Assets.xcassets/LockerV1.imageset/bg-locker-v1.png': 'c108413ae9da738bbb65ffa980833db965f68927703649303b9f380f71d1b889', 'BM/Resources/Assets.xcassets/BattingRoomV1.imageset/bg-batting-room-v1.png': '0eb041bd665f475c6803861c20ba390751cb0243180202ca2ffc32bbc9477533', 'BM/Resources/Assets.xcassets/BullpenRoomV1.imageset/bg-bullpen-room-v1.png': '5600ff83371532b39af75c369f65a498a7081fc16431fa51466397489dfaeef9'})

EXACT_PATHS.add("BM/Resources/Assets.xcassets/GameUniformStylesV104.dataset/Contents.json")
ART_HASHES["BM/Resources/Assets.xcassets/GameUniformStylesV104.dataset/kits.json"] = "c5dc5e3b653712a0006bb69061889b340b3df34d11fa2a86717b4e0547984a0e"

BLOCKED_PARTS = {"secrets", "credentials", ".ssh", ".aws", ".idea", ".vscode", "xcuserdata", "__pycache__", "generated"}
# Reviewed V91 standalone, unlettered header portrait.
EXACT_PATHS.add("BM/Resources/Assets.xcassets/PlayerPortraitV91.imageset/Contents.json")
ART_HASHES["BM/Resources/Assets.xcassets/PlayerPortraitV91.imageset/player-portrait.png"] = "a4c55d90e068630181d0cfc6426ed4c6ef357ab90a0e6c92d9c64a1d14722fde"

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

EXACT_PATHS.update({'BM/Resources/Assets.xcassets/RestBenchV67.imageset/Contents.json', 'BM/Resources/Assets.xcassets/GameDugoutV67.imageset/Contents.json'})
ART_HASHES.update({'BM/Resources/Assets.xcassets/RestBenchV67.imageset/room.png': 'ac353dcb72560a2a2a25bc399c743534c5ef0e1658ae797b7af8a8c49daf69f4', 'BM/Resources/Assets.xcassets/GameDugoutV67.imageset/room.png': '800cb87d289ab9b7bc6eb643be123d6c83dc0d5ef692b30aedb94b73f3dc43cd'})

EXACT_PATHS.add('BM/Resources/Assets.xcassets/RestBenchV69.imageset/Contents.json')
ART_HASHES['BM/Resources/Assets.xcassets/RestBenchV69.imageset/room.png'] = '24b8760b17d7b43155e7d987b234cefd37e12b0b026c54ab7a2f6b5ec98e6bb1'

# V75 reviewed training and player motion artwork.
ART_HASHES.update({'BM/Resources/MatchArt/batter-actions-v75.png': '495d460d405eeea31419c1b6f3223c0a5ae3fa5d0265e2e74c5a1e5cb86eba5c', 'BM/Resources/MatchArt/pitcher-delivery-v75.png': '5c5d19bd692776c691ec47c9fad81e92571fe12a572a811c1de8c7034969cd3e', 'BM/Resources/MatchArt/batting-practice-v75.png': '4304ab31aaf4d7764a0d3d7341e5be09f7c6e0ad8c712aafa8745ae7e0d87068'})
ART_HASHES['BM/Resources/MatchArt/opponent-batter-v116.png'] = '5ea509c981dc72727c577043a69cdfe2400914d6b699442b66a402b5aa4e0573'

# V166 reviewed modular management portraits and standalone umpire.
EXACT_PATHS.add("docs/management-ui-v166.md")
ART_HASHES.update({'BM/Resources/Assets.xcassets/ManagementHeadsV166.imageset/image.png': 'c6e881e3e0263a738a995d09ba61f3386212ab946e4008a31f118d07868feb9a', 'BM/Resources/Assets.xcassets/ManagementFeaturesV166.imageset/image.png': '4a421f399ad8516b5db77f512bb820c471aafaddc973a4363a56f29775a6ec5d', 'BM/Resources/MatchArt/umpire-isolated-v166.png': '6647a946a376c7edd596e502504c0de289b4b1d774e8ce99e8d49f995b815b8e'})
EXACT_PATHS.update({'BM/Resources/Assets.xcassets/ManagementFeaturesV166.imageset/Contents.json', 'BM/Resources/Assets.xcassets/ManagementHeadsV166.imageset/Contents.json'})
EXACT_PATHS.add("BM/Resources/Assets.xcassets/ManagementPortraitReferenceV167.imageset/Contents.json")
ART_HASHES["BM/Resources/Assets.xcassets/ManagementPortraitReferenceV167.imageset/image.png"] = "dfdea7a78f410d8359e06fe5d7fab8c70608f2a0bd9e5c11213953571014e02a"
# 승인한 V167 상반신 조합 시트만 허용하며 개인 이미지 경로는 열지 않는다.
EXACT_PATHS.add("BM/Resources/Assets.xcassets/ManagementPortraitPartsV202.imageset/Contents.json")
ART_HASHES["BM/Resources/Assets.xcassets/ManagementPortraitPartsV202.imageset/image.png"] = "e31307aa4782e1ad8d5290ded56026259ebf32fca53d006276e3a6b5757e4ff7"

# V79 generated club logos reviewed in design_V79; no wildcard binary permission.
EXACT_PATHS.update({'BM/Resources/Assets.xcassets/Club-kbo-0.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-kbo-1.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-kbo-2.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-kbo-3.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-kbo-4.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-kbo-5.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-kbo-6.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-kbo-7.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-kbo-8.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-kbo-9.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-mlb-0.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-mlb-1.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-mlb-2.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-mlb-3.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-mlb-4.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-mlb-5.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-mlb-6.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-mlb-7.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-mlb-8.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-mlb-9.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-npb-0.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-npb-1.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-npb-2.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-npb-3.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-npb-4.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-npb-5.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-npb-6.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-npb-7.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-npb-8.imageset/Contents.json',
 'BM/Resources/Assets.xcassets/Club-npb-9.imageset/Contents.json'})
ART_HASHES.update({'BM/Resources/Assets.xcassets/Club-kbo-0.imageset/Club-kbo-0.png': '112a5fd620047e123bb460ff99734c037e4ab662c9c086a577b39fa47218c639',
 'BM/Resources/Assets.xcassets/Club-kbo-1.imageset/Club-kbo-1.png': '6f0a97a311071d4769490702aad5739bd8b9eb897abdf82c06b354a32eef61d1',
 'BM/Resources/Assets.xcassets/Club-kbo-2.imageset/Club-kbo-2.png': '1d4fc35c81966ef6bb0e06d3151431e8d43152c8d1295bdb14a03a5670af29ba',
 'BM/Resources/Assets.xcassets/Club-kbo-3.imageset/Club-kbo-3.png': '8681ba74bc27e7ebaf60b57517d4c84167d2f0a7719c43763b66654ceb469676',
 'BM/Resources/Assets.xcassets/Club-kbo-4.imageset/Club-kbo-4.png': '69e25f5cdb4d9e2751dc8fb3f9053a83cc2e1d62b753a17b82301aa35cf97f12',
 'BM/Resources/Assets.xcassets/Club-kbo-5.imageset/Club-kbo-5.png': '3556ac61d90fc4875c9c1e35ab8f2ba89a75ab989f5fe1cfe11cc1aa49d6b09f',
 'BM/Resources/Assets.xcassets/Club-kbo-6.imageset/Club-kbo-6.png': '8e810afaa267576ac9ce1d0de399ac7d8653a6f3aa48b7d0f4a2e69fe9527abd',
 'BM/Resources/Assets.xcassets/Club-kbo-7.imageset/Club-kbo-7.png': '4b120029da877593940d9cdd9072f9eaf0e15685e41a15181626c724fa39d914',
 'BM/Resources/Assets.xcassets/Club-kbo-8.imageset/Club-kbo-8.png': '6cb25941e7dcfb38fc272a5873ad80ffd5132251ff07858ea65d27494b4523dc',
 'BM/Resources/Assets.xcassets/Club-kbo-9.imageset/Club-kbo-9.png': 'b60e15ed005719b547362a5d9eacdec7d76a9e22f5b7c7a22d33e470330d8ddb',
 'BM/Resources/Assets.xcassets/Club-mlb-0.imageset/Club-mlb-0.png': 'a45f6f940633de15e9beec065eb3d48ca6072bdf72444a42801b51d2be3d0ea0',
 'BM/Resources/Assets.xcassets/Club-mlb-1.imageset/Club-mlb-1.png': '56b57d07d8547b087873264ebe089195db2fbce476a47a6989fce23f4886ad1c',
 'BM/Resources/Assets.xcassets/Club-mlb-2.imageset/Club-mlb-2.png': '37902cab66d5baf07a801638c702b52e23a79263e3abf6b05de7aa049d937ab6',
 'BM/Resources/Assets.xcassets/Club-mlb-3.imageset/Club-mlb-3.png': 'd49f11a0f345b1e53d5d435e35d13ad291cf2124b04015e4c6f94667897b052d',
 'BM/Resources/Assets.xcassets/Club-mlb-4.imageset/Club-mlb-4.png': 'b351897ace87621d6b2111b1bb917adb2344b8a12738bfde7834fc73dd24bef1',
 'BM/Resources/Assets.xcassets/Club-mlb-5.imageset/Club-mlb-5.png': '4b57006fac8bf90967d4b01d33310db46de74b5fe4ac957a2324f9453c51d0c0',
 'BM/Resources/Assets.xcassets/Club-mlb-6.imageset/Club-mlb-6.png': '5d0acfd13c95a2c2e91154fe7f2d10d1a8fe4c9091388fb89cb4172f2584a6f6',
 'BM/Resources/Assets.xcassets/Club-mlb-7.imageset/Club-mlb-7.png': '4c6149bab69b0fc8a4d0bed54abb69d15e6da8a46408a5cb15ea7c127553767e',
 'BM/Resources/Assets.xcassets/Club-mlb-8.imageset/Club-mlb-8.png': '2bd38c720e40283c3fd2d8212b74ef8ce3eea1b9defa70eb10842d9d7aeccf57',
 'BM/Resources/Assets.xcassets/Club-mlb-9.imageset/Club-mlb-9.png': 'a5cc731619fd78151a178498c48be8679bb0bb9e766cd617eaaa60258c64da67',
 'BM/Resources/Assets.xcassets/Club-npb-0.imageset/Club-npb-0.png': '89ee549bd989a48687b3cc8436e33e07be15db50858f61f9d4e64b4b77a6d328',
 'BM/Resources/Assets.xcassets/Club-npb-1.imageset/Club-npb-1.png': '1cbe957bbb4f5022c0bcca7e7d874de3776d601ccbfc78f043cc888ad6ba550e',
 'BM/Resources/Assets.xcassets/Club-npb-2.imageset/Club-npb-2.png': '0fcb038ba6597a71b7690d353d441281b455f83e74adc11703e39d796f21f7e0',
 'BM/Resources/Assets.xcassets/Club-npb-3.imageset/Club-npb-3.png': '703e07953c5128d07a35c5d95ae7be16be21e99981875604077e2da3714c0598',
 'BM/Resources/Assets.xcassets/Club-npb-4.imageset/Club-npb-4.png': 'b1f42a86fba3f047ec368ac0d83bb3cbf1535b79538e6f2dcbcadab7eb4d8e84',
 'BM/Resources/Assets.xcassets/Club-npb-5.imageset/Club-npb-5.png': '942752491733c201760194affa71192d268fb3e3ecf0d65a56ffe3a926f9818b',
 'BM/Resources/Assets.xcassets/Club-npb-6.imageset/Club-npb-6.png': '65a3e538087536bc0fac4bd6e9721a38440b6a213f209209b50d6fe71164a358',
 'BM/Resources/Assets.xcassets/Club-npb-7.imageset/Club-npb-7.png': '2fea3d96a9276eb25bc9111a053f429db537766b93f5584b29c3127bc22cb137',
 'BM/Resources/Assets.xcassets/Club-npb-8.imageset/Club-npb-8.png': '99182060ef956e67fa94401567526fac135fdb387a92b2dbb66c73d4c7f6aedb',
 'BM/Resources/Assets.xcassets/Club-npb-9.imageset/Club-npb-9.png': 'c30e2552ee844c75098765f7419994bcaee77ccc5bda65e7686567fbc82e1fdd'})

# V102 contains only catalog IDs and reviewed hex colors, no roster/save data.
EXACT_PATHS.update({"BM/Resources/Assets.xcassets/GameUniformColorsV102.dataset/Contents.json",
                    "BM/Resources/Assets.xcassets/GameUniformColorsV102.dataset/colors.json"})
EXACT_PATHS.add("BM/Resources/Assets.xcassets/ProUniformDesignsV148.dataset/Contents.json")
ART_HASHES["BM/Resources/Assets.xcassets/ProUniformDesignsV148.dataset/designs.json"] = "86d8ec2677eef60fc3820144d08bac96c2e57289b9c3383d875c1ff0ac8cbd91"

# V110/V113 licensed recordings grouped by function in V114; asset names/bytes unchanged.
EXACT_PATHS.add("BM/Resources/Assets.xcassets/Audio/Contents.json")
EXACT_PATHS.update({'BM/Resources/Assets.xcassets/Audio/BaseballAudioCreditsV110.dataset/Contents.json', 'BM/Resources/Assets.xcassets/Audio/UmpireStrikeV110.dataset/Contents.json', 'BM/Resources/Assets.xcassets/Audio/BaseballContactV110.dataset/Contents.json', 'BM/Resources/Assets.xcassets/Audio/BaseballCatchV110.dataset/Contents.json', 'BM/Resources/Assets.xcassets/Audio/UmpireOutV110.dataset/Contents.json', 'BM/Resources/Assets.xcassets/Audio/UmpireBallV110.dataset/Contents.json', 'BM/Resources/Assets.xcassets/Audio/BaseballCrowdV110.dataset/Contents.json'})
ART_HASHES.update({'BM/Resources/Assets.xcassets/Audio/UmpireOutV110.dataset/sound.wav': '6503419ac05ac8ee434b0bcbb549f5228b0adc44ff2f7e9f01c40130b4f8134c', 'BM/Resources/Assets.xcassets/Audio/BaseballContactV110.dataset/sound.wav': 'bee7c92c7262db4f74cd81a397e056e6634037a29b84669bb5e40ed9eea19804', 'BM/Resources/Assets.xcassets/Audio/BaseballCatchV110.dataset/sound.wav': 'ad44c17d9d486b2c075250e20783eb12c6ed79fcda200de316c5017ff0a2c34e', 'BM/Resources/Assets.xcassets/Audio/BaseballAudioCreditsV110.dataset/credits.txt': 'f1187cf93fef33f21058807a9e6f7f311b332dee3acc1be74896aefa11ccc350', 'BM/Resources/Assets.xcassets/Audio/BaseballCrowdV110.dataset/sound.wav': '5ffb19bcc8866f8b2ac93bf28ea3dd6c2f35aeb673c145029f5fdecaa052b9b9', 'BM/Resources/Assets.xcassets/Audio/UmpireStrikeV110.dataset/sound.wav': '31c9b0f118f4476544b42ac387c8e7d69ab7e97b7e8b6267a67e4f1c702607dd', 'BM/Resources/Assets.xcassets/Audio/UmpireBallV110.dataset/sound.wav': '3532951ef9af9cf599f5bd00c70b2966639900b14ad04e5a8eca377b5d947fc8'})

ART_HASHES.update({
    'BM/Resources/MatchArt/school-stadium-v144-backstop-crossbeam.png': 'bbdcbb550d3a18369a04ba2a35dea54370de53f32ab69cf30350288008beabd1',
    'BM/Resources/MatchArt/school-stadium-v144-basalt-side.png': '6ae102df8e553b68b4529f3bd2bd435d6e3e2881886040da3b2d778457cb93f5',
    'BM/Resources/MatchArt/school-stadium-v144-brick-arch.png': '5191eb46a041dc8766cd8bec7a56cb79bf568fc1c341fb27494f9dab141fdd34',
    'BM/Resources/MatchArt/school-stadium-v144-canopy-fascia.png': '34f6aa9de73c601d6784613bb9df5167cd490acacc7c9d526d402793ed6cdedf',
    'BM/Resources/MatchArt/school-stadium-v144-forest-timber.png': '40c1d76ae1056af944b2e8fa79ca00fad12f46c9d88a3cc02e7399e8c3a3174b',
    'BM/Resources/MatchArt/school-stadium-v144-harbor-corner.png': 'de16dacd17d39ccee1bd014167f16a70e1c5d24388b58066f3a9f9eefe711904',
    'BM/Resources/MatchArt/school-stadium-v144-manual-wall.png': '930a210a266bc35f5723c433fb34a6ff824b79db0a76ad449abfb05944cab490',
    'BM/Resources/MatchArt/school-stadium-v144-school-wall.png': 'e856b7c1ea789256cec756403f9e6a932670efb3759145e47a895c0d06518d2f',
    'BM/Resources/MatchArt/school-stadium-v144-steel-gantry.png': '935a037508998716084e4ee0f7b3bb9c956b0a6fed25474c524846515310e0f3',
    'BM/Resources/MatchArt/school-stadium-v144-stone-terrace.png': 'b90afcb37ce169b887c4509d0c4bd28c4522fa2e73e6aac7963c62db5d50e11d',
})

ART_HASHES.update({
    'BM/Resources/MatchArt/pro-stadium-v145-kbo-0.png': 'd0cbae1ba24ea5327ad63c29362b37c3211bdc406bae0183d051cf21679474aa',
    'BM/Resources/MatchArt/pro-stadium-v145-kbo-1.png': '897509d59d5155bdbe65eb8105492e9c22978f549c2d2efbe1451bb3b53d9fc2',
    'BM/Resources/MatchArt/pro-stadium-v145-kbo-2.png': '53a7efbf12d8775239e2cb4e3179b69b01749f330aaa3c882150abd7af024da4',
    'BM/Resources/MatchArt/pro-stadium-v145-kbo-3.png': 'd020aae6bfa8bfe5ad6b91c1a35c90a3028094ddad787dee0874d055b8fcfb19',
    'BM/Resources/MatchArt/pro-stadium-v145-kbo-4.png': '07cc192dceaa70a07c3c23595bbb5f69caaaf7d717b0fd4e480621dcff5c9526',
    'BM/Resources/MatchArt/pro-stadium-v145-kbo-5.png': '1a85672b51a2a43811dd3b028f3fbf0c1d9cccf4d0c7829c0bf3b8208af75850',
    'BM/Resources/MatchArt/pro-stadium-v145-kbo-6.png': '1b91b8aa7fbcee6eb0b47248b61874356ca2dd75c20395a050621c2939d880da',
    'BM/Resources/MatchArt/pro-stadium-v145-kbo-7.png': 'c4af39a4c9bf362d94eccab628279cd42907ebdc4a065a4a2f5a83ed029fd5df',
    'BM/Resources/MatchArt/pro-stadium-v145-kbo-8.png': '266491017a82fcf9de18eabcd61eda01df7284def7395f2c1d93717fbe11aaaf',
    'BM/Resources/MatchArt/pro-stadium-v145-kbo-9.png': '572d67521c9adc7e2b6539e065185751a75f11afc18adc8363bdd0aabf1bc9da',
    'BM/Resources/MatchArt/pro-stadium-v145-npb-0.png': '3192b6ab9fe0cfc532f6a2b295b086c2e57c5e8b8d8237937a81da661b2cac40',
    'BM/Resources/MatchArt/pro-stadium-v145-npb-1.png': 'b201b2399a64c91908b78e90ad9cd8c4924f1c2eda9adadeba17c24bf6ca4673',
    'BM/Resources/MatchArt/pro-stadium-v145-npb-2.png': '7d9a565564085d9b5d0995b1326930d167806d0d209bb5855e177bdd1477f20b',
    'BM/Resources/MatchArt/pro-stadium-v145-npb-3.png': 'c67cd074feb45d0c7d0b5ee008f4b4eb7e10964f70637046e7e3537e1f8195f4',
    'BM/Resources/MatchArt/pro-stadium-v145-npb-4.png': 'ae7b08a2f905866d23689571918584ba48d5078e76187205c8ada88254bd2335',
    'BM/Resources/MatchArt/pro-stadium-v145-npb-5.png': '1a04d502d5ffda5d99e40029f2a3925006dc998aa73dcb8b0fb47a0f8f8916d1',
    'BM/Resources/MatchArt/pro-stadium-v145-npb-6.png': '4a5f046e617ca9938b5c6d736bd2c945097d90119d9eafb465e17f680e9dac1a',
    'BM/Resources/MatchArt/pro-stadium-v145-npb-7.png': '98d8a0e9a6b9cdab82db0c856a3b9ca1aa1519ed05ad85be9f9d02db728f3555',
    'BM/Resources/MatchArt/pro-stadium-v145-npb-8.png': 'd72bdbff1c2e9999b8d0c2230c899c12b52240f7d2c214fc7ee908aff3bc528d',
    'BM/Resources/MatchArt/pro-stadium-v145-npb-9.png': '3e0d4eee9ecb58b97bac26dac11352c5fc14d9f1f7b654ba2307b731ca8759a5',
    'BM/Resources/MatchArt/pro-stadium-v145-mlb-0.png': '8953601f012e2fa477411d703d08305ba19997be1cd6659af0923aab8e6156c6',
    'BM/Resources/MatchArt/pro-stadium-v145-mlb-1.png': '1045845b8d977aed05225adb08da6fd17c55fd11e0f936d9c0bde3b024d4d83f',
    'BM/Resources/MatchArt/pro-stadium-v145-mlb-2.png': '36d988b9b8e73143022e599ca811bb95d77f579d53b41d833e0f9e6488aa507b',
    'BM/Resources/MatchArt/pro-stadium-v145-mlb-3.png': '48dad4e2b5b9e25d4a08b9c0170c25b39a2e93545b2ea97c76b681bbcc4b37ce',
    'BM/Resources/MatchArt/pro-stadium-v145-mlb-4.png': 'e630399f6fa23b1f4ae94edc105bab4d1b6c53bcb95de1e21f06d6cd5c940d73',
    'BM/Resources/MatchArt/pro-stadium-v145-mlb-5.png': '73e18aaf7b8ecd0bd92d509050552a5efe1a1d02fd54aa323095e17a7664033d',
    'BM/Resources/MatchArt/pro-stadium-v145-mlb-6.png': '7ac5574ab3be84896396de56aac63fc2b10325662c64d6d6d8e52fd867d8f896',
    'BM/Resources/MatchArt/pro-stadium-v145-mlb-7.png': 'bc1026a1dde298ba26d7838a831c25bc143b037e24ae61c67322b089e95e56b3',
    'BM/Resources/MatchArt/pro-stadium-v145-mlb-8.png': 'e77574744d32fb8a813c2ab1cf3052526f3685d321da1d0439ec1af595fef448',
    'BM/Resources/MatchArt/pro-stadium-v145-mlb-9.png': '795d94bee6936b148d5859359d4a0eae1c0bc2752bdf939c44b2fdc9b2ea1fdc',
})


# V147 approved club crests, home/away uniform artwork, and field strips.
EXACT_PATHS.update({
    'BM/Resources/Assets.xcassets/Club-mlb-10.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/Club-mlb-11.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/Club-mlb-12.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/Club-mlb-13.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/Club-mlb-14.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/Club-npb-10.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/Club-npb-11.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/Club-npb-12.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/Club-npb-13.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/Club-npb-14.imageset/Contents.json',
})
ART_HASHES.update({
    'BM/Resources/Assets.xcassets/Club-mlb-10.imageset/Club-mlb-10.png': '61fb4347a85d974ff701b8e1d8dfc390b6f55e7574e1c09e664d2b1df1e4bff6',
    'BM/Resources/Assets.xcassets/Club-mlb-11.imageset/Club-mlb-11.png': 'fc7fd224e5cfb4197fbea48457b3f8812d93569a95bc5be7b3ead7b956620451',
    'BM/Resources/Assets.xcassets/Club-mlb-12.imageset/Club-mlb-12.png': 'e5feaa22730a2f5b8bcbf00eb3bc3dda264e494fdc803373d0a877d8fe5e0ac3',
    'BM/Resources/Assets.xcassets/Club-mlb-13.imageset/Club-mlb-13.png': 'd39af3cc591f57a149ba4ca29381d87a7112c7cfc15d11557c268d646a13e7c3',
    'BM/Resources/Assets.xcassets/Club-mlb-14.imageset/Club-mlb-14.png': '5072b018536c2d3b506b2e203bf0b1e45a987ddf989f269f8ba16f6ce91e2296',
    'BM/Resources/Assets.xcassets/Club-npb-10.imageset/Club-npb-10.png': '4b5d4ec6a6fdda7d217414af6a3f70d8ff5d735ec2a8ac806b9de615f2ad00d1',
    'BM/Resources/Assets.xcassets/Club-npb-11.imageset/Club-npb-11.png': '0fc03f38c92b0386d2dc63a1de3cc31a6b489bdee257f5dff33e476b5263d2e5',
    'BM/Resources/Assets.xcassets/Club-npb-12.imageset/Club-npb-12.png': 'b5107a765777891143ffa8d77f4922b382868e87320f25aaa3fa4e947444d1b9',
    'BM/Resources/Assets.xcassets/Club-npb-13.imageset/Club-npb-13.png': 'e7d9776021385f813dae409969285ed60e395499abd7acdd331a003a30814bb3',
    'BM/Resources/Assets.xcassets/Club-npb-14.imageset/Club-npb-14.png': 'f4f50d1b4805510e12eb2ad13b20ffdce357c28ba110c492d583f4f4910336c3',
    'BM/Resources/MatchArt/club-kit-v147-mlb-10-away.png': '1112348d11d2e7a5057f1d413edf7d82af42ba8e50ddf3a4e4fceb83fe804a6b',
    'BM/Resources/MatchArt/club-kit-v147-mlb-10-home.png': '3a4974fe491321a57eb4f8bf6a6c22883718305f0b68a73b959b0c484697f645',
    'BM/Resources/MatchArt/club-kit-v147-mlb-11-away.png': 'aed6e4a4a3b265d7429b3762741cff51e9a845d07ead8a0c2f7d656013ac7bbc',
    'BM/Resources/MatchArt/club-kit-v147-mlb-11-home.png': 'fb383dc42c7f3f6596e8af7c83f634770e4e02665867080679d8a8a493f19718',
    'BM/Resources/MatchArt/club-kit-v147-mlb-12-away.png': '3f005211e4531e4d313220c6025764afd35df2504189f182b0b8ef399641d349',
    'BM/Resources/MatchArt/club-kit-v147-mlb-12-home.png': '2b450af16de8c683631e14e3cf4dad34d3942cb2c4bff51c7fadd9eb5a87a025',
    'BM/Resources/MatchArt/club-kit-v147-mlb-13-away.png': '2d0f54b392bffa952a3b5a9d58a9e51fa281b406239599ebd21c16e84ad3caf9',
    'BM/Resources/MatchArt/club-kit-v147-mlb-13-home.png': 'eb6f63ab3373536f5bc7c2303c405efceb1b4c8f62aa8ad20879e2c1a1d7318b',
    'BM/Resources/MatchArt/club-kit-v147-mlb-14-away.png': '9cc5d5e19bd6fd9b52b5a02571e5fb5c7175e942143b695895defbcc2518d835',
    'BM/Resources/MatchArt/club-kit-v147-mlb-14-home.png': 'b349edbf56427ce4324a030b75c9d22f450e76b63fc3a22cb6f0b6240738c5e7',
    'BM/Resources/MatchArt/club-kit-v147-npb-10-away.png': 'd38402ce6b397df59d60d0f1a26a130092e4839ae9f9875a74c08c350238842c',
    'BM/Resources/MatchArt/club-kit-v147-npb-10-home.png': '3d65c2c8259d802b9b80bbfba887985db9bf2538c5148c0298ce299466cb84a7',
    'BM/Resources/MatchArt/club-kit-v147-npb-11-away.png': '5963e54defd3b8c3a305807252c28a6560a0a096236beb62a1c1ca19098a93e7',
    'BM/Resources/MatchArt/club-kit-v147-npb-11-home.png': '6b06d85417077340ae781ffda1775d8385759e1147dac0b29873b7963882c558',
    'BM/Resources/MatchArt/club-kit-v147-npb-12-away.png': '783f53e3a96632b609bce7d6f592db0bd48cd97c31866ec3f70255119bfaa2f8',
    'BM/Resources/MatchArt/club-kit-v147-npb-12-home.png': 'acc4d986f967b123a15662beab95a1c57df88dac3119c2c128af04f2938a161b',
    'BM/Resources/MatchArt/club-kit-v147-npb-13-away.png': 'fb26e2073b4b53dc3410499c504bb06a6af83a22acb9ced43d046bdab219590c',
    'BM/Resources/MatchArt/club-kit-v147-npb-13-home.png': 'b75604d9e7860ec94ba3758ec2ff0d02ed559adef9eb4a06deb8953d4b5c898c',
    'BM/Resources/MatchArt/club-kit-v147-npb-14-away.png': 'f42186ae543f881bcca83309e9b424909b9e7472d5089cb6afc84d7de7e0e106',
    'BM/Resources/MatchArt/club-kit-v147-npb-14-home.png': '64739d08b71041fa1e89deb95d7ef6da0e26d5e95e5c281ae81a8f755c1a859c',
    'BM/Resources/MatchArt/pro-stadium-v147-mlb-10.png': '9202bff83e4c6f0701fa69e914a76212f4a838408e873a0b4c63cbe329e4d50f',
    'BM/Resources/MatchArt/pro-stadium-v147-mlb-11.png': '0cfd4b7d6833209f58382f7a53165dfd437006ff9beb954f2218067f084e594e',
    'BM/Resources/MatchArt/pro-stadium-v147-mlb-12.png': 'fea08ea3fc7a86ccf0678c6dbabf711a2916146a0433eff56abc72a9ef6447c8',
    'BM/Resources/MatchArt/pro-stadium-v147-mlb-13.png': '65346e5e0990233057a5cdf158ff2f24575b08ae4f41cf49225c5094a426ab22',
    'BM/Resources/MatchArt/pro-stadium-v147-mlb-14.png': '18750450b776b701bc4975c82fb97452b7e2b63b69a92cdcf5c364a1ab7b567e',
    'BM/Resources/MatchArt/pro-stadium-v147-npb-10.png': '7e61d59439974589e5906af28908d82ea1e68560d41877bf5e155ba081eab2f6',
    'BM/Resources/MatchArt/pro-stadium-v147-npb-11.png': '0a168b8f4e143c1ff531f90b61a5a6fa2c41b67bc1c02e94623b0e5582356fee',
    'BM/Resources/MatchArt/pro-stadium-v147-npb-12.png': '9e9f11a9d7f08a59eae1cd9191bb8ecef937ee249cb7d553210aa60f1761049c',
    'BM/Resources/MatchArt/pro-stadium-v147-npb-13.png': '24ab35011ecca7f96c3baa57f79a1b05904b3e8eb59fced774b3bd6e447af833',
    'BM/Resources/MatchArt/pro-stadium-v147-npb-14.png': '934aa573e45e1e90f63b97d2a73ec5dc291ae78739e876ce6cff0ae95987add9',
})


# V187 reviewed game turf overlays.
ART_HASHES.update({
    'BM/Resources/MatchArt/stadium-turf-v187-dome-batter.png': '0818b9c4a2a77a28b315191da439cb5e2aa9f58bb740340598664ce3f4580842',
    'BM/Resources/MatchArt/stadium-turf-v187-dome-field.png': 'deddf1e5dca1d0ac09df3499596fb9e965f94fcf485e6727884a5c237e119d2b',
    'BM/Resources/MatchArt/stadium-turf-v187-dome-pitcher.png': '758abc4a8d477d6a5c3ca4656d8fd4296b702931f9f758a42afd33d83a6975c4',
    'BM/Resources/MatchArt/stadium-turf-v187-harbor-batter.png': '297b8f6d5e47abfa69645f5dbbb42e8584c67441d774e656b43c3aae0642de71',
    'BM/Resources/MatchArt/stadium-turf-v187-harbor-field.png': '21ae78007d508dd48a1256b62144f07af575ed6070dde031d91ca59608fad9e8',
    'BM/Resources/MatchArt/stadium-turf-v187-harbor-pitcher.png': '8d8c64e7e6f483d0c5450b1f4a1816b08f4abadc430219a9aedc0def4af76017',
    'BM/Resources/MatchArt/stadium-turf-v187-pacific-batter.png': 'cbe7776fb7421eef908fb716020a58dcec8f7fc83224d46324164dc5666d9520',
    'BM/Resources/MatchArt/stadium-turf-v187-pacific-field.png': '079cffeed18d48c21f13ce2c152faf28bf5499029a169eebbd1900ff78603d0d',
    'BM/Resources/MatchArt/stadium-turf-v187-pacific-pitcher.png': '03f1ef417a113f0f3cd0588afc691dfbc1ac6f88e4115a02e82b61a5a31ee86e',
    'BM/Resources/MatchArt/stadium-turf-v187-stone-batter.png': '9ee7b1bcab7f9964a1073394016c639fc6883d1d432de2ad14b041b3c3c195a6',
    'BM/Resources/MatchArt/stadium-turf-v187-stone-field.png': '812340d11a57e1688ee09287269a4c879e5f1991be5fbcbb8e2b8a9a173f98f6',
    'BM/Resources/MatchArt/stadium-turf-v187-stone-pitcher.png': '12855d2563b6a62ddc74ea24cec5e447e15defe3cb7d413c959f8c1324d59d23',
})


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
    # User-designated public support contact: allow only this exact declaration.
    # Commit identities and every other email occurrence keep the normal checks.
    if path == "BM/UI/SupportInformationView.swift":
        public_contact = ("jfmdr" + "@" + "naver.com").encode()
        declaration = b'    static let contactEmail = "' + public_contact + b'"\n'
        if data.count(declaration) == 1:
            return content_issues(data.replace(declaration, b"", 1))
    return content_issues(data)


def git(*args: str) -> bytes:
    return subprocess.check_output(["git", *args])


# V98 individually reviewed original creation layers and school-kit previews.
EXACT_PATHS.update({
    'BM/Resources/Assets.xcassets/CreationBodyV98.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationCapV98.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationFeaturesV98.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationHeadsV98.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-001.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-002.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-003.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-004.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-005.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-006.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-007.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-008.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-009.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-010.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-011.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-012.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-013.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-014.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-015.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-017.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-018.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-019.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-020.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-021.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-022.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-023.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-024.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-025.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-026.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-027.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-028.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-029.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-030.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-031.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-032.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-033.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-034.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-035.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-036.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-037.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-038.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-039.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-040.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-042.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-043.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-044.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-045.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-046.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-047.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-048.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-049.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-050.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-051.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-052.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationLockerV98.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationPitcherBodyV98.imageset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationSchoolKitsV98.dataset/Contents.json',
    'BM/Resources/Assets.xcassets/CreationSchoolKitsV98.dataset/kits.json',
})
ART_HASHES.update({
    'BM/Resources/Assets.xcassets/CreationBodyV98.imageset/image.png': 'ca7eee405bdaa49f8351f281534a07ec58dd9a66dc1adaf5166987cdd7f26eba',
    'BM/Resources/Assets.xcassets/CreationCapV98.imageset/image.png': '1d012d031ca81c17a22842db30e57350cded3f952807f5ca1bda5be432306168',
    'BM/Resources/Assets.xcassets/CreationFeaturesV98.imageset/image.png': '7102ed965f7a541ff5733a574b84034743b6886e72630adfce9faeba51e7faed',
    'BM/Resources/Assets.xcassets/CreationHeadsV98.imageset/image.png': 'cca8c49d36e4178ff373c94cbcd28f0584755bdd8bdd702111e81ea01e75110e',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-001.imageset/image.png': '7cc22e5a53cfd9a2771a844d4ebd733d956619b9986368983c652400588df413',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-002.imageset/image.png': '1edf9c65f040dee9a0c82cecc786074532d40dbb1e70ecc6b75d4a24e7dfeb66',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-003.imageset/image.png': '4351113366f38ee2fb16a47279135b501c38e579c01dfc95871011e22a2608b8',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-004.imageset/image.png': 'bed165c7afd3a1e693a7b40cbc4839e8b94c7faf96a3039ebc2e47027e4f7903',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-005.imageset/image.png': '92b9537c9f8168aa628fce879a3865987e63f6bb711e0882a34cbe5f767b15a1',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-006.imageset/image.png': '18c75a008f086f1be896b97411b75a16f1335d54378d9f7e1406ff3a47e1b7b6',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-007.imageset/image.png': '73b539e28311b466acfe940645a6e6055ba767067fe4450ad9a95fbde718800e',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-008.imageset/image.png': '061b0aee811f49363e8a3e09a611fee61813ce68cefaa70eeb00c0567491e761',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-009.imageset/image.png': '5293e6cc7314004ed89abef15be477964ca934f17a0113a46abf8263faed3ca8',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-010.imageset/image.png': '9da032c3314192f54ef7033bc6347383897445cce6d590fcf3c7f2da09d89a5d',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-011.imageset/image.png': '713f7a1a87e9abd643faf1036b08892856d75b2ac0511a0c7498466ad30d4a3f',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-012.imageset/image.png': 'ad78d8399b21d02cab24d2b9c2bf7ebb9a00f89affc0d3f7aa6367ceea7a2678',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-013.imageset/image.png': 'a0b499278698aba7bcfa0f99264bb5352a548247e6f813714429f0e2c6d4b514',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-014.imageset/image.png': 'ca8f1542fb548f337010ec6c164028c83e120b24fbe665c637447b03d132910d',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-015.imageset/image.png': '0bd3ce2c0f6a905707cffa165eef052deb778b64e6609a16ecd5f25b62c987f5',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-017.imageset/image.png': '4e290a783e583cb06d99b2b1bd0a1081b33103501924fe1d23a578399697e102',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-018.imageset/image.png': '3348e0f0659763e05baabd01c744f66f895a653246d018a093e420ef7056952b',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-019.imageset/image.png': 'a74ede714f8d654fea4495334550807c4e55193e429565e7d6ab28a73f28f7fa',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-020.imageset/image.png': '7f857d9f32ea806411c3cb6560cb67eea6b741749ba3bc5d611004d1da2cf764',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-021.imageset/image.png': '4a0fc6e3f26dd6072b8b3ebebac08def7d6f1bf078f6e812b9b3e794c1c4219d',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-022.imageset/image.png': 'e042cb531db8c3e72ae3866e7c6d8b746ee774ec8fbe88813ff5a219194cb370',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-023.imageset/image.png': 'cf60ba22566118e655b5ffe5fb3fb50ae01a71e8ddab93d2167ba2d742bdfdc7',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-024.imageset/image.png': '8004607a24a6a7baaa32ad6dbbfa7aa055329892394e1d0fcea38e516c961662',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-025.imageset/image.png': 'a2b03925656d184690ec8f9c4dd7d4872f3bdb7cf8b75ef7811c1938516fefb5',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-026.imageset/image.png': '6e012d72b8c904f988451f1bfb6452a5e99a6bd57b50ff74c97b7a2b0a16018e',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-027.imageset/image.png': 'ca0de3c765616d569d7ab8119636841c5686c933f56740780d36a75897ff3a84',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-028.imageset/image.png': '94130fdb62c9e3c757f4a369e3f92f827fbf27b5f21f6959ec186d29db37679c',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-029.imageset/image.png': '01760e25efb3509ce9b155104f809015b17e273c184ca79c1e0c7b1415647c84',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-030.imageset/image.png': 'fa7ee18be413ceb2b59626db7dcc599ca565f13e36f1e84ec1ddc245e35c9be8',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-031.imageset/image.png': '78af367d65b87c7c3ad9554e97550b0a0debb524cc415557c12f023f48b1b796',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-032.imageset/image.png': 'c6db66423b17d3e0a42c9eefa47fa507d1844380250becae2c7fa125cf535855',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-033.imageset/image.png': '18bc783003b90e6e0a5be34b143686630449ac9444ea924c1ea6acc26746317b',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-034.imageset/image.png': '676d48a79e58b3fce08bf0c8f35a601aaf3d54f442cbfbe30693af0afda3a29e',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-035.imageset/image.png': '5437c43dc7266b20d4afccaab8d6a419e6f97544c0a51bf167e458650e2b2007',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-036.imageset/image.png': '827da9dc8914ad0791bb0fccc320580b5ee418f8f242bf4d5c31804686888a2a',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-037.imageset/image.png': '9f3da6d167a68ffb32d681ed520758c2dfc219cbfb83c65406c446948868dc39',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-038.imageset/image.png': 'a73581eb6234b06ad3f25573488a851373fe79c4cb861cda08574157f6f98ab8',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-039.imageset/image.png': 'df69003b0cdfeeb743a14d005b1474942eb97fa4f1bbaee5b973c36df709af3e',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-040.imageset/image.png': '1f7c086620adbe6e7f5b5a21b8cbb4a90db364ebde7c6b57823f669c682af751',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-042.imageset/image.png': '44f564de41050d0e460aeab91e7f477e816cd148ecf1965be72f6e606a873334',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-043.imageset/image.png': 'd9e086f9c6fd5b85af46c6b1e7176c5002688b755b3d762c50b1059d346a3371',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-044.imageset/image.png': 'f17a7bd25a4768d7f032df7c871c3d2550dbdd4a33705a60eafb4c65a9930f62',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-045.imageset/image.png': '3f03276c4fc8629ff276cb807cc14c38ec57ecfb88e017fca5cf490095aabcc9',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-046.imageset/image.png': '1deda6c19d6842974b1f1cbf6e339c8e0eac8451a166fff39f4857320e28ebd6',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-047.imageset/image.png': 'a7e2f19977c028473ac8b1c2f4b5c8a9e8d0b2edf11008591ef47a4984594b1c',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-048.imageset/image.png': '3a471dbcb40abe63668321921468f7e09b68fd39a62c0295f797041825d4265e',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-049.imageset/image.png': '02e77b62111c80e600dec2311d698acc2f1e095be78ca4b03339d9fd427ca393',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-050.imageset/image.png': '15301fa08793bacecd96100d2b6657439dab3b380682a2d844c33004ea3a503f',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-051.imageset/image.png': '59b2b14ca90bf3efc5026a43995f37ba715d7bdabbc05ef771b80cbfd97ee222',
    'BM/Resources/Assets.xcassets/CreationKit-hs-ref-052.imageset/image.png': 'f15e8ca5a624656476eb487f3fd741f55ea141eefe492975b986417e84ceaa9b',
    'BM/Resources/Assets.xcassets/CreationLockerV98.imageset/image.png': '630371dd9f994a244eb59896024e339d2ef58fa1d3fd4f409b59b73938f853be',
    'BM/Resources/Assets.xcassets/CreationPitcherBodyV98.imageset/image.png': 'aa62e20884c943ece9018426379742d924c7a919c0050d8f6558c5e5e6d4bab0',
})

# 승인한 와이드 원화와 구장 명세만 고정 해시로 허용한다.
ART_HASHES.update({
    "BM/Resources/MatchArt/WideStadiums/venues.json": "8d4a202975ae633e64915cb4be227914b15682e54a62b4b0cc0cf369e9ee3411",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-001.jpg": "809a1bfc16f23348c576b97426dcf5ebbdb7981f0f81fde7382dfc2538de1af6",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-002.jpg": "8706dffd77f3984871d89eedc62ee8be43d816f169535ce00724c7c3e314aa2b",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-003.jpg": "1850d9d8e2e28cd6ed7d0e4c6aecf7ac2f8d9f41287f341b4b37fde7a489db0f",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-004.jpg": "82f29acc8d3c3f23ba41ed27666448cf49686e38156bfb375da160c003f5874d",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-005.jpg": "62d1ecb28df6986ead587f4b532c51a8f7a1c809679ef6735615f902eaa1087c",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-006.jpg": "b9f2faac7f3acfcd831364aa94949a39fe71592d4099fe88e701da744d086632",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-007.jpg": "23c63e0c4bd12272e0f90be3f5818c1fe479edb9a76e63d4d397ed8b353a27ea",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-008.jpg": "107276695a16ea1d959658b50dd48791915e4b56c765e5c9ee469334285b0e05",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-009.jpg": "2bac6d954f4f1486dde72a03e630bd1b631fb740ecfc86c1c5e794de6efea793",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-010.jpg": "2c60da233751a44621a44db36d2dc1248f8a790527d60d38a355fb4ea4a4332d",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-011.jpg": "4e90e02dff58ebc668edfcf7acf08ba05f2697435977296b577186e5e0153b2e",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-012.jpg": "57ff44a886d55bfad4d8ea6d8064e53c09817e35b16b55cedae77e4d66b7aa8f",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-013.jpg": "a9406413461d61437425b1152b0f9befce52efc615e553c4679a98eb2a24b960",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-014.jpg": "5faf5244a90c87c535dcbe6756e47243a514db4e07a5f2c1bc0914504858eae7",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-015.jpg": "da9350afb97b8d0caf2b9d4146cc76867a4c2e8ce38463b8acae7fb0c4bd34cd",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-017.jpg": "ea81c4152c56cf19a51e66a362412f03f5d1b346cce83251fba6d007b5b15361",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-018.jpg": "eef79912f0abf384f7bf95148d20ab401880ec67f2ae33d3872a1393a471cd59",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-019.jpg": "08761a9c98902777228207caac9a03e5b1a6b95316f378547c99efcc878376a2",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-020.jpg": "5a7caa8e03c29710e5cf0a504f568c707a7795ff67933c932ff3850af424f403",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-021.jpg": "01b53e08d944cef2fb755cb28fa248221167517ff82bd90e38fb424827607fd5",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-022.jpg": "eeeb9eb1d510dd41f02356ebeb47f14b4b1c572a06d100d2fbcfb83209654aa9",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-023.jpg": "468aef04cdb0d35040b622ccec48bdaca6c072cfbc0e7e0e2fd5adb1c1858d1d",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-024.jpg": "bb2a8cb86bab31150a75e7d8e6995449bbfce52e659826aaf5b868c309cd47b4",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-025.jpg": "d6c358b5a6ff361627749a9943f97fce22391572bb4517bc95830084d0da421b",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-026.jpg": "b07acb8725e869b4ddbf9265536ab6b677d8b3e09112f1535982e4c90d2982af",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-027.jpg": "8404b564c0fabf4eff4a5dde743e2b92a7d5faf95420545fde65bb178072d822",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-028.jpg": "4ad32c9a9993bb54ad031f2aa70d73f735ad2957f052a0c46dd47e04d4d2b6cb",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-029.jpg": "a6f0f7cb612173facd5e8f6b9d1cd24142e77dddaed0325e2b5e0b6cbdb07b91",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-030.jpg": "45df8eaf035594b7a25094a0d26d53219b03fee7073ad827fc8683cd5114cc89",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-031.jpg": "dc52f983ad83de3dfee28bc2ae26ffa81e3386b28713d94c755ffac6dc389c33",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-032.jpg": "89ba9f7bf7e9a1b30cab1951b4b84016cf1208e4e45f6c408e3c2a7fad37e914",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-033.jpg": "e64da3525db518c3d8a4d9c562afc8bc03d3365cf8b318ede783398e47ea09c9",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-034.jpg": "2e8e72d6ac0f331052c4eaed460b0f4bea967f206c9f58a3520a125d1ce4e781",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-035.jpg": "4294e69b48d32c922cb89923093e841bc47abada4a9b245c7e86ac31d85d4944",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-036.jpg": "c5f895a8e5c4065c6aed97f35a59ac0d8ae37c7c1d461d384f7a258ed3d30493",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-037.jpg": "42b16a2bf48975d163320f7822940271966892cc1346a0cfcdd3c925d5b80523",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-038.jpg": "2f937dfd864d17d152834106033dd74277cc5b4c808efe529122b85a997bd6ed",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-039.jpg": "1c87022e514068aa1fe16a658768151a2bf227050bfb13746f7bd8808333a301",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-040.jpg": "d91eff583ebcefa0c779bba3b6d70614390da926896cf628adac7ce24718bd64",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-042.jpg": "353b102c1303aebbe144bb3ebfdb0e58643bd809841e15ed00bcf5e8f3bf3c19",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-043.jpg": "200eec48ef2c3a06b27d0f0b9d65a4aef4bd30fefb9a5bd3adf57e0c98fb5841",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-044.jpg": "79a3051f8418fecd8b6f0b2bbc5e47b51212bff6f68a8b1ec292219cda95886a",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-045.jpg": "ed2c0d683e897434bbfaaff2f90903513614b9fcdb6ff17aa2a033a3dca95c01",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-046.jpg": "1e91cf8437cd495d6f795c4bfcbc0bc0f20df8e47a7f76e27cbdaa8877cfc117",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-047.jpg": "be5d8e467dfac349c5ae99609a1ef2aafe6fe355a2551ae62d6dfd294ab95639",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-048.jpg": "898539345242476fd2db01ea52c2e4cd3584ba6a91832524ad866c17bed9fb45",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-049.jpg": "87d99dd9a200ef657e4d83c211f236ecdb1d5f052a0930f451e940c570f1c97c",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-050.jpg": "6b8e2030c05350bad30451c659c58db230e25d07a65ffbf235ffb27bbbc64caa",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-051.jpg": "7c6b376ae9a0c685abcc61c1069ce2c959575ab0f45570f9643b9338302f02a7",
    "BM/Resources/MatchArt/WideStadiums/venues/hs-ref-052.jpg": "fdcc9df881851714481a5994126f0e831b54dc96b73fdb94332b5d87b0d254ff",
    "BM/Resources/MatchArt/WideStadiums/venues/kbo-0.jpg": "c809ead453f6ed196ed4069cd080d078d9ab3b8d9c9d6a75764420337c124eb9",
    "BM/Resources/MatchArt/WideStadiums/venues/kbo-1.jpg": "856dd44a65f24526af9d8fe2fa4602c42f1e0d2376b9f9c2e3880bf183e72a75",
    "BM/Resources/MatchArt/WideStadiums/venues/kbo-2.jpg": "f17433a3f1314f9d4c35489355baf5f68687df9ac6fddcd797feff385469269b",
    "BM/Resources/MatchArt/WideStadiums/venues/kbo-3.jpg": "b0f7dc24129a2cb5233d67bc8d5bd0504728c6de786a4508630617659ac738ca",
    "BM/Resources/MatchArt/WideStadiums/venues/kbo-4.jpg": "4a15ba55255bedaf33c01a7b4ac0441d7fdab7fe8b75f1e60abccdaf21a78d5d",
    "BM/Resources/MatchArt/WideStadiums/venues/kbo-5.jpg": "bb113a2adb9412c3ddf3221c571c4423cdfa3dc8348d0f3415ca1d46b1418fd8",
    "BM/Resources/MatchArt/WideStadiums/venues/kbo-6.jpg": "61a4a55c6dc1f58180fde4ed0478efc4158ea9c27e17ee0f0cef8dbe30163006",
    "BM/Resources/MatchArt/WideStadiums/venues/kbo-7.jpg": "4dcf6bc50f8cd4eb52181402196cf1afc23ee6a6e5f7440d11100aac2bd3b667",
    "BM/Resources/MatchArt/WideStadiums/venues/kbo-8.jpg": "b9562a803d2423bac2a3f11709871211b372489258d24c96b8b9464558c10f30",
    "BM/Resources/MatchArt/WideStadiums/venues/kbo-9.jpg": "b97c6b190deeefd33a7d106a2a9cf13413868495cf6f5a8dbe03124dd3dfcffc",
    "BM/Resources/MatchArt/WideStadiums/venues/mlb-0.jpg": "45f0102de50edc5d08e9e1a8c4a9cb4a32aa2cff3e76ab4d174e6867de6d277d",
    "BM/Resources/MatchArt/WideStadiums/venues/mlb-1.jpg": "f823654f1979d4d1622f9ee4fa9f2651a98ac4daa08013a98028652100640b19",
    "BM/Resources/MatchArt/WideStadiums/venues/mlb-10.jpg": "2688fb597aa1d8b311a7bd518342b4f98c981e069818b0f91e1ce2506eef63c8",
    "BM/Resources/MatchArt/WideStadiums/venues/mlb-11.jpg": "55ae28efcef3d58dd2bf63f0d4162e99e97d7abdf80161ac4609858aa80cc176",
    "BM/Resources/MatchArt/WideStadiums/venues/mlb-12.jpg": "1ef5f8e5a3fa64aa8b637167b4298296cb460b6c1a9201d327bd6b576f6539cd",
    "BM/Resources/MatchArt/WideStadiums/venues/mlb-13.jpg": "d9b2fbf0b431b5ebd140816e3cd4702d787b1e517fea8160a387aa4e0a55f978",
    "BM/Resources/MatchArt/WideStadiums/venues/mlb-14.jpg": "d41927cd739e054f508b1e58cc79bfa293ac8994ee36578aaf37d8b2017f607d",
    "BM/Resources/MatchArt/WideStadiums/venues/mlb-2.jpg": "10d2d99958018f8ba888b0f770b29f08a1bc7ab66b1f8add6c4a22c5af3965b9",
    "BM/Resources/MatchArt/WideStadiums/venues/mlb-3.jpg": "1e36896a4cd892f47f3aa5080657c660529b3e4e07a117d186400b2a20b5a800",
    "BM/Resources/MatchArt/WideStadiums/venues/mlb-4.jpg": "6afb81662913e968eed1f9b452110c688fe022f6aa4c8fc3145ad06689c6cc77",
    "BM/Resources/MatchArt/WideStadiums/venues/mlb-5.jpg": "972de9e11c4b280f5eb7e1479fd96477392c6947177120761d9ef821cee6f5a5",
    "BM/Resources/MatchArt/WideStadiums/venues/mlb-6.jpg": "89d4f3eaec900bae38bf096465505985fa194877e154684e7134afc79e44afee",
    "BM/Resources/MatchArt/WideStadiums/venues/mlb-7.jpg": "07532cc957b86c8510046af3a587d958c61e58c21db6babb2dbf5bb4b1b88383",
    "BM/Resources/MatchArt/WideStadiums/venues/mlb-8.jpg": "c80749835d81bae8d915c61ccabdbb1a5811979a7eb282136a05589334f6fe8b",
    "BM/Resources/MatchArt/WideStadiums/venues/mlb-9.jpg": "1f3a75d126154d8c1f2473bca8d00b3bead356f8dafdb84aea6a78984d4b1e49",
    "BM/Resources/MatchArt/WideStadiums/venues/npb-0.jpg": "fef1ddddacca69c0ffc01ef10f4f76bd29fcb4b1ce63d45eef442f3e575f616e",
    "BM/Resources/MatchArt/WideStadiums/venues/npb-1.jpg": "e842fd3be3c9659db0083df52ce18e847018873ecb8b6bbe596720dccd8957d4",
    "BM/Resources/MatchArt/WideStadiums/venues/npb-10.jpg": "902193549a39d0a92ee338f8d53c40f56745e4bf17fbb019604d15cfb1fa5980",
    "BM/Resources/MatchArt/WideStadiums/venues/npb-11.jpg": "f4f7f6e2af317e8dbc8dcf1043e82077cc021fbe70136756c890d4125f343ecd",
    "BM/Resources/MatchArt/WideStadiums/venues/npb-12.jpg": "97e5bdae1033587453c172af6383771b6845be449dacfe1a22e961caf42b791a",
    "BM/Resources/MatchArt/WideStadiums/venues/npb-13.jpg": "823587b73737327f53f039fe6ff92750890e9f316d44f3c1819ff45f4343427c",
    "BM/Resources/MatchArt/WideStadiums/venues/npb-14.jpg": "c9142ebf2ae83ac35accd8a7bc64c0311ff5238bce1ad20def492f2b05cccb41",
    "BM/Resources/MatchArt/WideStadiums/venues/npb-2.jpg": "790b4988b854e4ccf1b5f8daf597347888d32430e401dc6672db7fa9f99630fe",
    "BM/Resources/MatchArt/WideStadiums/venues/npb-3.jpg": "79bbca9a95a5403e72ca297a8e990b0a36948f31f44e9b7000cfa9f7fdb89494",
    "BM/Resources/MatchArt/WideStadiums/venues/npb-4.jpg": "5c0817a1cd060c647866c4ca3b46141700312ee1af51f25c658c8c8a56b839c9",
    "BM/Resources/MatchArt/WideStadiums/venues/npb-5.jpg": "61299e421a31dceb681c1e537efab97769ade995f35e3532888b1f9fd45fe481",
    "BM/Resources/MatchArt/WideStadiums/venues/npb-6.jpg": "cdbdffa0d1f2044f9530a920b3fb099a1233bc0e977f9d9bc3ab42c3e7c29307",
    "BM/Resources/MatchArt/WideStadiums/venues/npb-7.jpg": "c85d1c0cfd6fccbeda996ee1b77b6ae52cce31d4fe8c43d09eb1a103f03684b2",
    "BM/Resources/MatchArt/WideStadiums/venues/npb-8.jpg": "e2df962f2ef9e18e972487d7bcc4eecce332972e4053648a0047b7d4afa81be9",
    "BM/Resources/MatchArt/WideStadiums/venues/npb-9.jpg": "79d05527866c10fd6bdbde50565273dc95bd873d4fa967ad33124a001f34be5f",
    "BM/Resources/MatchArt/inplay-stadium-wide-v240.png": "6aac9cebb8053c263e761dcb59c7790215eda5736d2e19ea2865875f4dfdab39"
})

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
