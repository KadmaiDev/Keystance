"""Makes the controller drawing for the Keyboard tab's Controller layout, and a round cap:

    python tools/make_controller.py

  media/controller.tga  512x256, a controller's silhouette (flat, dark, with a soft outline),
                        drawn in the layout's own units so the buttons in Layouts.lua sit on it
  media/circle.tga      64x64, a white disc: round button backgrounds (tinted in game) and
                        the mask that makes their icons round

The game wants uncompressed 32-bit TGA files with power-of-two sizes.
"""
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "media")

# The layout's board is 15.5 x 8 key units; the image covers it.
UNITS_W, UNITS_H = 15.5, 8.0
W, H = 512, 256
SUPER = 4  # drawn larger, then shrunk, for smooth edges
FILL = (34, 36, 42, 235)
EDGE = (92, 96, 108, 255)


def shape(draw, s, colour, grow=0.0):
    """The controller: a rounded body and two grips, in key units (y down)."""
    ux, uy = W * s / UNITS_W, H * s / UNITS_H

    def box(x0, y0, x1, y1):
        return (x0 * ux - grow * ux, y0 * uy - grow * uy, x1 * ux + grow * ux, y1 * uy + grow * uy)

    draw.rounded_rectangle(box(0.9, 1.7, 14.6, 5.4), radius=1.4 * ux, fill=colour)
    draw.ellipse(box(0.7, 3.4, 5.6, 7.9), fill=colour)   # left grip
    draw.ellipse(box(9.9, 3.4, 14.8, 7.9), fill=colour)  # right grip
    draw.rounded_rectangle(box(0.9, 0.1, 3.3, 2.4), radius=0.6 * ux, fill=colour)    # left shoulder
    draw.rounded_rectangle(box(11.9, 0.1, 14.3, 2.4), radius=0.6 * ux, fill=colour)  # right shoulder


def controller():
    big = Image.new("RGBA", (W * SUPER, H * SUPER), (0, 0, 0, 0))
    edge = Image.new("RGBA", big.size, (0, 0, 0, 0))
    shape(ImageDraw.Draw(edge), SUPER, EDGE, grow=0.06)
    shape(ImageDraw.Draw(big), SUPER, FILL)
    out = Image.alpha_composite(edge, big).resize((W, H), Image.LANCZOS)
    return out.filter(ImageFilter.SMOOTH)


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
