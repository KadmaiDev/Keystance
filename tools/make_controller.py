"""Makes the controller drawing for the Keyboard tab's Controller layout, and a disc:

    python tools/make_controller.py

  media/controller.tga  512x256, a controller: a smooth outline (shoulders, a gently curved
                        top, grips flaring down and out) with shallow wells under the sticks,
                        the d-pad and the face buttons, drawn in the layout's own key units
                        (15.5 x 8) so the buttons in Layouts.lua sit on it
  media/circle.tga      64x64, a white disc: the dark backing behind a controller button's badge

The game wants uncompressed 32-bit TGA files with power-of-two sizes.
"""
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "media")

UNITS_W, UNITS_H = 15.5, 8.0
W, H = 512, 256
SUPER = 4  # drawn larger, then shrunk, for smooth edges
BODY = (38, 40, 47, 240)
EDGE = (100, 104, 118, 255)
WELL = (27, 28, 34, 255)

# The outline, clockwise from the left shoulder, in key units (y down). A smooth closed
# curve is drawn through these points.
OUTLINE = [
    (1.4, 1.35), (4.2, 1.55), (7.75, 1.75), (11.3, 1.55), (14.1, 1.35),  # top
    (15.0, 2.2), (15.25, 3.9), (15.1, 5.7), (14.7, 7.1),                 # right side
    (13.7, 7.85), (12.5, 7.55), (11.3, 6.1),                             # right grip
    (9.6, 5.45), (7.75, 5.35), (5.9, 5.45),                              # underside
    (4.2, 6.1), (3.0, 7.55), (1.8, 7.85),                                # left grip
    (0.8, 7.1), (0.4, 5.7), (0.25, 3.9), (0.5, 2.2),                     # left side
]


def catmull_rom(points, steps=24):
    """A smooth closed curve through the points."""
    out = []
    n = len(points)
    for i in range(n):
        p0, p1, p2, p3 = points[i - 1], points[i], points[(i + 1) % n], points[(i + 2) % n]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                       + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                       + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    return out


def controller():
    s = SUPER
    ux, uy = W * s / UNITS_W, H * s / UNITS_H
    to_px = lambda pts: [(x * ux, y * uy) for x, y in pts]
    curve = catmull_rom(OUTLINE)
    img = Image.new("RGBA", (W * s, H * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # The outline: the same shape a little larger, in the edge colour, under the body.
    cx, cy = UNITS_W / 2, 4.6
    grown = [(cx + (x - cx) * 1.012, cy + (y - cy) * 1.03) for x, y in curve]
    d.polygon(to_px(grown), fill=EDGE)
    d.polygon(to_px(curve), fill=BODY)

    def well(x0, y0, x1, y1):
        d.ellipse((x0 * ux, y0 * uy, x1 * ux, y1 * uy), fill=WELL)

    # Wells under the sticks, the d-pad and the face buttons (centres match Layouts.lua).
    well(1.75, 2.05, 3.65, 3.95)      # left stick
    well(9.15, 3.85, 11.05, 5.75)     # right stick
    well(3.35, 2.65, 7.05, 6.35)      # d-pad
    well(10.65, 1.75, 14.35, 5.45)    # face buttons
    img = img.resize((W, H), Image.LANCZOS)
    return img.filter(ImageFilter.SMOOTH)


def circle():
    big = Image.new("RGBA", (64 * SUPER, 64 * SUPER), (255, 255, 255, 0))
    ImageDraw.Draw(big).ellipse((2 * SUPER, 2 * SUPER, 62 * SUPER, 62 * SUPER), fill=(255, 255, 255, 255))
    return big.resize((64, 64), Image.LANCZOS)


def main():
    controller().save(os.path.join(MEDIA, "controller.tga"), compression=None)
    circle().save(os.path.join(MEDIA, "circle.tga"), compression=None)
    print("made media/controller.tga, media/circle.tga")


if __name__ == "__main__":
    main()
