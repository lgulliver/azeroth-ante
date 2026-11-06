"""Checks the generated TGA textures in AzerothAnte/Media."""
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
    if failed:
        sys.exit(1)
    print("all media ok")


if __name__ == "__main__":
    main()
