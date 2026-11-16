#!/usr/bin/env python3
"""Lists host UI strings that have no Korean translation.

Reads string literals from lines of apps/mac-host/Sources/VeilHostShell that build UI text (Text, Button,
Label, .help, title:, detail:, String(localized:), ...) and reports the ones missing from
Resources/ko.lproj/Localizable.strings. A literal with interpolation is matched against the format keys.

It is a reading aid, not a gate: it cannot tell a string shown to people from one in a diagnostic, and it
does not see strings built at runtime. Run it from the repository root:

    script/audit_localization.py            # counts per file
    script/audit_localization.py --list     # every string
"""
import collections
import glob
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "apps", "mac-host")
STRINGS = os.path.join(ROOT, "Resources", "ko.lproj", "Localizable.strings")
KEY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=', re.M)
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
UI_CONTEXT = re.compile(
    r"(\bText\(|\bButton\(|\bLabel\(|\bToggle\(|\bPicker\(|\bTextField\(|\bSection\(|\bMenu\(|\bLink\("
    r"|\.help\(|\.navigationTitle\(|\.accessibilityLabel\(|\.accessibilityHint\(|String\(localized:"
    r"|Text\(localized:|\btitle:|\bsubtitle:|\bdetail:|\bmessage:|displayMessage\s*=)"
)
SYMBOL_ARGUMENT = re.compile(r'(systemImage|symbolName|systemName):\s*"[^"]*"')
FORMAT_SPECIFIER = re.compile(r"%(?:\\\d+\\\$)?(?:lld|ld|d|@|lf|f)")


def main() -> int:
    with open(STRINGS, encoding="utf-8") as file:
        keys = {match.group(1).replace('\\"', '"') for match in KEY.finditer(file.read())}
    formats = [
        re.compile("^" + FORMAT_SPECIFIER.sub(r"\\\\\\(.+?\\)", re.escape(key)) + "$")
        for key in keys
        if "%" in key
    ]

    missing = collections.OrderedDict()
    for path in sorted(glob.glob(os.path.join(ROOT, "Sources", "VeilHostShell", "**", "*.swift"), recursive=True)):
        with open(path, encoding="utf-8") as file:
            for number, line in enumerate(file, 1):
                if line.strip().startswith("//") or not UI_CONTEXT.search(line):
                    continue
                for match in LITERAL.finditer(SYMBOL_ARGUMENT.sub("", line)):
                    literal = match.group(1)
                    text = literal.replace('\\"', '"')
                    # Identifiers, symbol names, and strings with no word in them are not UI text.
                    if not re.search(r"[A-Za-z]{3}", literal) or re.fullmatch(r"[a-z0-9_.\-:/]+", literal):
                        continue
                    if text in keys or ("\\(" in literal and any(pattern.match(text) for pattern in formats)):
                        continue
                    missing.setdefault(literal, (os.path.relpath(path, ROOT), number))

    print(f"{len(keys)} Korean strings; {len(missing)} UI literals without one")
    if "--list" in sys.argv:
        for literal, (path, number) in missing.items():
            print(f"{path}:{number}: {literal}")
    else:
        counts = collections.Counter(path for path, _ in missing.values())
        for path, count in counts.most_common():
            print(f"{count:4d}  {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
