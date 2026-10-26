#!/usr/bin/env python3
"""Zeichnet das App-Icon von Orbit (hell, dunkel, getönt) als 1024×1024-PNG.

Aufruf: python3 Scripts/icon/make_icon.py App/Resources/Assets.xcassets/AppIcon.appiconset
Braucht Pillow. Gezeichnet wird 4-fach vergrößert und dann verkleinert (weiche Kanten).
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 4
S = SIZE * SCALE


def hex_rgb(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def diagonal_gradient(top_left, bottom_right):
    """Verlauf von oben links nach unten rechts."""
    small = Image.new("RGB", (256, 256))
    pixels = small.load()
    a, b = hex_rgb(top_left), hex_rgb(bottom_right)
    for y in range(256):
        for x in range(256):
            pixels[x, y] = lerp(a, b, (x + y) / 510)
    return small.resize((S, S), Image.BICUBIC)


def radial_glow(color, radius, alpha):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    c = S / 2
    draw.ellipse([c - radius, c - radius, c + radius, c + radius], fill=hex_rgb(color) + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.45))


def sphere(radius, light, dark):
    """Planet mit Verlauf von hell (oben links) nach dunkel (unten rechts)."""
    diameter = int(radius * 2)
    grad = Image.new("RGB", (64, 64))
    pixels = grad.load()
    a, b = hex_rgb(light), hex_rgb(dark)
    for y in range(64):
        for x in range(64):
            pixels[x, y] = lerp(a, b, min(1, (x + y) / 110))
    grad = grad.resize((diameter, diameter), Image.BICUBIC)
    mask = Image.new("L", (diameter, diameter), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, diameter - 1, diameter - 1], fill=255)
    out = Image.new("RGBA", (diameter, diameter), (0, 0, 0, 0))
    out.paste(grad, (0, 0), mask)
    return out


def orbit_layers(ring_color, ring_alpha, moons, back_moon):
    """Ring als zwei Ebenen (hinten / vorne), noch nicht gedreht."""
    back = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    front = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    c = S / 2
    a, b = 372 * SCALE, 142 * SCALE
    box = [c - a, c - b, c + a, c + b]
    width = 20 * SCALE
    color = hex_rgb(ring_color) + (ring_alpha,)
    # PIL-Winkel: 0° = rechts, im Uhrzeigersinn. 180–360 = obere (hintere) Hälfte.
    ImageDraw.Draw(back).arc(box, 180, 360, fill=color, width=width)
    ImageDraw.Draw(front).arc(box, 0, 180, fill=color, width=width)

    def point(angle):
        t = math.radians(angle)
        return c + a * math.cos(t), c + b * math.sin(t)

    def moon(layer, angle, radius, fill):
        x, y = point(angle)
        r = radius * SCALE
        ImageDraw.Draw(layer).ellipse([x - r, y - r, x + r, y + r], fill=hex_rgb(fill) + (255,))

    angle, radius, fill = back_moon
    moon(back, angle, radius, fill)
    for angle, radius, fill in moons:
        moon(front, angle, radius, fill)
    return back, front


def compose(background, glow, planet_light, planet_dark, ring_color, ring_alpha, moons, back_moon, tilt=-24):
    image = background.convert("RGBA")
    image.alpha_composite(radial_glow(glow, 360 * SCALE, 150))
    back, front = orbit_layers(ring_color, ring_alpha, moons, back_moon)
    image.alpha_composite(back.rotate(tilt, resample=Image.BICUBIC))
    radius = 200 * SCALE
    planet = sphere(radius, planet_light, planet_dark)
    halo = radial_glow(planet_dark, 250 * SCALE, 110)
    image.alpha_composite(halo)
    image.alpha_composite(planet, (int(S / 2 - radius), int(S / 2 - radius)))
    image.alpha_composite(front.rotate(tilt, resample=Image.BICUBIC))
    return image.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")


# Monde in den Bereichsfarben: Medikamente (Mint), Training (Koralle), Aufgaben (Weiß).
MOONS = [(40, 40, "#2DD4BF"), (128, 30, "#FB7185"), (165, 20, "#FFFFFF")]
BACK_MOON = (300, 24, "#A5B4FC")


def main(folder):
    folder = Path(folder)
    light = compose(
        diagonal_gradient("#312E81", "#6D28D9"), "#8B5CF6",
        "#FDE68A", "#F97316", "#FFFFFF", 235, MOONS, BACK_MOON,
    )
    light.save(folder / "AppIcon.png")

    dark = compose(
        diagonal_gradient("#0B0A1F", "#1E1B4B"), "#4338CA",
        "#FDE68A", "#F97316", "#E0E7FF", 220, MOONS, BACK_MOON,
    )
    dark.save(folder / "AppIcon-Dark.png")

    gray_moons = [(40, 40, "#FFFFFF"), (128, 30, "#D4D4D4"), (165, 20, "#FFFFFF")]
    tinted = compose(
        diagonal_gradient("#000000", "#000000"), "#000000",
        "#FFFFFF", "#9CA3AF", "#FFFFFF", 230, gray_moons, (300, 24, "#9CA3AF"),
    )
    tinted.convert("L").convert("RGB").save(folder / "AppIcon-Tinted.png")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
