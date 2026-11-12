#!/usr/bin/env python3
"""Generate emoji_width_generated.odin from Unicode 15.1 emoji-data.txt.

Usage: python3 tools/generate_emoji_width.py /path/to/emoji-data.txt > emoji_width_generated.odin
Source: https://www.unicode.org/Public/15.1.0/ucd/emoji/emoji-data.txt
"""
import sys

source = open(sys.argv[1], encoding="utf-8").read()
if "Emoji Version 15.1" not in source:
    sys.exit("expected Unicode Emoji 15.1 emoji-data.txt")

ranges = []
for line in source.splitlines():
    fields = line.split("#", 1)[0].split(";")
    if len(fields) != 2 or fields[1].strip() != "Emoji_Presentation":
        continue
    ends = fields[0].strip().split("..")
    lo, hi = int(ends[0], 16), int(ends[-1], 16)
    if ranges and lo <= ranges[-1][1] + 1:
        ranges[-1] = (ranges[-1][0], max(hi, ranges[-1][1]))
    else:
        ranges.append((lo, hi))

print("// Generated from Unicode 15.1.0 emoji-data.txt; do not edit.")
print("// See tools/generate_emoji_width.py. Unicode data: https://unicode.org/license.txt")
print("package odintui\n")
print("@(private)\nemoji_presentation_ranges := [?][2]rune{")
for lo, hi in ranges:
    print(f"\t{{0x{lo:X}, 0x{hi:X}}},")
print("}")
