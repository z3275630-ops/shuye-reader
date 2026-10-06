"""Build the licensed 600-weight UI subset; never inspect users' books."""

import argparse
import hashlib
import json
from pathlib import Path
import zlib

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from subset_serif import SOURCE_SHA256


def build(source: Path, destination: Path, root: Path) -> None:
    if hashlib.sha256(source.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ValueError("Source font differs from the audited upstream version")
    unicodes = set(range(32, 255))
    for start, end in [(0x2000, 0x2070), (0x3000, 0x3040), (0xFF00, 0xFFEF)]:
        unicodes.update(range(start, end))
    for path in (root / "lib").glob("*.dart"):
        unicodes.update(ord(c) for c in path.read_text(encoding="utf-8")
                        if 0x3400 <= ord(c) <= 0x9FFF)
    font = TTFont(source)
    instantiateVariableFont(font, {"wght": 600}, inplace=True)
    options = subset.Options()
    options.hinting = False
    options.layout_features = ["ccmp", "locl", "kern", "liga", "palt"]
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.notdef_glyph = options.notdef_outline = options.recommended_glyphs = True
    worker = subset.Subsetter(options=options)
    worker.populate(unicodes=unicodes)
    worker.subset(font)
    names = {1: "Shuye Serif", 2: "SemiBold", 3: "ShuyeSerif-UI-1.0",
             4: "Shuye Serif SemiBold", 6: "ShuyeSerif-SemiBold",
             16: "Shuye Serif", 17: "SemiBold"}
    for name in font["name"].names:
        if name.nameID in names:
            name.string = names[name.nameID].encode(name.getEncoding())
    destination.mkdir(parents=True, exist_ok=True)
    target = destination / "ShuyeSerif-SemiBold.ttf"
    font.save(target)
    data = target.read_bytes()
    report = {"source_sha256": SOURCE_SHA256, "weight": font["OS/2"].usWeightClass,
              "bytes": len(data), "deflate_bytes": len(zlib.compress(data, 9)),
              "codepoints": len(font.getBestCmap()),
              "sha256": hashlib.sha256(data).hexdigest()}
    (destination / "semibold-audit.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    build(args.source, args.destination, args.root)
