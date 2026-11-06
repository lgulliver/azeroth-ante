"""Checks the generated TGA textures in AzerothAnte/Media."""
import math
import os
import struct
import sys

MEDIA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "AzerothAnte", "Media")
EXPECTED = {
    "Suit_S.tga": (64, 64),
    "Suit_H.tga": (64, 64),
    "Suit_C.tga": (64, 64),
    "Suit_D.tga": (64, 64),
    "CardBack.tga": (128, 256),
    "Lock.tga": (64, 64),
    "Face_Plain.tga": (128, 256),
    "Ed_Sheen.tga": (128, 256),
    "Ed_Holo.tga": (128, 256),
    "Consumable_Scroll.tga": (128, 256),
    "Consumable_Tome.tga": (128, 256),
    "Consumable_Relic.tga": (128, 256),
    "Pack.tga": (128, 256),
}
BACKS = ("ROGUE", "WARRIOR", "GOBLIN", "MONK", "WARLOCK")
for _deck in BACKS:
    EXPECTED["Back_%s.tga" % _deck] = (128, 256)
    EXPECTED["BackSq_%s.tga" % _deck] = (256, 256)
for _enh in ("BONUS", "MULT", "WILD", "GLASS", "STEEL", "STONE", "GOLD", "LUCKY"):
    EXPECTED["Face_%s.tga" % _enh] = (128, 256)
for _seal in ("GOLD", "RED", "BLUE", "PURPLE"):
    EXPECTED["Seal_%s.tga" % _seal] = (32, 32)
CHIPS = ("SMALL", "BIG", "BOSS")
for _chip in CHIPS:
    EXPECTED["Chip_%s.tga" % _chip] = (64, 64)

EXPECTED["UI_Gradient.tga"] = (16, 64)
EXPECTED["UI_Shadow.tga"] = (64, 64)

# Overlays are mostly see-through; faces/seals/frames must be mostly opaque.
# name -> (min, max) fraction of pixels with alpha > 0
CARD_H = 179  # the card occupies the top 128x179 of the 128x256 canvas
CARD_PREFIXES = ("Face_", "Consumable_", "Pack")
# Fractions are of the card region.
COVERAGE = {"Ed_Sheen.tga": (0.1, 0.9), "Ed_Holo.tga": (0.1, 0.9), "Face_GLASS.tga": (0.5, 1.0)}


def _plain_alpha():
    with open(os.path.join(MEDIA, "Face_Plain.tga"), "rb") as f:
        data = f.read()
    return data[18 + data[0]:][3::4]


PLAIN_ALPHA = _plain_alpha()


def _pixels(name):
    with open(os.path.join(MEDIA, name), "rb") as f:
        data = f.read()
    return data[18 + data[0]:]


def check_backs():
    """Deck backs share CardBack's silhouette and gold border, and each looks different."""
    base = _pixels("CardBack.tga")
    means = {}
    if any(not os.path.exists(os.path.join(MEDIA, "Back_%s.tga" % d)) for d in BACKS):
        return "missing Back_* files"
    for deck in BACKS:
        px = _pixels("Back_%s.tga" % deck)
        if px[3::4] != base[3::4]:
            return "Back_%s: silhouette differs from CardBack" % deck
        # outer border: same gold as CardBack along the top edge, mid-card
        for x, y in ((64, 1), (64, 2), (1, 90), (126, 90)):
            i = (y * 128 + x) * 4
            if px[i:i + 4] != base[i:i + 4]:
                return "Back_%s: border pixel (%d,%d) differs from CardBack" % (deck, x, y)
        n = 128 * 179
        means[deck] = tuple(sum(px[i::4][:n]) / float(n) for i in range(3))
    decks = list(BACKS)
    for i, a in enumerate(decks):
        for b in decks[i + 1:]:
            if sum(abs(means[a][k] - means[b][k]) for k in range(3)) < 25:
                return "Back_%s and Back_%s are too alike" % (a, b)
    return None


