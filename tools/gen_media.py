#!/usr/bin/env python3
"""Generates the Azeroth Ante textures in AzerothAnte/Media (stdlib only).

Output is uncompressed 32-bit BGRA TGA (type 2, descriptor 0x28: 8 alpha bits,
top-left origin). Shapes are point tests sampled on a 4x supersampled grid and
averaged down for anti-aliasing. Suits are pure white with the shape in alpha so
the UI can tint them with SetVertexColor.

Usage: python3 tools/gen_media.py [--png-dir DIR]   (PNG previews are optional)
"""
import math
import os
import struct
import sys
import zlib

SS = 4  # supersampling factor per axis
MEDIA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "AzerothAnte", "Media")


# ---------------------------------------------------------------- shapes
# Each suit function takes (u, v) in [0,1]^2 (v grows downward) and returns alpha 0..1.

def _heart(x, y):
    """Classic heart curve; y up, roughly x in [-1.15,1.15], y in [-1,1.25]."""
    return (x * x + y * y - 1) ** 3 - x * x * y ** 3 <= 0


def _stem(u, v, top, bottom, half_top, half_base):
    """Flared stem with a concave curve, widest at the base."""
    if not (top <= v <= bottom):
        return False
    t = (v - top) / (bottom - top)
    return abs(u - 0.5) <= half_top + (half_base - half_top) * t ** 3


def _spade_body(u, v):
    # Heart flipped vertically: tip at the top.
    x = (u - 0.5) * 3.0
    y = (v - 0.39) * 3.0
    return _heart(x, y)


def spade(u, v):
    if _spade_body(u, v) or _stem(u, v, 0.55, 0.93, 0.03, 0.2):
        # Sword-hilt cut-out: blade slit down the middle with a crossguard.
        blade = abs(u - 0.5) <= 0.016 and 0.24 <= v <= 0.56
        guard = abs(u - 0.5) <= 0.085 and 0.43 <= v <= 0.455
        pommel = (u - 0.5) ** 2 + (v - 0.565) ** 2 <= 0.026 ** 2
        if blade or guard or pommel:
            return 0.0
        return 1.0
    return 0.0


def heart(u, v):
    x = (u - 0.5) * 2.5
    y = (0.5 - v) * 2.5 + 0.12
    return 1.0 if _heart(x, y) else 0.0


def _circle(u, v, cx, cy, r):
    return (u - cx) ** 2 + (v - cy) ** 2 <= r * r


def club(u, v):
    lobes = (
        _circle(u, v, 0.5, 0.26, 0.2)
        or _circle(u, v, 0.285, 0.55, 0.2)
        or _circle(u, v, 0.715, 0.55, 0.2)
    )
    # Fills the gap between the three lobes.
    core = _circle(u, v, 0.5, 0.47, 0.15)
    return 1.0 if (lobes or core or _stem(u, v, 0.5, 0.93, 0.03, 0.2)) else 0.0


def _rhombus(u, v, hw, hh):
    return abs(u - 0.5) / hw + abs(v - 0.5) / hh


def diamond(u, v):
    d = _rhombus(u, v, 0.34, 0.45)
    if d > 1.0:
        return 0.0
    # Gem facets: inner rhombus outline and a girdle line, cut to low alpha.
    inner = _rhombus(u, v, 0.34 * 0.55, 0.45 * 0.55)
    ring = abs(inner - 1.0) <= 0.07
    girdle = abs(v - 0.5) <= 0.012 and abs(u - 0.5) <= 0.34 * 0.55
    if ring or girdle:
        return 0.3
    return 1.0


SUITS = {"Suit_S": spade, "Suit_H": heart, "Suit_C": club, "Suit_D": diamond}


# ------------------------------------------------------------- card back
NAVY = (22, 18, 52)
NAVY_LIGHT = (34, 28, 76)
GOLD = (214, 175, 62)
GOLD_DARK = (150, 118, 38)
BACK_W, BACK_H = 128, 256
CORNER = 9.0  # corner radius in px; corners outside are transparent


def _in_round_rect(px, py, w, h, r, inset=0.0):
    x0, y0, x1, y1 = inset, inset, w - inset, h - inset
    rr = max(r - inset, 0.0)
    if px < x0 or px > x1 or py < y0 or py > y1:
        return False
    cx = min(max(px, x0 + rr), x1 - rr)
    cy = min(max(py, y0 + rr), y1 - rr)
    return (px - cx) ** 2 + (py - cy) ** 2 <= rr * rr


