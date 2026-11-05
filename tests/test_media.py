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
    "Face_Plain.tga": (128, 256),
    "Ed_Sheen.tga": (128, 256),
    "Ed_Holo.tga": (128, 256),
    "Consumable_Scroll.tga": (128, 256),
    "Consumable_Tome.tga": (128, 256),
    "Consumable_Relic.tga": (128, 256),
    "Pack.tga": (128, 256),
}
for _enh in ("BONUS", "MULT", "WILD", "GLASS", "STEEL", "STONE", "GOLD", "LUCKY"):
    EXPECTED["Face_%s.tga" % _enh] = (128, 256)
for _seal in ("GOLD", "RED", "BLUE", "PURPLE"):
    EXPECTED["Seal_%s.tga" % _seal] = (32, 32)

# Overlays are mostly see-through; faces/seals/frames must be mostly opaque.
# name -> (min, max) fraction of pixels with alpha > 0
COVERAGE = {"Ed_Sheen.tga": (0.1, 0.9), "Ed_Holo.tga": (0.1, 0.9), "Face_GLASS.tga": (0.5, 1.0)}


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
    if 0 not in alpha or 255 not in alpha:
        return "alpha lacks both 0 and 255"
    if name in COVERAGE:
        lo, hi = COVERAGE[name]
        frac = sum(1 for a in alpha if a > 0) / float(len(alpha))
        if not (lo <= frac <= hi):
            return "alpha coverage %.2f outside %.2f..%.2f" % (frac, lo, hi)
    if name.startswith(("Face_", "Consumable_", "Pack")) and name != "Face_GLASS.tga":
        if sum(1 for a in alpha if a == 255) < len(alpha) * 0.5:
            return "expected a mostly opaque texture"
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
    if failed:
        sys.exit(1)
    print("all media ok")


if __name__ == "__main__":
    main()
