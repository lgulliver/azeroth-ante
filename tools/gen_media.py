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
CANVAS_H = 256        # textures are 128x256 (power of two); cards use the top 128x179 (5:7)
BACK_W, BACK_H = 128, 179
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


# ------------------------------------------------------------ v2 helpers
import colorsys

FACE_W, FACE_H = 128, 179
CLEAR = (0, 0, 0, 0)
PARCH = (238, 224, 182)
PARCH_DARK = (212, 190, 140)


def _clamp(v):
    return max(0, min(255, int(round(v))))


def _mix(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(c1[i] + (c2[i] - c1[i]) * t for i in range(3))


def _shade(c, k):
    return tuple(_clamp(v * k) for v in c)


def _rgb(c, a=255):
    return (_clamp(c[0]), _clamp(c[1]), _clamp(c[2]), _clamp(a))


def _hash(x, y, seed=0):
    n = (x * 374761393 + y * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def _vnoise(x, y, k, seed=0):
    """Smooth value noise in 0..1 with feature size k (pixels)."""
    gx, gy = x / k, y / k
    ix, iy = math.floor(gx), math.floor(gy)
    fx, fy = gx - ix, gy - iy
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a = _hash(ix, iy, seed)
    b = _hash(ix + 1, iy, seed)
    c = _hash(ix, iy + 1, seed)
    d = _hash(ix + 1, iy + 1, seed)
    return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy


def _edge_dist(px, py, w, h, r):
    """Distance inwards from the rounded-rect edge; negative outside."""
    dx, dy = min(px, w - px), min(py, h - py)
    if dx < r and dy < r:
        return r - math.hypot(r - dx, r - dy)
    return min(dx, dy)


def _seg_dist(px, py, x0, y0, x1, y1):
    vx, vy = x1 - x0, y1 - y0
    t = ((px - x0) * vx + (py - y0) * vy) / (vx * vx + vy * vy)
    t = max(0.0, min(1.0, t))
    return math.hypot(px - (x0 + vx * t), py - (y0 + vy * t))


def _diamond_at(px, py, cx, cy, r):
    return abs(px - cx) + abs(py - cy) <= r


RUNES = [
    [(.3, .1, .3, .9), (.3, .4, .7, .2), (.3, .65, .7, .45)],
    [(.3, .9, .3, .1), (.3, .1, .7, .35), (.7, .35, .7, .9)],
    [(.3, .1, .3, .9), (.3, .3, .7, .5), (.7, .5, .3, .7)],
    [(.3, .1, .3, .9), (.3, .15, .7, .35), (.3, .45, .7, .65)],
    [(.2, .1, .8, .9), (.8, .1, .2, .9)],
    [(.65, .1, .35, .35), (.35, .35, .65, .65), (.65, .65, .35, .9)],
    [(.2, .1, .2, .9), (.8, .1, .8, .9), (.2, .1, .8, .9), (.8, .1, .2, .9)],
    [(.5, .1, .8, .5), (.8, .5, .5, .9), (.5, .9, .2, .5), (.2, .5, .5, .1)],
]


def _rune(px, py, cx, cy, size, idx, width=0.9):
    if abs(px - cx) > size * 0.6 or abs(py - cy) > size * 0.6:
        return False
    u, v = (px - cx) / size + 0.5, (py - cy) / size + 0.5
    for x0, y0, x1, y1 in RUNES[idx % len(RUNES)]:
        if _seg_dist(u, v, x0, y0, x1, y1) * size <= width:
            return True
    return False


def _rune_row(px, py, cy, x0, count, step, size, first=0, width=0.9):
    if abs(py - cy) > size * 0.6:
        return False
    for i in range(count):
        if _rune(px, py, x0 + i * step, cy, size, first + i, width):
            return True
    return False


# ------------------------------------------------------------ card faces
def parchment(px, py, d):
    n = _vnoise(px, py, 7, 1) * 0.6 + _vnoise(px, py, 2.5, 2) * 0.4
    c = _mix((230, 213, 168), (246, 235, 200), n)
    if d < 24:
        c = _mix(c, PARCH_DARK, 0.55 * (1 - d / 24.0))
    return c


def _corner_ornament(px, py, inset, col, dark, skip_br=False):
    """Gold diamonds in the free corners (top-left stays clear for the rank)."""
    corners = [(FACE_W - inset, inset), (inset, FACE_H - inset), (FACE_W - inset, FACE_H - inset)]
    for cx, cy in corners[:2] if skip_br else corners:
        if _diamond_at(px, py, cx, cy, 5.0):
            return dark if _diamond_at(px, py, cx, cy, 2.0) else col
    return None


def parchment_face(px, py, frame=None, tint=None, clover=False):
    """Parchment card face. frame: None | an (r,g,b) band colour | 'rainbow'."""
    w, h = FACE_W, FACE_H
    d = _edge_dist(px, py, w, h, CORNER)
    if d < 0:
        return CLEAR
    if d < 3.0:
        return _rgb(GOLD)
    if d < 4.0:
        return _rgb(GOLD_DARK)
    inner = 4.0
    if frame is not None:
        if d < 10.0:
            if frame == "rainbow":
                hue = (math.atan2(py - h / 2.0, px - w / 2.0) / (2 * math.pi) + 0.5) % 1.0
                band = tuple(v * 255 for v in colorsys.hsv_to_rgb(hue, 0.85, 0.95))
            else:
                band = frame
            t = (d - 4.0) / 6.0
            band = _mix(_shade(band, 1.25), _shade(band, 0.78), abs(t - 0.5) * 2.0 * 0.0 + t * 0.7)
            if d < 5.0:
                band = _mix(band, GOLD, 0.5)
            return _rgb(band)
        if d < 11.0:
            return _rgb(GOLD_DARK)
        inner = 11.0
    elif 7.0 <= d < 8.0:
        return _rgb(GOLD_DARK)
    orn = _corner_ornament(px, py, 20.0, GOLD, GOLD_DARK, skip_br=clover)
    if orn:
        return _rgb(orn)
    c = parchment(px, py, d)
    if tint:
        c = _mix(c, tint, 0.2)
    # faint rune ring and rune row, kept low-contrast so the rank stays readable
    ring = abs(math.hypot(px - w / 2.0, py - h / 2.0) - 44.0)
    if ring < 0.9 or _rune_row(px, py, h - 22.0, 44.0, 4, 14.0, 9.0, 2):
        c = _shade(c, 0.9)
    if clover:
        cl = _clover(px, py, 101.0, 152.0)
        if cl:
            return _rgb(cl)
    return _rgb(c)


def _clover(px, py, cx, cy):
    leaf = 5.4
    off = 5.2
    green, vein = (40, 148, 62), (22, 96, 40)
    if _seg_dist(px, py, cx, cy, cx + 8, cy + 13) <= 1.1:
        return vein
    for ox, oy in ((-off, 0), (off, 0), (0, -off), (0, off)):
        if math.hypot(px - (cx + ox), py - (cy + oy)) <= leaf:
            if _seg_dist(px, py, cx, cy, cx + ox * 1.5, cy + oy * 1.5) <= 0.6:
                return vein
            lit = _mix(green, (120, 210, 110), max(0.0, 0.5 - (px - cx + py - cy) / 30.0) * 0.5)
            return lit if math.hypot(px - (cx + ox), py - (cy + oy)) <= leaf - 0.9 else vein
    return None


def face_plain(px, py):
    return parchment_face(px, py)


def face_bonus(px, py):
    return parchment_face(px, py, frame=(44, 104, 214), tint=(60, 120, 230))


def face_mult(px, py):
    return parchment_face(px, py, frame=(196, 42, 44), tint=(230, 70, 60))


def face_wild(px, py):
    return parchment_face(px, py, frame="rainbow")


def face_lucky(px, py):
    return parchment_face(px, py, frame=(40, 130, 56), tint=(70, 170, 80), clover=True)


def face_gold(px, py):
    w, h = FACE_W, FACE_H
    d = _edge_dist(px, py, w, h, CORNER)
    if d < 0:
        return CLEAR
    if d < 3.0:
        return _rgb((250, 226, 130))
    if d < 4.0:
        return _rgb(GOLD_DARK)
    if d < 10.0:
        # filigree band: diagonal scroll work between two gold lines
        wave = 0.5 + 0.5 * math.sin((px + py) * 0.55)
        wave2 = 0.5 + 0.5 * math.sin((px - py) * 0.55)
        c = _mix((150, 112, 34), (236, 200, 84), wave * wave2 * 1.6)
        return _rgb(c)
    if d < 11.0:
        return _rgb(GOLD_DARK)
    t = py / float(h)
    c = _mix((238, 204, 98), (212, 168, 58), t)
    c = _mix(c, (255, 236, 150), (_vnoise(px, py, 9, 3) - 0.5) * 0.3 + 0.0)
    s = (px * 0.7 + py * 0.3) % 100.0
    if 36 < s < 52:
        c = _mix(c, (255, 244, 190), 0.35 * (1 - abs(s - 44.0) / 8.0))
    lx = ((px + py) / 16.0) % 1.0
    ly = ((px - py) / 16.0) % 1.0
    if min(lx, 1 - lx) < 0.035 or min(ly, 1 - ly) < 0.035:
        c = _shade(c, 0.9)
    orn = _corner_ornament(px, py, 20.0, (255, 240, 170), GOLD_DARK)
    if orn:
        return _rgb(orn)
    return _rgb(c)


def face_steel(px, py):
    w, h = FACE_W, FACE_H
    d = _edge_dist(px, py, w, h, CORNER)
    if d < 0:
        return CLEAR
    if d < 3.0:
        return _rgb((214, 220, 230))
    if d < 6.0:
        return _rgb((72, 76, 88))
    if d < 7.0:
        return _rgb((190, 196, 208))
    # brushed: long horizontal streaks
    streak = _vnoise(px / 70.0, py * 1.0, 1.0, 5) * 0.65 + _vnoise(px / 25.0, py * 1.0, 1.0, 6) * 0.35
    c = _mix((128, 134, 146), (176, 182, 194), streak)
    c = _mix(c, (200, 206, 216), max(0.0, 0.5 - abs((px * 0.6 + py * 0.4) % 120 - 60) / 25.0) * 0.5)
    for cx, cy in ((w - 16.0, 16.0), (16.0, h - 16.0), (w - 16.0, h - 16.0)):
        r = math.hypot(px - cx, py - cy)
        if r <= 4.0:
            return _rgb(_mix((235, 238, 245), (80, 84, 96), r / 4.0 + (0.0 if px < cx else 0.2)))
    return _rgb(c)


def face_stone(px, py):
    w, h = FACE_W, FACE_H
    d = _edge_dist(px, py, w, h, 6.0)
    if d < 0:
        return CLEAR
    if d < 2.5:
        return _rgb((150, 146, 140))
    if d < 5.0:
        return _rgb((54, 52, 52))
    n = _vnoise(px, py, 14, 7) * 0.5 + _vnoise(px, py, 5, 8) * 0.3 + _vnoise(px, py, 1.6, 9) * 0.2
    c = _mix((78, 76, 76), (128, 124, 118), n)
    # chiselled cracks
    for x0, y0, x1, y1 in ((20, 28, 60, 64), (60, 64, 54, 98), (54, 98, 96, 123),
                           (96, 123, 104, 158), (60, 64, 100, 59), (30, 140, 70, 119)):
        dd = _seg_dist(px, py, x0, y0, x1, y1)
        if dd < 1.1:
            c = _shade(c, 0.45)
        elif dd < 2.0:
            c = _shade(c, 1.1)
    # carved slab panel with a recessed rune medallion
    if 9.0 <= d < 10.0:
        c = _shade(c, 0.7)
    r = math.hypot(px - w / 2.0, py - h / 2.0)
    if 30.0 <= r < 31.5:
        c = _shade(c, 0.6)
    elif 31.5 <= r < 33.0:
        c = _shade(c, 1.2)
    return _rgb(c)


def face_glass(px, py):
    w, h = FACE_W, FACE_H
    d = _edge_dist(px, py, w, h, CORNER)
    if d < 0:
        return CLEAR
    if d < 3.0:
        return _rgb((150, 236, 250), 255)
    if d < 4.0:
        return _rgb((60, 160, 190), 230)
    if 7.0 <= d < 8.0:
        return _rgb((220, 250, 255), 190)
    c = _mix((120, 218, 240), (170, 240, 252), py / float(h))
    a = 80.0
    s = (px * 0.8 - py * 0.6) % 90.0
    # two bright glints running diagonally, like light on a pane
    for centre, width, gain in ((20.0, 6.0, 90.0), (36.0, 2.5, 70.0)):
        k = max(0.0, 1.0 - abs(s - centre) / width)
        a += gain * k
        c = _mix(c, (255, 255, 255), k)
    a += (_vnoise(px, py, 8, 10) - 0.5) * 16
    return _rgb(c, a)


FACES = {
    "Face_Plain": face_plain,
    "Face_BONUS": face_bonus,
    "Face_MULT": face_mult,
    "Face_WILD": face_wild,
    "Face_GLASS": face_glass,
    "Face_STEEL": face_steel,
    "Face_STONE": face_stone,
    "Face_GOLD": face_gold,
    "Face_LUCKY": face_lucky,
}


# ----------------------------------------------------------------- seals
SEAL_SIZE = 32
SEALS = {
    "GOLD": ((236, 190, 56), (150, 104, 20)),
    "RED": ((200, 36, 40), (110, 14, 22)),
    "BLUE": ((52, 110, 220), (22, 52, 130)),
    "PURPLE": ((150, 70, 200), (80, 28, 124)),
}


def _glyph(kind, x, y):
    """Emblem in a -1..1 box (y down)."""
    if kind == "GOLD":  # four-point star
        return abs(x) ** 0.7 + abs(y) ** 0.7 <= 0.9 ** 0.7
    if kind == "RED":  # ruby
        return abs(x) / 0.62 + abs(y) / 0.85 <= 1.0
    if kind == "BLUE":  # eye / drop
        return math.hypot(x, y) <= 0.62 and not math.hypot(x, y) <= 0.22
    # PURPLE: crescent
    return math.hypot(x, y) <= 0.75 and math.hypot(x - 0.38, y + 0.1) > 0.62


def seal_fn(kind):
    base, dark = SEALS[kind]

    def fn(px, py):
        cx = cy = SEAL_SIZE / 2.0
        dx, dy = px - cx, py - cy
        r = math.hypot(dx, dy)
        ang = math.atan2(dy, dx)
        edge = 13.6 + 1.1 * math.cos(9 * ang)
        if r > edge:
            return CLEAR
        light = max(0.0, min(1.0, 0.5 - (dx + dy) / (2.0 * edge) * 0.9))
        c = _mix(dark, base, 0.35 + 0.65 * light)
        if r > edge - 1.2:
            c = _shade(c, 0.7)
        elif 9.2 <= r < 10.4:
            c = _mix(dark, base, 0.2 + 0.5 * light)  # pressed rim
        elif r < 9.2:
            c = _mix(base, dark, 0.12)
            if _glyph(kind, dx / 6.2, dy / 6.2):
                c = _mix(dark, (255, 240, 210), 0.14 + 0.5 * light * 0.0)
                c = _shade(c, 0.85)
            elif _glyph(kind, (dx + 0.8) / 6.2, (dy + 0.8) / 6.2):
                c = _mix(c, (255, 255, 255), 0.45)
        return _rgb(c)
    return fn


# -------------------------------------------------------------- editions
def ed_sheen(px, py):
    """White diagonal sweep for Foil: a broad soft band plus a thin trailing line."""
    d = _edge_dist(px, py, FACE_W, FACE_H, CORNER)
    if d < 0:
        return CLEAR
    s = px + py * 0.5  # diagonal coordinate, ~0..192
    k = max(0.0, 1.0 - abs(s - 96.0) / 52.0)
    a = 255 * k * k * (3 - 2 * k)
    k2 = max(0.0, 1.0 - abs(s - 46.0) / 5.0)
    a = max(a, 200 * k2)
    return (255, 255, 255, _clamp(a))


def ed_holo(px, py):
    """Rainbow diagonal band for Holographic."""
    d = _edge_dist(px, py, FACE_W, FACE_H, CORNER)
    if d < 0:
        return CLEAR
    s = px + py * 0.5
    k = max(0.0, 1.0 - abs(s - 100.0) / 62.0)
    a = 255 * k ** 0.8
    hue = ((s - 40.0) / 120.0) % 1.0
    r, g, b = colorsys.hsv_to_rgb(hue, 0.75, 1.0)
    # fine glitter lines running with the band
    if int(s) % 9 < 1:
        a = min(255, a + 55 * (1 if k > 0.05 else 0))
    return (_clamp(r * 255), _clamp(g * 255), _clamp(b * 255), _clamp(a))


# ----------------------------------------------------------- consumables
def consumable_scroll(px, py):
    w, h = FACE_W, FACE_H
    # rolled rods at the top and bottom
    for y0 in (4.0, h - 22.0):
        if y0 <= py <= y0 + 18.0:
            u = (py - y0) / 18.0
            cap = (px < 8.0 or px > w - 8.0)
            rx = min(px, w - px)
            if rx < 2.0 + 4.0 * (1 - math.sin(u * math.pi)):
                return CLEAR
            shade = 0.55 + 0.75 * math.sin(u * math.pi) ** 1.4
            wood = _mix((96, 58, 30), (160, 104, 56), _vnoise(px, py * 4.0, 20, 11))
            c = _shade(wood, shade)
            if cap:
                c = _shade(_mix(GOLD_DARK, (250, 226, 130), math.sin(u * math.pi)), 1.0)
            return _rgb(c)
    if not (10.0 <= px <= w - 10.0 and 21.0 <= py <= h - 20.0):
        return CLEAR
    d = min(px - 10.0, w - 10.0 - px, py - 21.0, h - 20.0 - py)
    n = _vnoise(px, py, 7, 12) * 0.6 + _vnoise(px, py, 2.5, 13) * 0.4
    c = _mix((232, 210, 158), (248, 232, 190), n)
    c = _mix(c, (170, 120, 60), 0.5 * max(0.0, 1 - d / 14.0))
    if py < 30:
        c = _shade(c, 0.72 + 0.28 * (py - 21.0) / 9.0)  # shadow under the rod
    elif py > h - 29.0:
        c = _shade(c, 0.72 + 0.28 * (h - 20.0 - py) / 9.0)
    if 8.0 <= d < 9.0:
        c = GOLD_DARK
    if 11.0 <= d < 11.8:
        c = _mix(c, GOLD, 0.6)
    if _rune_row(px, py, 40.0, 28.0, 5, 18.0, 9.0, 0, 0.9) or _rune_row(px, py, h - 40.0, 28.0, 5, 18.0, 9.0, 3, 0.9):
        c = _mix(c, (130, 70, 30), 0.65)
    return _rgb(c)


def consumable_tome(px, py):
    w, h = FACE_W, FACE_H
    d = _edge_dist(px, py, w, h, 7.0)
    if d < 0:
        return CLEAR
    if d < 2.0:
        return _rgb((40, 20, 16))
    leather_n = _vnoise(px, py, 3, 14) * 0.6 + _vnoise(px, py, 11, 15) * 0.4
    c = _mix((82, 38, 34), (118, 60, 48), leather_n)
    # page block down the right edge
    if px > w - 11.0 and d > 2.0:
        stripe = 0.85 + 0.15 * math.sin(py * 1.4)
        return _rgb(_shade((236, 224, 188), stripe))
    # spine on the left with gold bands
    if px < 16.0:
        c = _shade(c, 0.75 + 0.25 * math.sin(px / 16.0 * math.pi))
        for by in (30.0, 89.0, 150.0):
            if abs(py - by) < 3.0:
                return _rgb(_mix(GOLD_DARK, (250, 226, 130), 1 - abs(py - by) / 3.0))
    # gold border and corner brackets
    if 4.0 <= d < 5.5:
        return _rgb(GOLD)
    for cx, cy, sx, sy in ((7.0, 7.0, 1, 1), (w - 7.0, 7.0, -1, 1), (7.0, h - 7.0, 1, -1), (w - 7.0, h - 7.0, -1, -1)):
        u, v = (px - cx) * sx, (py - cy) * sy
        if (0 <= u <= 18 and 0 <= v < 3.4) or (0 <= u < 3.4 and 0 <= v <= 18):
            return _rgb(GOLD)
    # central recessed panel for the icon, with a gold keyline
    if 28.0 <= px <= w - 18.0 and 40.0 <= py <= h - 40.0:
        pd = min(px - 28.0, w - 18.0 - px, py - 40.0, h - 40.0 - py)
        if pd < 1.6:
            return _rgb(GOLD)
        if pd < 3.0:
            return _rgb(_shade(c, 0.55))
        return _rgb(_mix(c, (150, 84, 62), 0.55))
    # clasp strap near the foot
    if abs(px - 72.0) < 5.0 and py > h - 40.0:
        return _rgb(_shade((140, 80, 56), 0.9 + 0.2 * math.sin(px)))
    if math.hypot(px - 72.0, py - (h - 28.0)) < 6.0:
        return _rgb(_mix(GOLD_DARK, (250, 226, 130), 0.5))
    return _rgb(c)


def consumable_relic(px, py):
    w, h = FACE_W, FACE_H
    cut = 18.0
    # chamfered octagon silhouette
    dx, dy = min(px, w - px), min(py, h - py)
    if dx + dy < cut:
        return CLEAR
    d = min(dx, dy, (dx + dy - cut) / math.sqrt(2.0))
    if d < 0:
        return CLEAR
    base = _mix((20, 32, 42), (34, 56, 66), _vnoise(px, py, 10, 16) * 0.7 + (py / h) * 0.3)
    glow = (96, 240, 206)
    if d < 2.5:
        return _rgb(_mix(glow, (220, 255, 245), 0.4))
    if d < 4.0:
        return _rgb(_shade(base, 0.5))
    c = base
    if d < 14.0:
        c = _mix(c, (30, 120, 112), 0.55 * (1 - (d - 4.0) / 10.0))  # inner glow
    if 8.0 <= d < 9.0:
        c = _mix(c, glow, 0.8)
    # rune ring around the centre
    cx, cy = w / 2.0, h / 2.0
    r = math.hypot(px - cx, py - cy)
    if 56.0 <= r < 57.2:
        c = _mix(c, glow, 0.7)
    elif 50.0 <= r < 50.8:
        c = _mix(c, glow, 0.4)
    elif 50.8 <= r < 56.0:
        c = _mix(c, (28, 90, 88), 0.35)
        ang = math.atan2(py - cy, px - cx)
        for i in range(12):
            a = i * math.pi / 6.0
            if _rune(px, py, cx + math.cos(a) * 53.2, cy + math.sin(a) * 53.2, 6.5, i, 0.7):
                c = _mix(c, glow, 0.9)
    # jewel at the top and bottom
    for jy in (22.0, h - 22.0):
        if _diamond_at(px, py, cx, jy, 9.0):
            return _rgb(_mix((220, 255, 245), (40, 170, 160), (abs(px - cx) + abs(py - jy)) / 9.0))
    return _rgb(c)


# ------------------------------------------------------------------ pack
def pack_wrapper(px, py):
    w, h = FACE_W, FACE_H
    # crimped, zig-zag cut top and bottom
    zig = abs(((px / 8.0) % 1.0) - 0.5) * 2.0
    top_edge = 2.0 + 5.0 * zig
    bot_edge = h - 2.0 - 5.0 * zig
    if py < top_edge or py > bot_edge or px < 1.5 or px > w - 1.5:
        return CLEAR
    base = _mix((58, 24, 100), (96, 44, 150), py / float(h))
    c = base
    # crimp ribbing
    if py < 24.0 or py > h - 24.0:
        rib = 0.5 + 0.5 * math.sin(px * 1.9)
        c = _mix(_shade(base, 0.7), (190, 150, 230), rib * 0.35)
        if abs(py - 24.0) < 1.2 or abs(py - (h - 24.0)) < 1.2:
            c = GOLD
        return _rgb(c)
    # foil stripes and a bright sweep
    s = (px + py) % 24.0
    if s < 2.0:
        c = _mix(c, (170, 120, 220), 0.35)
    s2 = (px * 0.7 - py * 0.3) % 120.0
    c = _mix(c, (230, 200, 255), max(0.0, 0.5 - abs(s2 - 60.0) / 40.0) * 0.3)
    side = min(px, w - px)
    if side < 4.0:
        return _rgb(GOLD)
    if side < 5.0:
        return _rgb(GOLD_DARK)
    # central emblem: gold ring, eight-point star, runes
    cx, cy = w / 2.0, 72.0
    dx, dy = px - cx, py - cy
    r = math.hypot(dx, dy)
    if 36.0 <= r < 38.0:
        return _rgb(GOLD)
    if 31.0 <= r < 32.0:
        return _rgb(GOLD_DARK)
    if r < 31.0:
        ang = math.atan2(dy, dx)
        star = 14.0 + 15.0 * max(0.0, math.cos(4 * ang)) ** 3
        inner = _mix((40, 14, 74), (70, 30, 110), r / 31.0)
        if r <= star:
            return _rgb(_mix((250, 226, 130), (200, 150, 50), r / star))
        return _rgb(inner)
    # banner with runes below the emblem
    if 126.0 <= py < 150.0:
        by = abs(py - 138.0)
        c = _mix((214, 175, 62), (150, 118, 38), by / 12.0)
        if by > 10.5:
            c = GOLD_DARK
        elif _rune_row(px, py, 138.0, 28.0, 6, 14.4, 9.0, 1, 1.0):
            c = (60, 24, 90)
        return _rgb(c)
    return _rgb(c)


NEW_JOBS = dict(FACES)
NEW_JOBS.update({
    "Ed_Sheen": ed_sheen,
    "Ed_Holo": ed_holo,
    "Consumable_Scroll": consumable_scroll,
    "Consumable_Tome": consumable_tome,
    "Consumable_Relic": consumable_relic,
    "Pack": pack_wrapper,
})


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


def top_only(fn, height):
    """Cards occupy the top 128x179 of the 128x256 canvas; the rest is transparent."""
    def sample(px, py):
        return CLEAR if py >= height else fn(px, py)
    return sample


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
    jobs.append(("CardBack", BACK_W, CANVAS_H, render(BACK_W, CANVAS_H, top_only(card_back, BACK_H))))
    for name, fn in NEW_JOBS.items():
        jobs.append((name, FACE_W, CANVAS_H, render(FACE_W, CANVAS_H, top_only(fn, FACE_H))))
    for kind in SEALS:
        jobs.append(("Seal_" + kind, SEAL_SIZE, SEAL_SIZE, render(SEAL_SIZE, SEAL_SIZE, seal_fn(kind))))
    for name, w, h, rgba in jobs:
        write_tga(os.path.join(MEDIA, name + ".tga"), w, h, rgba)
        print("wrote %s.tga (%dx%d)" % (name, w, h))
        if png_dir:
            write_png(os.path.join(png_dir, name + ".png"), w, h, rgba, bg=(70, 70, 80) if name.startswith(("Suit", "Seal", "Ed_", "Face_GLASS")) else None)


if __name__ == "__main__":
    main(sys.argv[1:])
