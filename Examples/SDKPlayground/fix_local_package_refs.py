#!/usr/bin/env python3
"""
XcodeGen (as of 2.45) omits `package = <XCLocalSwiftPackageReference>` on
XCSwiftPackageProductDependency entries, which makes Xcode report
"Missing package product 'XMPPChatCore' / 'XMPPChatUI'".

Run after: xcodegen generate

Usage:
  python3 fix_local_package_refs.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


def main() -> int:
    pbx = Path(__file__).resolve().parent / "SDKPlayground.xcodeproj" / "project.pbxproj"
    text = pbx.read_text(encoding="utf-8")

    m = re.search(
        r"(\w{24})\s+/\*\s+XCLocalSwiftPackageReference\s+\"([^\"]+)\"\s+\*/",
        text,
    )
    if not m:
        print("error: could not find XCLocalSwiftPackageReference in project.pbxproj", file=sys.stderr)
        return 1

    uuid, rel_path = m.group(1), m.group(2)
    pkg_line = f"\t\t\tpackage = {uuid} /* XCLocalSwiftPackageReference \"{rel_path}\" */;"

    def inject_after_isa(match: re.Match[str]) -> str:
        block = match.group(0)
        if "package = " in block:
            return block
        return match.group(1) + pkg_line + "\n" + match.group(2)

    # Each product dependency: { isa; [optional broken]; productName; };
    pattern = re.compile(
        r"(\t\t\w{24} /\* XMPPChat(?:Core|UI) \*/ = \{\n"
        r"\t\t\tisa = XCSwiftPackageProductDependency;\n)"
        r"(\t\t\tproductName = XMPPChat(?:Core|UI);\n)",
        re.MULTILINE,
    )
    new_text, n = pattern.subn(inject_after_isa, text)
    if n == 0:
        # Already patched: each XMPPChat product block has `package =` between isa and productName.
        if re.search(
            r"isa = XCSwiftPackageProductDependency;\n\t\t\tpackage = .+\n\t\t\tproductName = XMPPChatCore;",
            text,
        ):
            print("OK: XMPPChat package links already present.")
            return 0
        print("error: could not patch XMPPChat product dependencies", file=sys.stderr)
        return 1

    pbx.write_text(new_text, encoding="utf-8")
    print(f"Patched {n} Swift package product dependency block(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
