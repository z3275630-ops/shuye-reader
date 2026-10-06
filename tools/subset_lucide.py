"""Extract the used default Lucide icons from audited 3.1.22, without editing caches."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

from fontTools import subset
from fontTools.ttLib import TTFont

FONT_SHA = "124ecc64b91a158fc519eefdaaead89a2d9e2c39b6f9c8429c5584c93a0be451"
CODE_SHA = "f489be5a42bd3d6de6a09eafb66ca2f0b8d98ee3bab1fde346b5e2b936f23e89"
ARCHIVE_SHA = "abfff57c1f4de40204e25a15809d566b17c1a085d2aa58e00203649758c7fed4"


def build(source: Path, root: Path) -> None:
    code = source / "lib/lucide_icons.dart"
    font_path = source / "assets/lucide.ttf"
    for path, expected in [(code, CODE_SHA), (font_path, FONT_SHA)]:
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError(f"Unverified upstream input: {path.name}")
    used = sorted(set(re.findall(r"LucideIcons\.(\w+)",
                                 (root / "lib/app_icons.dart").read_text(encoding="utf-8"))))
    declarations = dict(re.findall(
        r"static const IconData (\w+)\s*=\s*(const IconData\(.*?\));",
        code.read_text(encoding="utf-8"), re.S))
    points = set()
    definitions = []
    for name in used:
        expression = declarations[name].removeprefix('const ')
        if "fontFamily: 'Lucide'" not in expression:
            raise ValueError(f"Only default Lucide weight is supported: {name}")
        points.add(int(re.search(r"IconData\((\d+)", expression).group(1)))
        definitions.append(f"  static const IconData {name} = {expression};")
    destination = root / "third_party/lucide_icons_flutter"
    (destination / "lib").mkdir(parents=True, exist_ok=True)
    (destination / "assets").mkdir(exist_ok=True)
    dart = "// Generated from lucide_icons_flutter 3.1.22; see README.md and LICENSE.\n"
    dart += "import 'package:flutter/widgets.dart';\n\n@staticIconProvider\nclass LucideIcons {\n"
    dart += "  const LucideIcons._();\n" + "\n".join(definitions) + "\n}\n"
    (destination / "lib/lucide_icons.dart").write_text(dart, encoding="utf-8")
    font = TTFont(font_path, recalcTimestamp=False)
    options = subset.Options()
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.notdef_glyph = True
    worker = subset.Subsetter(options=options)
    worker.populate(unicodes=points)
    worker.subset(font)
    output = destination / "assets/lucide.ttf"
    font.save(output)
    shutil.copy2(source / "LICENSE", destination / "LICENSE")
    report = {"upstream_version": "3.1.22", "archive_sha256": ARCHIVE_SHA,
              "source_font_sha256": FONT_SHA, "source_code_sha256": CODE_SHA,
              "icons": used, "glyph_codepoints": len(points),
              "font_bytes": output.stat().st_size,
              "font_sha256": hashlib.sha256(output.read_bytes()).hexdigest()}
    (destination / "audit.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "icons"}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Unmodified 3.1.22 package directory")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    build(args.source, args.root)
