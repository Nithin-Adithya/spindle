#!/usr/bin/env python3
"""Turn Localization/keys.txt plus one <language>.txt per language into .lproj folders."""
import pathlib
import sys

source, destination = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
keys = (source / "keys.txt").read_text(encoding="utf-8").splitlines()


def escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


for path in sorted(source.glob("*.txt")):
    language = path.stem
    values = keys if language == "keys" else path.read_text(encoding="utf-8").splitlines()
    if len(values) != len(keys):
        sys.exit(f"{path.name}: {len(values)} lines, expected {len(keys)}")
    folder = destination / (("en" if language == "keys" else language) + ".lproj")
    folder.mkdir(parents=True, exist_ok=True)
    lines = [f'"{escape(key)}" = "{escape(value)}";' for key, value in zip(keys, values)]
    (folder / "Localizable.strings").write_text("\n".join(lines) + "\n", encoding="utf-8")