def check_chips():
    """Blind chips: round, opaque in the middle, notched rim, distinct hues, BOSS light enough to tint,
    and the generator reproduces the shipped file byte for byte."""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
    import gen_media
    means = {}
    for chip in CHIPS:
        name = "Chip_%s.tga" % chip
        if not os.path.exists(os.path.join(MEDIA, name)):
            return "missing " + name
        px = _pixels(name)
        a = px[3::4]
        if a[32 * 64 + 32] != 255 or a[0] != 0 or a[63] != 0 or a[63 * 64] != 0 or a[63 * 64 + 63] != 0:
            return "%s: not a disc (centre opaque, corners clear)" % name
        frac = sum(1 for v in a if v > 0) / 4096.0
        if not 0.7 <= frac <= 0.82:
            return "%s: disc coverage %.2f outside 0.70..0.82" % (name, frac)
        # rotational symmetry of the silhouette: left/right and top/bottom mirror
        for y in range(64):
            for x in range(32):
                if abs(a[y * 64 + x] - a[y * 64 + 63 - x]) > 8 or abs(a[x * 64 + y] - a[(63 - x) * 64 + y]) > 8:
                    return "%s: silhouette not symmetric" % name
        # the rim ring is notched: colour varies around a circle of radius ~28
        ring = set()
        for i in range(96):
            t = i * 2 * 3.14159265 / 96
            x, y = int(round(31.5 + 28 * math.cos(t))), int(round(31.5 + 28 * math.sin(t)))
            j = (y * 64 + x) * 4
            ring.add(tuple(px[j:j + 3]))
        if len(ring) < 3:
            return "%s: rim has no notches" % name
        n = sum(1 for v in a if v > 0)
        # TGA pixels are BGRA: read channels as R, G, B
        means[chip] = tuple(sum(px[k::4][i] * (a[i] / 255.0) for i in range(4096)) / n for k in (2, 1, 0))
    sm, big, boss = means["SMALL"], means["BIG"], means["BOSS"]
    if not (sm[2] > sm[0] + 20 and sm[2] > sm[1]):
        return "Chip_SMALL is not blue"
    if not (big[0] > big[2] + 40 and big[1] > big[2] + 20):
        return "Chip_BIG is not gold/amber"
    if max(boss) - min(boss) > 20:
        return "Chip_BOSS is not a neutral base (%s)" % (tuple(round(v) for v in boss),)
    if min(boss) < 170:
        return "Chip_BOSS is too dark to tint cleanly (%s)" % (tuple(round(v) for v in boss),)
    for chip in CHIPS:
        with open(os.path.join(MEDIA, "Chip_%s.tga" % chip), "rb") as f:
            if f.read() != gen_media.chip_tga(chip):
                return "Chip_%s.tga differs from the generator output" % chip
    return None


def check_ui_chrome():
    """UI_Gradient is a white vertical ramp (opaque top, clear bottom, uniform across);
    UI_Shadow is a white blob, solid in the middle and clear at the edge. Both are reproducible."""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
    import gen_media
    px = _pixels("UI_Gradient.tga")
    a = px[3::4]
    if any(px[i] != 255 for i in range(len(px)) if i % 4 != 3):
        return "UI_Gradient is not pure white"
    if a[0] != 255 or a[16 * 63] > 8:
        return "UI_Gradient does not run opaque to clear"
    col = [a[y * 16] for y in range(64)]
    if any(col[y] < col[y + 1] for y in range(63)):
        return "UI_Gradient is not monotonic"
    if any(a[y * 16 + x] != a[y * 16] for y in range(64) for x in range(16)):
        return "UI_Gradient varies horizontally"
    px = _pixels("UI_Shadow.tga")
    a = px[3::4]
    if a[32 * 64 + 32] < 240:
        return "UI_Shadow centre is not solid"
    edge = [a[x] for x in range(64)] + [a[63 * 64 + x] for x in range(64)] + [a[y * 64] for y in range(64)] + [a[y * 64 + 63] for y in range(64)]
    if max(edge) != 0:
        return "UI_Shadow edge ring is not clear"
    if a[8 * 64 + 32] >= a[32 * 64 + 32] or a[2 * 64 + 32] >= a[8 * 64 + 32]:
        return "UI_Shadow does not fall off outwards"
    for name, (w, h, fn) in gen_media.UI_JOBS.items():
        with open(os.path.join(MEDIA, name + ".tga"), "rb") as f:
            if f.read() != gen_media.tga_bytes(w, h, gen_media.render(w, h, fn)):
                return "%s.tga differs from the generator output" % name
    return None


def is_pow2(n):
    return n > 0 and (n & (n - 1)) == 0


