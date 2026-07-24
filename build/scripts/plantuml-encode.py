#!/usr/bin/env python3
"""
Encode PlantUML source into the URL form the PlantUML server understands.

The PlantUML server accepts URLs of the form
    https://www.plantuml.com/plantuml/{svg|png}/{encoded}
where {encoded} is the source compressed with raw deflate, then base64-encoded
with PlantUML's custom alphabet. This script is a small wrapper around that
encoding so the AUTHENTICATION.html generator can compute stable URLs from
PlantUML source.

Run with `python3 plantuml-encode.py < diagram.puml`
or pipe via heredoc.
"""

from __future__ import annotations

import sys
import zlib

PLANTUML_ALPHABET = (
    "0123456789"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "abcdefghijklmnopqrstuvwxyz"
    "-_"
)


def _encode_3bytes(b1: int, b2: int, b3: int) -> str:
    c1 = b1 >> 2
    c2 = ((b1 & 0x3) << 4) | (b2 >> 4)
    c3 = ((b2 & 0xF) << 2) | (b3 >> 6)
    c4 = b3 & 0x3F
    return (
        PLANTUML_ALPHABET[c1]
        + PLANTUML_ALPHABET[c2]
        + PLANTUML_ALPHABET[c3]
        + PLANTUML_ALPHABET[c4]
    )


def encode(source: str) -> str:
    data = source.encode("utf-8")
    compressor = zlib.compressobj(9, zlib.DEFLATED, -zlib.MAX_WBITS)
    compressed = compressor.compress(data) + compressor.flush()
    result = []
    for i in range(0, len(compressed), 3):
        b1 = compressed[i]
        b2 = compressed[i + 1] if i + 1 < len(compressed) else 0
        b3 = compressed[i + 2] if i + 2 < len(compressed) else 0
        result.append(_encode_3bytes(b1, b2, b3))
    return "".join(result)


def url(source: str, fmt: str = "svg") -> str:
    return f"https://www.plantuml.com/plantuml/{fmt}/{encode(source)}"


if __name__ == "__main__":
    src = sys.stdin.read()
    print(url(src))
