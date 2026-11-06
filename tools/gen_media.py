#!/usr/bin/env python3
"""Generates the Azeroth Ante textures in AzerothAnte/Media (stdlib only).

Output is uncompressed 32-bit BGRA TGA (type 2, descriptor 0x28: 8 alpha bits,
top-left origin). Shapes are point tests sampled on a 4x supersampled grid and
averaged down for anti-aliasing. Suits are pure white with the shape in alpha so
the UI can tint them with SetVertexColor.

Usage: python3 tools/gen_media.py [--png-dir DIR] [--only NAME_PREFIX]   (PNG previews are optional)
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


def _corner_ornament(px, py, inset, col, dark, skip_bl=False):
    """Gold diamonds in the free corners. Top-left and bottom-right stay clear:
    the rank is printed straight onto the face there."""
    corners = [(FACE_W - inset, inset)]
    if not skip_bl:
        corners.append((inset, FACE_H - inset))
    for cx, cy in corners:
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
    orn = _corner_ornament(px, py, 20.0, GOLD, GOLD_DARK, skip_bl=clover)
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
        cl = _clover(px, py, 27.0, 150.0)
        if cl:
            return _rgb(cl)
    return _rgb(c)


def _clover(px, py, cx, cy):
    # stem runs down-left so the clover stays clear of the bottom-right rank
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
    for cx, cy in ((w - 16.0, 16.0), (16.0, h - 16.0)):  # bottom-right is left bare for the rank
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
# Scrolls, Tomes and Relics are cards: the same rounded 5:7 silhouette and border
# thickness as the playing cards, with a clear centre window for the item icon.
WIN_X0, WIN_Y0, WIN_X1, WIN_Y1 = 18.0, 24.0, 110.0, 132.0  # icon window (card px)


def _win_d(px, py):
    """Distance inside the icon window edge (negative outside)."""
    return min(px - WIN_X0, WIN_X1 - px, py - WIN_Y0, WIN_Y1 - py)


def _card_edge(px, py, col, dark):
    """Shared outline: (d, colour-or-None). d < 0 means outside the card."""
    d = _edge_dist(px, py, FACE_W, FACE_H, CORNER)
    if d < 0:
        return d, CLEAR
    if d < 3.0:
        return d, _rgb(col)
    if d < 4.0:
        return d, _rgb(dark)
    return d, None


def consumable_scroll(px, py):
    """Tarot: warm parchment, gold arcane border, rune banner at the foot."""
    w, h = FACE_W, FACE_H
    d, edge = _card_edge(px, py, GOLD, GOLD_DARK)
    if edge:
        return edge
    if 7.0 <= d < 8.0:
        return _rgb(GOLD_DARK)
    c = parchment(px, py, d)
    # arcane ring around the window and a gold diamond at each upper corner
    for cx in (20.0, w - 20.0):
        if _diamond_at(px, py, cx, 14.0, 4.0):
            return _rgb(GOLD_DARK if _diamond_at(px, py, cx, 14.0, 1.6) else GOLD)
    # rune banner
    if 140.0 <= py < 166.0 and 12.0 <= px <= w - 12.0:
        edge_d = min(py - 140.0, 166.0 - py)
        if edge_d < 1.2:
            return _rgb(GOLD)
        band = _mix((132, 52, 40), (96, 36, 30), (py - 140.0) / 26.0)
        if _rune_row(px, py, 153.0, 32.0, 6, 13.0, 10.0, 0, 1.0):
            band = (240, 208, 120)
        return _rgb(band)
    # icon window: slightly recessed, gold keyline
    wd = _win_d(px, py)
    if wd >= 0:
        if wd < 1.4:
            return _rgb(GOLD)
        if wd < 2.6:
            return _rgb(_shade(c, 0.78))
        return _rgb(_shade(_mix(c, (250, 238, 205), 0.4), 0.97))
    return _rgb(c)


def consumable_tome(px, py):
    """Planet: deep-blue starfield, silver border."""
    w, h = FACE_W, FACE_H
    silver, silver_dark = (214, 220, 232), (104, 112, 134)
    d, edge = _card_edge(px, py, silver, silver_dark)
    if edge:
        return edge
    if 7.0 <= d < 8.0:
        return _rgb(silver_dark)
    n = _vnoise(px, py, 22, 21) * 0.6 + _vnoise(px, py, 8, 22) * 0.4
    c = _mix((12, 18, 52), (34, 56, 116), n * 0.8 + (py / h) * 0.2)
    wd = _win_d(px, py)
    if wd >= 0:
        c = _mix(c, (6, 9, 30), 0.65)
    gx, gy = int(px / 2.0), int(py / 2.0)
    r = _hash(gx, gy, 23)
    if r < 0.03:
        k = 0.45 + 0.55 * _hash(gx, gy, 24)
        c = _mix(c, (240, 246, 255), k)
    if wd >= 0:
        if wd < 1.4:
            return _rgb(silver)
        if wd < 2.6:
            return _rgb(_shade(c, 0.6))
    return _rgb(c)


def consumable_relic(px, py):
    """Spectral: dark violet, pale spectral border, rising wisps."""
    w, h = FACE_W, FACE_H
    pale, pale_dark = (222, 208, 246), (118, 96, 160)
    d, edge = _card_edge(px, py, pale, pale_dark)
    if edge:
        return edge
    if 7.0 <= d < 8.0:
        return _rgb(pale_dark)
    n = _vnoise(px, py, 16, 31) * 0.7 + (py / h) * 0.3
    c = _mix((26, 12, 44), (58, 30, 88), n)
    if d < 14.0:
        c = _mix(c, (92, 60, 140), 0.45 * (1 - (d - 4.0) / 10.0))  # inner glow
    # wisps drifting up the card
    for k in range(4):
        cx = 18.0 + k * 30.0 + 7.0 * math.sin(py * 0.06 + k * 1.7)
        dist = abs(px - cx)
        rise = max(0.0, (py - 20.0) / (h - 20.0))
        if dist < 2.2:
            c = _mix(c, (190, 170, 236), (1 - dist / 2.2) * 0.30 * rise)
    wd = _win_d(px, py)
    if wd >= 0:
        c = _mix(c, (12, 6, 24), 0.7)
        if wd < 1.4:
            return _rgb(pale)
        if wd < 2.6:
            return _rgb(_shade(c, 0.6))
    # pale jewels, top and bottom
    for jy in (12.0, h - 12.0):
        if _diamond_at(px, py, w / 2.0, jy, 4.0):
            return _rgb(pale)
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


# ------------------------------------------------------------ deck backs
# Back_<DECK>: the CardBack silhouette and gold border, with a per-deck field,
# a gold-ringed medallion and an emblem built from simple vector shapes.
BCX, BCY = BACK_W / 2.0, BACK_H / 2.0
INK = (12, 8, 8)


def _frame(px, py):
    """The shared silhouette and borders; None inside the border."""
    w, h = BACK_W, BACK_H
    if not _in_round_rect(px, py, w, h, CORNER):
        return CLEAR
    if not _in_round_rect(px, py, w, h, CORNER, 4.0):
        return GOLD + (255,)
    if _in_round_rect(px, py, w, h, CORNER, 7.0) and not _in_round_rect(px, py, w, h, CORNER, 8.0):
        return GOLD_DARK + (255,)
    return None


def _rot(dx, dy, deg):
    """Axis coordinates for a shape whose tip points `deg` clockwise from up."""
    a = math.radians(deg)
    return dx * math.sin(a) - dy * math.cos(a), dx * math.cos(a) + dy * math.sin(a)


def _dagger(dx, dy, deg, g):
    u, v = _rot(dx, dy, deg)
    u += 8  # the daggers cross a little way up their blades
    if -4 - g <= u <= 38 + g:  # blade, pointed
        t = max(0.0, min(1.0, u / 38.0))
        half = 5.5 * (1 - t ** 1.7) + g
        if abs(v) <= half and (u <= 38 + g * 0.2 or g):
            if g:
                return INK
            if abs(v) < 0.9 and 3 < u < 28:
                return (120, 130, 150)
            return (222, 228, 238) if v < 0 else (160, 170, 188)
    if -8 - g <= u <= -3 + g and abs(v) <= 11 + g:  # crossguard
        return _mix(GOLD, GOLD_DARK, abs(v) / 11.0) if not g else INK
    if -26 - g <= u <= -7 and abs(v) <= 2.8 + g:  # handle
        if g:
            return INK
        return (96, 40, 30) if int(u + 40) % 5 else (60, 22, 18)
    if (u + 30) ** 2 + v ** 2 <= (4.2 + g) ** 2:  # pommel
        return INK if g else GOLD
    return None


def rogue_emblem(dx, dy, g):
    return _dagger(dx, dy, -42, g) or _dagger(dx, dy, 42, g)


def _shield_hw(y, g):
    if y < -24 - g:
        return -1
    if y <= 4:
        return 30 + g
    t = (y - 4) / (38.0 + g)
    return (30 + g) * math.sqrt(max(0.0, 1 - t * t)) if t <= 1 else -1


def warrior_emblem(dx, dy, g):
    # sword in front of the shield
    if -41 - g <= dy <= -3 + g:
        t = max(0.0, min(1.0, (dy + 41) / 12.0))
        half = (4.8 * t ** 0.7 if g == 0 else 4.8 * t ** 0.7 + g)
        if abs(dx) <= half:
            if g:
                return INK
            if abs(dx) < 0.8 and dy > -30:
                return (110, 124, 150)
            return (230, 236, 246) if dx < 0 else (165, 176, 196)
    if -3 - g <= dy <= 1 + g and abs(dx) <= 15 + g:
        return INK if g else _mix(GOLD, GOLD_DARK, abs(dx) / 15.0)
    if 1 <= dy <= 20 + g and abs(dx) <= 2.8 + g:
        return INK if g else ((96, 40, 30) if int(dy) % 5 else (60, 22, 18))
    if dx ** 2 + (dy - 24) ** 2 <= (4.4 + g) ** 2:
        return INK if g else GOLD
    hw = _shield_hw(dy, g)
    if abs(dx) <= hw:
        if g:
            return INK
        if abs(dx) > _shield_hw(dy, -3.5) - 0.0 and _shield_hw(dy, -3.5) > 0 or _shield_hw(dy, -3.5) < 0:
            return _mix(GOLD, GOLD_DARK, (dy + 24) / 70.0)
        if dy < -14 and abs(dx) < 26 and dy > -20:  # chief bar
            return (205, 214, 232)
        return (34, 70, 142) if dx < 0 else (70, 112, 190)
    return None


def _coin_stack(dx, dy, cx, base, n, rx, ry, thick, g):
    top = base - n * thick
    x = dx - cx
    if g:
        rx, ry = rx + g, ry + g
        top -= g
        base += g
    # top face
    if (x / rx) ** 2 + ((dy - top) / ry) ** 2 <= 1:
        if g:
            return INK
        d = (x / rx) ** 2 + ((dy - top) / ry) ** 2
        if 0.55 <= d <= 0.72:
            return GOLD_DARK
        return _mix((255, 232, 130), (226, 176, 52), d)
    if abs(x) <= rx and top <= dy <= base or (x / rx) ** 2 + ((dy - base) / ry) ** 2 <= 1:
        if g:
            return INK
        k = (base - dy) / float(thick)
        edge = abs(k - round(k)) < 0.12
        shade = 0.72 + 0.28 * (1 - abs(x) / rx)
        c = (150, 112, 30) if edge else (214, 168, 46)
        return tuple(_clamp(v * shade) for v in c)
    return None


def goblin_emblem(dx, dy, g):
    for cx, base, n in ((0, 32, 6), (-22, 28, 3), (21, 29, 4)):
        c = _coin_stack(dx, dy, cx, base, n, 11.5 if cx == 0 else 10.0, 4.2, 4.6, g)
        if c:
            return c
    if not g:  # a sparkle above the stacks
        for sx, sy, size in ((14, -26, 7.0), (-18, -14, 5.0)):
            if abs(dx - sx) ** 0.6 + abs(dy - sy) ** 0.6 <= size ** 0.6:
                return (255, 246, 190)
    return None


def monk_emblem(dx, dy, g):
    r = math.hypot(dx, dy)
    if r > 31 + g:
        return None
    if g:
        return INK
    if r >= 28.5:
        return GOLD
    if r <= 4.5:
        return GOLD
    ang = math.atan2(dy, dx) / (2 * math.pi)
    k = (ang * 3 + r / 28.0 * 0.85) % 1.0
    if k < 0.5:
        return _mix((120, 226, 190), (200, 255, 230), r / 28.0)
    return _mix((16, 84, 74), (10, 52, 50), r / 28.0)


def _seg(dx, dy, x0, y0, x1, y1):
    return _seg_dist(dx, dy, x0, y0, x1, y1)


def _sigil_dist(dx, dy):
    r = math.hypot(dx, dy)
    d = abs(r - 38.5) - 0.9
    # A vertical slit eye: two arcs meeting at pointed tips.
    eye_h, eye_w = 21.0, 9.5
    big_r = (eye_w ** 2 + eye_h ** 2) / (2 * eye_w)
    off = big_r - eye_w
    if abs(dy) <= eye_h + 1.0:
        if dx <= 0:
            d = min(d, abs(math.hypot(dx - off, dy) - big_r) - 0.9)
        if dx >= 0:
            d = min(d, abs(math.hypot(dx + off, dy) - big_r) - 0.9)
    # Jagged fel-flame spikes licking out of the eye's corners.
    flame = ((9.0, 3.5), (17.0, 6.5), (14.5, 10.0), (24.0, 15.5))
    for sx in (-1, 1):
        for sy in (-1, 1):
            for i in range(len(flame) - 1):
                x0, y0 = flame[i]
                x1, y1 = flame[i + 1]
                d = min(d, _seg(dx, dy, sx * x0, sy * y0, sx * x1, sy * y1) - 0.8)
    if 28 <= r <= 37:  # rune ticks around the rim
        ang = math.atan2(dy, dx)
        k = int(round(ang / (math.pi / 6.0)))
        a = k * math.pi / 6.0
        ux, uy = math.cos(a), math.sin(a)
        d = min(d, _seg(dx, dy, ux * 31, uy * 31, ux * 36.5, uy * 36.5) - 0.7)
        px_, py_ = -uy, ux
        m = k % 3
        if m == 0:
            d = min(d, _seg(dx, dy, ux * 33.5 - px_ * 2.2, uy * 33.5 - py_ * 2.2, ux * 33.5 + px_ * 2.2, uy * 33.5 + py_ * 2.2) - 0.6)
        elif m == 1:
            d = min(d, _seg(dx, dy, ux * 31, uy * 31, ux * 34 + px_ * 2.6, uy * 34 + py_ * 2.6) - 0.6)
    return d


def warlock_emblem(dx, dy, g):
    if g:
        return None
    if abs(dx) / 4.5 + abs(dy) / 10.5 <= 1:  # the diamond pupil
        return _mix((255, 245, 160), (120, 255, 110), (abs(dx) / 4.5 + abs(dy) / 10.5))
    d = _sigil_dist(dx, dy)
    if d <= 0.0:
        return (150, 255, 120)
    return None


def _disc_radial(inner, outer, extra=None):
    def disc(dx, dy, r):
        c = _mix(inner, outer, r / 43.5)
        return extra(dx, dy, r, c) if extra else c
    return disc


def _warlock_disc(dx, dy, r):
    c = _mix((70, 26, 110), (26, 8, 48), r / 43.5)
    d = _sigil_dist(dx, dy)
    return _mix(c, (70, 230, 90), math.exp(-max(d, 0) / 4.5) * 0.55)


def _monk_disc(dx, dy, r, c):
    ang = math.atan2(dy, dx)
    if 35.0 <= r <= 42.0:  # ring of beads
        a = (ang / (2 * math.pi) * 12 + 0.5) % 1.0
        ba = (math.floor(ang / (2 * math.pi) * 12) + 0.5) * 2 * math.pi / 12
        if math.hypot(dx - 38.5 * math.cos(ba), dy - 38.5 * math.sin(ba)) <= 2.4:
            return _mix(c, (190, 250, 225), 0.8)
    return c


def _goblin_disc(dx, dy, r, c):
    if r > 38 and (int(math.floor(dx / 7.0)) + int(math.floor(dy / 7.0))) % 2 == 0:
        return _shade(c, 0.88)
    return c


def _field_rogue(px, py):
    c = _mix((150, 28, 40), (62, 8, 16), math.hypot(px - BCX, py - BCY) / 90.0)
    if ((px + py) % 15.0) < 1.3:
        c = _shade(c, 0.78)
    return c


def _field_warrior(px, py):
    c = _mix((54, 92, 150), (16, 30, 62), math.hypot(px - BCX, py - BCY) / 90.0)
    if ((abs(px - BCX) + py) % 14.0) < 1.4:
        c = _mix(c, (150, 176, 214), 0.28)
    return c


def _field_goblin(px, py):
    c = _mix((50, 112, 52), (14, 44, 22), math.hypot(px - BCX, py - BCY) / 90.0)
    gx, gy = px / 12.0, py / 12.0
    row = int(gy)
    fx = (gx + (0.5 if row % 2 else 0.0)) % 1.0
    if (fx - 0.5) ** 2 + ((gy % 1.0) - 0.5) ** 2 < 0.035:
        c = _mix(c, GOLD, 0.65)
    return c


def _field_monk(px, py):
    r = math.hypot(px - BCX, py - BCY)
    c = _mix((30, 130, 108), (8, 48, 46), r / 90.0)
    if (r % 9.0) < 1.1:
        c = _mix(c, (130, 220, 190), 0.22)
    return c


def _field_warlock(px, py):
    r = math.hypot(px - BCX, py - BCY)
    c = _mix((74, 26, 112), (22, 8, 40), r / 90.0)
    n = _vnoise(px, py, 14.0, 7)
    c = _mix(c, (40, 130, 70), max(0.0, n - 0.55) * 0.9)
    if _hash(int(px), int(py), 3) > 0.985:
        c = (130, 255, 130)
    return c


def _ornament(px, py):
    for cy in (23.0, BACK_H - 23.0):
        d = abs(px - BCX) / 7.0 + abs(py - cy) / 7.0
        if d <= 1.0:
            return INK if d < 0.35 else GOLD
        if abs(py - cy) <= 1.0 and 12 <= abs(px - BCX) <= 26:
            return GOLD_DARK
    return None


def make_back(field, disc, emblem):
    def fn(px, py):
        c = _frame(px, py)
        if c is not None:
            return c
        dx, dy = px - BCX, py - BCY
        r = math.hypot(dx, dy)
        if r < 43.5:
            e = emblem(dx, dy, 0)
            if e:
                return _rgb(e)
            if emblem(dx, dy, 1.5):
                return _rgb(INK)
            return _rgb(disc(dx, dy, r))
        if 46.0 <= r < 48.5:
            return _rgb(_mix(GOLD, GOLD_DARK, (r - 46.0) / 2.5 * 0.5))
        if 43.5 <= r < 44.5:
            return _rgb(GOLD_DARK)
        if r < 46.0:
            return _rgb(INK)
        o = _ornament(px, py)
        return _rgb(o if o else field(px, py))
    return fn


BACKS = {
    "Back_ROGUE": make_back(_field_rogue, _disc_radial((120, 22, 32), (48, 6, 12)), rogue_emblem),
    "Back_WARRIOR": make_back(_field_warrior, _disc_radial((70, 106, 168), (22, 40, 82)), warrior_emblem),
    "Back_GOBLIN": make_back(_field_goblin, _disc_radial((60, 128, 60), (20, 62, 30), _goblin_disc), goblin_emblem),
    "Back_MONK": make_back(_field_monk, _disc_radial((26, 118, 98), (10, 56, 52), _monk_disc), monk_emblem),
    "Back_WARLOCK": make_back(_field_warlock, _warlock_disc, warlock_emblem),
}


def square_back(fn):
    """The back centred (160x224, 5:7) in a 256x256 canvas with a clear margin. The carousel
    rotates it a few degrees, and SetRotation only turns a square texture rigidly."""
    k = 160.0 / BACK_W  # 224 / 179 is the same ratio

    def sample(px, py):
        x, y = (px - 48.0) / k, (py - 16.0) / k
        if x < 0 or y < 0 or x >= BACK_W or y >= BACK_H:
            return CLEAR
        return fn(x, y)
    return sample


# --------------------------------------------------------------- padlock
def _lock_body(px, py, g):
    return _in_round_rect(px - 12 + g, py - 28 + g, 40 + 2 * g, 30 + 2 * g, 5.0 + g)


def _lock_shackle(px, py, g):
    d = math.hypot(px - 32, py - 28)
    if py <= 28:
        return 9.5 - g <= d <= 15 + g
    return py <= 34 and (17 - g <= px <= 22.5 + g or 41.5 - g <= px <= 47 + g)


def padlock(px, py):
    """A gold padlock with a steel shackle and a dark keyhole, outlined for any backdrop."""
    if _lock_body(px, py, 0):
        if math.hypot(px - 32, py - 40) <= 4.2 or (30 <= px <= 34 and 41 <= py <= 51):
            return _rgb(INK)
        return _rgb(_mix((238, 198, 80), (160, 118, 36), (py - 28) / 30.0))
    if _lock_shackle(px, py, 0):
        return _rgb(_mix((226, 232, 242), (140, 150, 170), (px - 17) / 30.0))
    if _lock_body(px, py, 1.8) or _lock_shackle(px, py, 1.8):
        return _rgb(INK)
    return CLEAR


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
    only = argv[argv.index("--only") + 1] if "--only" in argv else ""
    os.makedirs(MEDIA, exist_ok=True)
    jobs = [(name, 64, 64, render_suit(fn)) for name, fn in SUITS.items()]
    jobs.append(("CardBack", BACK_W, CANVAS_H, render(BACK_W, CANVAS_H, top_only(card_back, BACK_H))))
    for name, fn in NEW_JOBS.items():
        jobs.append((name, FACE_W, CANVAS_H, render(FACE_W, CANVAS_H, top_only(fn, FACE_H))))
    for kind in SEALS:
        jobs.append(("Seal_" + kind, SEAL_SIZE, SEAL_SIZE, render(SEAL_SIZE, SEAL_SIZE, seal_fn(kind))))
    for name, fn in BACKS.items():
        jobs.append((name, BACK_W, CANVAS_H, render(BACK_W, CANVAS_H, top_only(fn, BACK_H))))
    for name, fn in BACKS.items():
        jobs.append((name.replace("Back_", "BackSq_"), 256, 256, render(256, 256, square_back(fn))))
    jobs.append(("Lock", 64, 64, render(64, 64, padlock)))
    jobs = [j for j in jobs if j[0].startswith(only)]
    for name, w, h, rgba in jobs:
        write_tga(os.path.join(MEDIA, name + ".tga"), w, h, rgba)
        print("wrote %s.tga (%dx%d)" % (name, w, h))
        if png_dir:
            write_png(os.path.join(png_dir, name + ".png"), w, h, rgba, bg=(70, 70, 80) if name.startswith(("Suit", "Seal", "Ed_", "Face_GLASS")) else None)


if __name__ == "__main__":
    main(sys.argv[1:])