def card_back(px, py):
    """Returns (r, g, b, a) at a point in pixel units (floats)."""
    w, h = BACK_W, BACK_H
    if not _in_round_rect(px, py, w, h, CORNER):
        return (0, 0, 0, 0)
    # Outer 4px gold border.
    if not _in_round_rect(px, py, w, h, CORNER, 4.0):
        return GOLD + (255,)
    # Thin inner gold line, 1px wide at 8px inset.
    if _in_round_rect(px, py, w, h, CORNER, 7.0) and not _in_round_rect(px, py, w, h, CORNER, 8.0):
        return GOLD_DARK + (255,)
    cx, cy = w / 2.0, h / 2.0
    dx, dy = px - cx, py - cy
    # Central emblem: gold diamond ring, inner navy diamond, gold gem, 4-point star.
    d = abs(dx) / 38.0 + abs(dy) / 62.0
    if 0.93 <= d <= 1.0:
        return GOLD + (255,)
    if 0.80 <= d <= 0.84:
        return GOLD_DARK + (255,)
    # four-point star (astroid) at the centre
    if abs(dx) ** (2.0 / 3.0) + abs(dy) ** (2.0 / 3.0) <= 17.0 ** (2.0 / 3.0):
        return GOLD + (255,)
    if d < 0.8:
        # Faceted gem look: small gold diamonds on a lattice inside the emblem.
        if 2.0 < abs(dy) / 1.0 and abs(abs(dx) / 9.0 + abs(dy) / 14.0 - 2.6) < 0.06:
            return GOLD_DARK + (255,)
        return NAVY_LIGHT + (255,)
    # Background lattice of faint diamonds.
    lx = ((px + py) / 16.0) % 1.0
    ly = ((px - py) / 16.0) % 1.0
    if min(lx, 1 - lx) < 0.04 or min(ly, 1 - ly) < 0.04:
        return NAVY_LIGHT + (255,)
    return NAVY + (255,)


# ---------------------------------------------------------------- output
def render(width, height, fn):
    """Supersample fn(sample_x, sample_y) -> (r,g,b,a) and average to RGBA bytes.
    Colour is alpha-weighted so transparent samples do not bleed black."""
    out = bytearray()
    n = SS * SS
    for y in range(height):
        for x in range(width):
            r = g = b = a = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    cr, cg, cb, ca = fn(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS)
                    r += cr * ca
                    g += cg * ca
                    b += cb * ca
                    a += ca
            if a > 0:
                out += bytes((round(r / a), round(g / a), round(b / a), round(a / n)))
            else:
                out += bytes((255, 255, 255, 0))
    return bytes(out)


def render_suit(fn, size=64):
    def sample(px, py):
        return (255, 255, 255, round(255 * fn(px / size, py / size)))
    return render(size, size, sample)


def write_tga(path, width, height, rgba):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    bgra = bytearray(len(rgba))
    bgra[0::4] = rgba[2::4]
    bgra[1::4] = rgba[1::4]
    bgra[2::4] = rgba[0::4]
    bgra[3::4] = rgba[3::4]
    with open(path, "wb") as f:
        f.write(header + bytes(bgra))


def write_png(path, width, height, rgba, bg=None):
    """Preview PNG. bg=(r,g,b) composites over a solid colour."""
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        row = rgba[y * width * 4:(y + 1) * width * 4]
        if bg:
            for i in range(0, len(row), 4):
                a = row[i + 3] / 255.0
                raw += bytes(round(row[i + k] * a + bg[k] * (1 - a)) for k in range(3))
        else:
            raw += row
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    color_type = 2 if bg else 6
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw))) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def main(argv):
    png_dir = None
    if "--png-dir" in argv:
        png_dir = argv[argv.index("--png-dir") + 1]
        os.makedirs(png_dir, exist_ok=True)
    os.makedirs(MEDIA, exist_ok=True)
    jobs = [(name, 64, 64, render_suit(fn)) for name, fn in SUITS.items()]
    jobs.append(("CardBack", BACK_W, BACK_H, render(BACK_W, BACK_H, card_back)))
    for name, w, h, rgba in jobs:
        write_tga(os.path.join(MEDIA, name + ".tga"), w, h, rgba)
        print("wrote %s.tga (%dx%d)" % (name, w, h))
        if png_dir:
            write_png(os.path.join(png_dir, name + ".png"), w, h, rgba, bg=(70, 70, 80) if name.startswith("Suit") else None)


if __name__ == "__main__":
    main(sys.argv[1:])
