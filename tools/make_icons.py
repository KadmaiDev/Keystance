"""Makes the game's icon files from the logo (media/logo-source.png, 1024x1024):

    python tools/make_icons.py

  media/icon.tga     64x64, the badge without its gold ring: the addon list (## IconTexture)
                     shows it at about 16 pixels, where the ring took room from the keys
                     and they lost their detail (as Alts Forever's icon does)
  media/minimap.tga  64x64, the same: the minimap button's own border (or EllesmereUI's
                     tray) draws the ring, and two rings never line up
  media/logo.png     400x400, the whole badge with its ring, for the README

The game wants uncompressed 32-bit TGA files with power-of-two sizes.
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "media")
SIZE = 64
SUPER = 4  # the mask is drawn this much larger, then shrunk, for a smooth edge


def badge_box(im):
    """The badge's bounding square, from the logo's opaque pixels."""
    left, top, right, bottom = im.split()[3].getbbox()
    cx, cy = (left + right) / 2, (top + bottom) / 2
    # The drawn badge is slightly oval: the long side fits it all in, the short side is
    # the radius that stays inside the ring all the way round.
    return cx, cy, max(right - left, bottom - top) / 2, min(right - left, bottom - top) / 2


def circle_mask(size, radius_fraction):
    big = size * SUPER
    mask = Image.new("L", (big, big), 0)
    r = big / 2 * radius_fraction
    ImageDraw.Draw(mask).ellipse((big / 2 - r, big / 2 - r, big / 2 + r, big / 2 + r), fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def save_tga(im, name):
    im.save(os.path.join(MEDIA, name), compression=None)


def main():
    src = Image.open(os.path.join(MEDIA, "logo-source.png")).convert("RGBA")
    cx, cy, half, short = badge_box(src)

    full = src.crop((round(cx - half), round(cy - half), round(cx + half), round(cy + half)))
    full.resize((400, 400), Image.LANCZOS).save(os.path.join(MEDIA, "logo.png"))

    # Inside the gold ring: measured on the logo, the ring's inner edge is at 92.4% of the
    # badge's radius; cut inside it (0.9) so no gold shows at the edge.
    inner = short * 0.9
    disc = src.crop((round(cx - inner), round(cy - inner), round(cx + inner), round(cy + inner)))
    disc = disc.resize((SIZE, SIZE), Image.LANCZOS)
    alpha = Image.new("L", (SIZE, SIZE), 0)
    alpha.paste(disc.split()[3], mask=circle_mask(SIZE, 1.0))
    disc.putalpha(alpha)
    save_tga(disc, "icon.tga")
    save_tga(disc, "minimap.tga")
    print("made media/icon.tga, media/minimap.tga, media/logo.png")


if __name__ == "__main__":
    main()
