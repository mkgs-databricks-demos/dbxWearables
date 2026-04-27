#!/usr/bin/env python3
"""Generate the iOS app icon for dbxWearables.

Renders a 1024x1024 PNG that Xcode auto-resizes to every required size.
Design: Databricks red gradient background, a white EKG/pulse waveform
across the center, with a stylized heart accent. Mirrors the in-app
brand colors (DBXColors.dbxRed / dbxOrange / dbxNavy / dbxDarkTeal).
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
OUTPUT = Path(__file__).resolve().parent.parent / (
    "healthKit/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
)


def hex_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))


DBX_RED = hex_rgb("FF3621")
DBX_ORANGE = hex_rgb("FF6A33")
DBX_ORANGE_DEEP = hex_rgb("E25420")
DBX_NAVY = hex_rgb("0D2228")
WHITE = (255, 255, 255)


def diagonal_gradient(size: int, top_left: tuple[int, int, int], bottom_right: tuple[int, int, int]) -> Image.Image:
    """Linear gradient from top-left to bottom-right."""
    base = Image.new("RGB", (size, size), top_left)
    pixels = base.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            r = int(top_left[0] + (bottom_right[0] - top_left[0]) * t)
            g = int(top_left[1] + (bottom_right[1] - top_left[1]) * t)
            b = int(top_left[2] + (bottom_right[2] - top_left[2]) * t)
            pixels[x, y] = (r, g, b)
    return base


def heart_polygon(cx: int, cy: int, scale: float) -> list[tuple[float, float]]:
    """Return points tracing a heart shape centered at (cx, cy).

    Uses the classic parametric heart curve, which gives a clean
    silhouette without relying on bezier composition.
    """
    import math

    points: list[tuple[float, float]] = []
    steps = 720
    for i in range(steps):
        t = (i / steps) * 2 * math.pi
        # Parametric heart curve.
        x = 16 * (math.sin(t) ** 3)
        y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
        points.append((cx + x * scale, cy + y * scale))
    return points


def pulse_polyline(cx: int, cy: int, span: int, height: int) -> list[tuple[int, int]]:
    """A stylized EKG/pulse waveform centered on (cx, cy)."""
    half = span // 2
    h = height
    return [
        (cx - half, cy),
        (cx - half + int(span * 0.18), cy),
        (cx - half + int(span * 0.26), cy - int(h * 0.15)),
        (cx - half + int(span * 0.32), cy + int(h * 0.20)),
        (cx - half + int(span * 0.38), cy - int(h * 0.95)),
        (cx - half + int(span * 0.46), cy + int(h * 0.55)),
        (cx - half + int(span * 0.52), cy),
        (cx - half + int(span * 0.62), cy),
        (cx - half + int(span * 0.68), cy - int(h * 0.20)),
        (cx - half + int(span * 0.74), cy),
        (cx + half, cy),
    ]


def render() -> Image.Image:
    icon = diagonal_gradient(SIZE, DBX_ORANGE, DBX_ORANGE_DEEP).convert("RGBA")

    # Soft vignette towards corners to add depth.
    vignette = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    v_draw = ImageDraw.Draw(vignette)
    v_draw.ellipse(
        (-int(SIZE * 0.15), -int(SIZE * 0.15), int(SIZE * 1.15), int(SIZE * 1.15)),
        fill=(*DBX_NAVY, 60),
    )
    icon = Image.alpha_composite(icon, vignette.filter(ImageFilter.GaussianBlur(120)))

    # Heart silhouette (white, slightly translucent so the gradient bleeds through).
    cx, cy = SIZE // 2, int(SIZE * 0.46)
    heart_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    h_draw = ImageDraw.Draw(heart_layer)
    h_draw.polygon(heart_polygon(cx, cy, scale=22.5), fill=(*WHITE, 235))
    icon = Image.alpha_composite(icon, heart_layer)

    # EKG pulse line — drawn in DBX_NAVY for contrast against the white heart.
    pulse_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    p_draw = ImageDraw.Draw(pulse_layer)
    pulse_pts = pulse_polyline(cx=SIZE // 2, cy=int(SIZE * 0.52), span=int(SIZE * 0.78), height=int(SIZE * 0.18))
    p_draw.line(pulse_pts, fill=(*DBX_NAVY, 255), width=42, joint="curve")
    icon = Image.alpha_composite(icon, pulse_layer)

    # Wordmark-style accent dot at the pulse origin (echoes the Databricks "data point" idea).
    dot_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d_draw = ImageDraw.Draw(dot_layer)
    dot_x = int(SIZE * 0.12)
    dot_y = int(SIZE * 0.52)
    d_draw.ellipse((dot_x - 26, dot_y - 26, dot_x + 26, dot_y + 26), fill=(*DBX_NAVY, 255))
    icon = Image.alpha_composite(icon, dot_layer)

    return icon.convert("RGB")


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image = render()
    image.save(OUTPUT, format="PNG", optimize=True)
    print(f"Wrote {OUTPUT} ({image.size[0]}x{image.size[1]})")


if __name__ == "__main__":
    main()
