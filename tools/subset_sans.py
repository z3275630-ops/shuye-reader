"""Build static Noto Sans SC UI faces from a pinned, audited source."""

import argparse
import hashlib
import json
from pathlib import Path
import zlib

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

SOURCE_SHA256 = "a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"
SOURCE_COMMIT = "a85815a42757630ce188fdad368c2dfc444d4773"


def build(source: Path, root: Path) -> None:
    if hashlib.sha256(source.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ValueError("Source font differs from the audited upstream version")
    # Use the existing public common-character repertoire, never users' books.
    common = set(TTFont(root / "assets/fonts/ShuyeSerif-Regular.ttf").getBestCmap())
    ui_chars = set(range(32, 255))
    for start, end in [(0x2000, 0x2070), (0x3000, 0x3040), (0xFF00, 0xFFEF)]:
        ui_chars.update(range(start, end))
    for path in (root / "lib").glob("*.dart"):
        ui_chars.update(ord(c) for c in path.read_text(encoding="utf-8")
                        if 0x3400 <= ord(c) <= 0x9FFF)
    reports = []
    for weight, face, chars in [(400, "Regular", common | ui_chars),
                                (600, "SemiBold", ui_chars)]:
        font = TTFont(source)
        instantiateVariableFont(font, {"wght": weight}, inplace=True)
        options = subset.Options()
        options.hinting = False
        options.layout_features = ["ccmp", "locl", "kern", "liga", "palt"]
        options.name_IDs = ["*"]
        options.name_languages = ["*"]
        options.notdef_glyph = options.notdef_outline = options.recommended_glyphs = True
        worker = subset.Subsetter(options=options)
        worker.populate(unicodes=chars)
        worker.subset(font)
        names = {1: "Shuye Sans", 2: face, 3: f"ShuyeSans-{face}-1.0",
                 4: f"Shuye Sans {face}", 6: f"ShuyeSans-{face}",
                 16: "Shuye Sans", 17: face}
        for name in font["name"].names:
            if name.nameID in names:
                name.string = names[name.nameID].encode(name.getEncoding())
        target = root / f"assets/fonts/ShuyeSans-{face}.ttf"
        font.save(target)
        data = target.read_bytes()
        reports.append({"face": face, "weight": font["OS/2"].usWeightClass,
                        "bytes": len(data), "deflate_bytes": len(zlib.compress(data, 9)),
                        "codepoints": len(font.getBestCmap()),
                        "sha256": hashlib.sha256(data).hexdigest()})
    report = {"source_commit": SOURCE_COMMIT, "source_sha256": SOURCE_SHA256,
              "faces": reports}
    (root / "assets/fonts/sans-audit.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    build(args.source, args.root)