def check(name, size):
    path = os.path.join(MEDIA, name)
    if not os.path.exists(path):
        return "missing file"
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 18:
        return "too short"
    id_len, cmap, itype = data[0], data[1], data[2]
    w, h = struct.unpack("<HH", data[12:16])
    bpp, desc = data[16], data[17]
    if itype != 2:
        return "image type %d, want 2" % itype
    if cmap != 0:
        return "unexpected colour map"
    if bpp != 32:
        return "bpp %d, want 32" % bpp
    if desc != 0x28:
        return "descriptor 0x%02x, want 0x28" % desc
    if (w, h) != size:
        return "size %dx%d, want %dx%d" % (w, h, size[0], size[1])
    if not (is_pow2(w) and is_pow2(h)):
        return "dimensions not powers of two"
    pixels = data[18 + id_len:]
    if len(pixels) != w * h * 4:
        return "pixel data length %d, want %d" % (len(pixels), w * h * 4)
    alpha = pixels[3::4]
    if name.startswith("BackSq_"):
        return check_square(w, h, alpha)
    if name.startswith(CARD_PREFIXES) or name in ("CardBack.tga", "Ed_Sheen.tga", "Ed_Holo.tga") or name.startswith("Back_"):
        return check_card(name, w, h, alpha)
    if 0 not in alpha or 255 not in alpha:
        return "alpha lacks both 0 and 255"
    return None


def check_square(w, h, alpha):
    """The carousel's square variant: the 5:7 card (160x224) centred with a clear margin,
    so a 6 degree SetRotation never samples past the card."""
    for y in range(h):
        for x in range(w):
            inside = 48 <= x < 208 and 16 <= y < 240
            if not inside and alpha[y * w + x] != 0:
                return "pixel outside the 160x224 card box at (%d,%d)" % (x, y)
    if alpha[(128) * w + 128] != 255 or alpha[128 * w + 49] != 255:
        return "card is not opaque across its middle"
    if alpha[16 * w + 48] != 0:
        return "card corner is not rounded"
    return None


def check_card(name, w, h, alpha):
    """Cards are authored in the top 128x179 (5:7) of the 128x256 canvas."""
    top, rest = alpha[:w * CARD_H], alpha[w * CARD_H:]
    if any(a != 0 for a in rest):
        return "pixels below the top %dx%d card region" % (w, CARD_H)
    if 0 not in top:
        return "card region has no transparent corners"
    if max(top) != 255:
        return "card region has no opaque pixel"
    frac = sum(1 for a in top if a > 0) / float(len(top))
    if name in COVERAGE:
        lo, hi = COVERAGE[name]
        if not (lo <= frac <= hi):
            return "alpha coverage %.2f outside %.2f..%.2f" % (frac, lo, hi)
    if name.startswith(("Face_", "CardBack", "Back_")) and name != "Face_GLASS.tga":
        # opaque everywhere inside the rounded edge (an 8px inset clears the corners)
        for y in range(8, CARD_H - 8):
            row = alpha[y * w + 8:y * w + w - 8]
            if min(row) != 255:
                return "face not opaque inside the card region (row %d)" % y
    elif name.startswith("Consumable_"):
        # Scrolls, Tomes and Relics are cards: opaque inside the same rounded 5:7
        # silhouette as the playing cards, so the alpha must match Face_Plain exactly.
        for y in range(8, CARD_H - 8):
            if min(alpha[y * w + 8:y * w + w - 8]) != 255:
                return "card not opaque inside the card region (row %d)" % y
        if alpha != PLAIN_ALPHA:
            return "silhouette differs from Face_Plain (not the playing-card shape)"
    elif name.startswith("Pack"):
        if sum(1 for a in top if a == 255) < len(top) * 0.5:
            return "expected a mostly opaque texture"
    return None
    return None


def main():
    failed = 0
    for name, size in sorted(EXPECTED.items()):
        err = check(name, size)
        if err:
            failed += 1
            print("FAIL %s: %s" % (name, err))
        else:
            print("ok   %s" % name)
    err = check_backs()
    if err:
        failed += 1
        print("FAIL backs: " + err)
    err = check_chips()
    if err:
        failed += 1
        print("FAIL chips: " + err)
    err = check_ui_chrome()
    if err:
        failed += 1
        print("FAIL ui chrome: " + err)
    if failed:
        sys.exit(1)
    print("all media ok")


if __name__ == "__main__":
    main()
