"""Build the licensed Shuye Serif subset from a separately downloaded source."""

import argparse
import hashlib
import json
from pathlib import Path
import zlib

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

SOURCE_SHA256 = "050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"


def build(source: Path, destination: Path, root: Path) -> None:
    source_bytes = source.read_bytes()
    if hashlib.sha256(source_bytes).hexdigest() != SOURCE_SHA256:
        raise ValueError("Source font differs from the audited upstream version")
    font = TTFont(source)
    instantiateVariableFont(font, {"wght": 400}, inplace=True)
    options = subset.Options()
    options.hinting = False
    options.layout_features = ["ccmp", "locl", "kern", "liga", "palt"]
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.notdef_glyph = True
    options.notdef_outline = True
    options.recommended_glyphs = True
    unicodes = set()
    for start, end in [(0x20, 0x24F), (0x2000, 0x206F),
                       (0x3000, 0x303F), (0xFF00, 0xFFEF)]:
        unicodes.update(range(start, end + 1))
    for lead in range(0xA1, 0xF8):
        for trail in range(0xA1, 0xFF):
            try:
                unicodes.update(map(ord, bytes([lead, trail]).decode("gb2312")))
            except UnicodeDecodeError:
                pass
    dictionary = root / "assets/chinese/STCharacters.txt"
    for line in dictionary.read_text(encoding="utf-8").splitlines():
        fields = line.split("\t")
        if len(fields) == 2 and all(ord(c) in unicodes for c in fields[0]):
            unicodes.update(map(ord, fields[1]))
    for path in (root / "lib").glob("*.dart"):
        unicodes.update(ord(c) for c in path.read_text(encoding="utf-8")
                        if 0x3400 <= ord(c) <= 0x9FFF)
    worker = subset.Subsetter(options=options)
    worker.populate(unicodes=unicodes)
    worker.subset(font)
    names = {1: "Shuye Serif", 2: "Regular", 3: "ShuyeSerif-1.0",
             4: "Shuye Serif Regular", 6: "ShuyeSerif-Regular",
             16: "Shuye Serif", 17: "Regular"}
    for name in font["name"].names:
        if name.nameID in names:
            name.string = names[name.nameID].encode(name.getEncoding())
    destination.mkdir(parents=True, exist_ok=True)
    target = destination / "ShuyeSerif-Regular.ttf"
    font.save(target)
    data = target.read_bytes()
    report = {"source_sha256": SOURCE_SHA256, "bytes": len(data),
              "deflate_bytes": len(zlib.compress(data, 9)),
              "sha256": hashlib.sha256(data).hexdigest(),
              "codepoints": len(font.getBestCmap()),
              "weight": font["OS/2"].usWeightClass}
    (destination / "font-audit.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--root", type=Path,
                        default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    build(args.source, args.destination, args.root)
