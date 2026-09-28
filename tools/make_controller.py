"""Makes the controller drawing for the Keyboard tab's Controller layout, and a disc:

    python tools/make_controller.py

  media/controller.tga  512x512, an outline drawing of a controller (body, bumpers,
                        triggers, sticks, d-pad, face and menu buttons) in thin light
                        strokes, like a diagram. The drawing is PAD_W x PAD_H pixels as shown
                        in game (ns.PAD_W, ns.PAD_H in Layouts.lua), scaled to the texture's
                        width and centred in its height; the buttons sit where Layouts.lua's
                        `at` points say, so the callout lines meet them
  media/circle.tga      64x64, a white disc: a button badge's backing and the lines' dots

The game wants uncompressed 32-bit TGA files with power-of-two sizes.
"""
import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "media")

PAD_W, PAD_H = 300, 218  # as shown in game
SIZE = 512
SUPER = 4  # drawn larger, then shrunk, for smooth edges
SCALE = SIZE / PAD_W
TOP = (SIZE - PAD_H * SCALE) / 2
STROKE = (212, 214, 222, 235)
FAINT = (212, 214, 222, 90)
FILL = (30, 32, 38, 150)
WIDTH = 2.0  # stroke width, in shown pixels

# The body, clockwise from the left shoulder, in shown pixels (y down). A smooth closed
# curve is drawn through these points.
BODY = [
    (40, 34), (75, 25), (115, 30), (150, 33), (185, 30), (225, 25), (260, 34),  # top
    (278, 58), (288, 100), (294, 150), (293, 190),                            # right side
    (282, 210), (262, 213), (242, 200), (222, 184),                           # right grip
    (190, 176), (150, 173), (110, 176),                                       # underside
    (78, 184), (58, 200), (38, 213), (18, 210),                               # left grip
    (7, 190), (6, 150), (12, 100), (22, 58),                                  # left side
]
# Bumpers: an open curve just outside each shoulder.
LEFT_BUMPER = [(26, 46), (40, 30), (70, 19), (102, 21)]
# The buttons (the same points as Layouts.lua's `at`).
LEFT_STICK, RIGHT_STICK = (80, 84), (190, 138)
DPAD = (115, 138)
FACE = [(228, 70), (246, 88), (210, 88), (228, 106)]  # Y, B, X, A
BACK, FORWARD, GUIDE = (126, 56), (174, 56), (150, 47)


def catmull_rom(points, closed=True, steps=24):
    """A smooth curve through the points."""
    out = []
    n = len(points)
    segments = range(n) if closed else range(n - 1)
    for i in segments:
        p0 = points[i - 1] if (closed or i > 0) else points[0]
        p1, p2 = points[i], points[(i + 1) % n]
        p3 = points[(i + 2) % n] if (closed or i + 2 < n) else points[-1]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * t
                                    + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2
                                    + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3) for k in (0, 1)))
    if not closed:
        out.append(points[-1])
    return out


def controller():
    s = SCALE * SUPER
    img = Image.new("RGBA", (SIZE * SUPER, SIZE * SUPER), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    width = round(WIDTH * s)

    def px(pts):
        return [(x * s, (y * SCALE + TOP) * SUPER) for x, y in pts]

    def circle(c, r, colour=STROKE, fill=None):
        (x, y), = px([c])
        d.ellipse((x - r * s, y - r * s, x + r * s, y + r * s), outline=colour, width=width, fill=fill)

    def rounded(x0, y0, x1, y1, r):
        (a, b), (c, e) = px([(x0, y0), (x1, y1)])
        d.rounded_rectangle((a, b, c, e), radius=r * s, outline=STROKE, width=width)

    # Triggers behind the bumpers, then the body.
    rounded(52, 2, 92, 14, 5)
    rounded(208, 2, 248, 14, 5)
    body = px(catmull_rom(BODY))
    d.polygon(body, fill=FILL)
    d.line(body + body[:1], fill=STROKE, width=width, joint="curve")
    for bumper in (LEFT_BUMPER, [(PAD_W - x, y) for x, y in LEFT_BUMPER]):
        d.line(px(catmull_rom(bumper, closed=False)), fill=STROKE, width=width, joint="curve")
    # Sticks: a cap inside a faint ring.
    for c in (LEFT_STICK, RIGHT_STICK):
        circle(c, 23, FAINT)
        circle(c, 16)
    # The d-pad: a cross.
    cx, cy = DPAD
    a, r = 8, 20
    cross = [(cx - a, cy - r), (cx + a, cy - r), (cx + a, cy - a), (cx + r, cy - a), (cx + r, cy + a),
             (cx + a, cy + a), (cx + a, cy + r), (cx - a, cy + r), (cx - a, cy + a), (cx - r, cy + a),
             (cx - r, cy - a), (cx - a, cy - a)]
    cross = px(cross)
    d.line(cross + cross[:1], fill=STROKE, width=width, joint="curve")
    for c in FACE:
        circle(c, 9)
    rounded(BACK[0] - 6, BACK[1] - 4, BACK[0] + 6, BACK[1] + 4, 2)
    circle(FORWARD, 5)
    circle(GUIDE, 10)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


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
