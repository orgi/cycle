#!/usr/bin/env python3
"""Generates Radl's logo and app-icon sources from one geometry.

The logo is a bike wheel that is also a speedometer: tyre, laced spokes, an
orange speed arc and a needle. Everything is drawn on a 512-unit canvas and
written out as

* assets/branding/*.svg   master SVGs (icon, rounded preview, light, mono mark)
* Android vector drawables: the adaptive icon's foreground and monochrome
  layers (API 26+, sharp at any size) and the status-bar icon used by the
  recording notification.

PNGs (legacy Android launcher icons, iOS AppIcon, store icons) are rendered
from the master SVG by tool/gen_icon_pngs.sh. Run both after changing this file:

    python3 tool/gen_icons.py && tool/gen_icon_pngs.sh
"""
import math
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
C = 256  # canvas centre

# Geometry (canvas units).
TYRE_R, TYRE_W = 176, 36
ARC_R, ARC_W = 134, 24
ARC_START, ARC_END = -135, 40  # degrees, 0 = up, clockwise; needle at ARC_END
HUB_R, HUB_DOT_R = 24, 9
SPOKES, SPOKE_HUB_R, SPOKE_RIM_R, SPOKE_W, SPOKE_LEAD = 24, 30, 158, 4.5, 28

DARK = dict(bg="#0B0D10", fg="#E9EEF2", spoke="#3A4048", a0="#FF6A00", a1="#FFB15C")
LIGHT = dict(bg="#F3F5F7", fg="#16191D", spoke="#B4BCC5", a0="#E85D00", a1="#FF9A3C")


def pt(r, deg, cx=C, cy=C):
    a = math.radians(deg)
    return cx + r * math.sin(a), cy - r * math.cos(a)


def f(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def arc_d(r, a0, a1):
    x0, y0 = pt(r, a0)
    x1, y1 = pt(r, a1)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return f"M{f(x0)},{f(y0)} A{r},{r} 0 {large} 1 {f(x1)},{f(y1)}"


def circle_d(r):
    """A full circle as path data (vector drawables have no <circle>)."""
    return f"M{C - r},{C} A{r},{r} 0 1 1 {C + r},{C} A{r},{r} 0 1 1 {C - r},{C} Z"


def spokes_d():
    # Laced like a real wheel: each spoke leaves the hub flange and meets the
    # rim SPOKE_LEAD degrees ahead or behind, alternating, so they cross.
    out = []
    for i in range(SPOKES):
        a = i * 360 / SPOKES
        lead = 1 if i % 2 else -1
        x0, y0 = pt(SPOKE_HUB_R, a)
        x1, y1 = pt(SPOKE_RIM_R, a + lead * SPOKE_LEAD)
        out.append(f"M{f(x0)},{f(y0)} L{f(x1)},{f(y1)}")
    return " ".join(out)


def needle_d(deg=ARC_END, length=118, base=11, tip=3.5):
    """Tapered needle from the hub to a round tip."""
    b1 = pt(base, deg - 90)
    b2 = pt(base, deg + 90)
    tx, ty = pt(length, deg)
    t1 = pt(tip, deg - 90, tx, ty)
    t2 = pt(tip, deg + 90, tx, ty)
    return (f"M{f(b1[0])},{f(b1[1])} L{f(t1[0])},{f(t1[1])} "
            f"A{tip},{tip} 0 0 1 {f(t2[0])},{f(t2[1])} L{f(b2[0])},{f(b2[1])} Z")


# Speed-arc gradient runs from its lower-left end to its upper-right end.
GRAD = (C - ARC_R, pt(ARC_R, ARC_START)[1], pt(ARC_R, ARC_END)[0], C - ARC_R)


def icon_svg(pal, rounded):
    bg = (f'<rect width="512" height="512" rx="112" fill="{pal["bg"]}"/>' if rounded
          else f'<rect width="512" height="512" fill="{pal["bg"]}"/>')
    x1, y1, x2, y2 = GRAD
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <defs>
    <linearGradient id="arc" gradientUnits="userSpaceOnUse" x1="{f(x1)}" y1="{f(y1)}" x2="{f(x2)}" y2="{f(y2)}">
      <stop offset="0" stop-color="{pal["a0"]}"/>
      <stop offset="1" stop-color="{pal["a1"]}"/>
    </linearGradient>
  </defs>
  {bg}
  <path d="{spokes_d()}" fill="none" stroke="{pal["spoke"]}" stroke-width="{SPOKE_W}" stroke-linecap="round"/>
  <path d="{circle_d(TYRE_R)}" fill="none" stroke="{pal["fg"]}" stroke-width="{TYRE_W}"/>
  <path d="{arc_d(ARC_R, ARC_START, ARC_END)}" fill="none" stroke="url(#arc)" stroke-width="{ARC_W}" stroke-linecap="round"/>
  <path d="{needle_d()}" fill="{pal["fg"]}"/>
  <path d="{circle_d(HUB_R)}" fill="{pal["fg"]}"/>
  <path d="{circle_d(HUB_DOT_R)}" fill="{pal["a0"]}"/>
</svg>
'''


# The single-colour mark (themed icons, status bar): no spokes, bolder lines.
MONO = dict(tyre_w=40, arc_r=130, arc_w=34, needle=dict(length=112, base=14, tip=5), hub_r=28)


def mono_paths(color):
    m = MONO
    return [
        ("stroke", circle_d(TYRE_R), m["tyre_w"], color),
        ("stroke", arc_d(m["arc_r"], ARC_START, ARC_END), m["arc_w"], color),
        ("fill", needle_d(**m["needle"]), None, color),
        ("fill", circle_d(m["hub_r"]), None, color),
    ]


def mono_svg():
    body = []
    for kind, d, w, col in mono_paths("#000000"):
        if kind == "stroke":
            body.append(f'  <path d="{d}" fill="none" stroke="{col}" stroke-width="{w}" stroke-linecap="round"/>')
        else:
            body.append(f'  <path d="{d}" fill="{col}"/>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">\n'
            + "\n".join(body) + "\n</svg>\n")


def vd_path(kind, d, w, color):
    if kind == "stroke":
        return (f'        <path android:pathData="{d}" android:strokeColor="{color}"\n'
                f'            android:strokeWidth="{w}" android:strokeLineCap="round"/>')
    return f'        <path android:pathData="{d}" android:fillColor="{color}"/>'


def vector(size_dp, viewport, scale, translate, paths, aapt=False):
    ns = ' xmlns:aapt="http://schemas.android.com/aapt"' if aapt else ""
    return f'''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/gen_icons.py. Do not edit; change the script and re-run it. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"{ns}
    android:width="{size_dp}dp" android:height="{size_dp}dp"
    android:viewportWidth="{viewport}" android:viewportHeight="{viewport}">
    <group android:scaleX="{scale}" android:scaleY="{scale}"
        android:translateX="{translate}" android:translateY="{translate}">
{chr(10).join(paths)}
    </group>
</vector>
'''


def adaptive_foreground():
    # Adaptive icons are 108dp; launchers show the middle 72dp (masked) and
    # guarantee the central 66dp circle. The 512 canvas maps onto that 72dp, so
    # the tyre's outer edge (194 units) sits at ~27dp, inside the safe circle.
    p = DARK
    x1, y1, x2, y2 = GRAD
    arc = f'''        <path android:pathData="{arc_d(ARC_R, ARC_START, ARC_END)}"
            android:strokeWidth="{ARC_W}" android:strokeLineCap="round">
            <aapt:attr name="android:strokeColor">
                <gradient android:type="linear"
                    android:startX="{f(x1)}" android:startY="{f(y1)}"
                    android:endX="{f(x2)}" android:endY="{f(y2)}"
                    android:startColor="{p["a0"]}" android:endColor="{p["a1"]}"/>
            </aapt:attr>
        </path>'''
    paths = [
        vd_path("stroke", spokes_d(), SPOKE_W, p["spoke"]),
        vd_path("stroke", circle_d(TYRE_R), TYRE_W, p["fg"]),
        arc,
        vd_path("fill", needle_d(), None, p["fg"]),
        vd_path("fill", circle_d(HUB_R), None, p["fg"]),
        vd_path("fill", circle_d(HUB_DOT_R), None, p["a0"]),
    ]
    return vector(108, 108, f(72 / 512), 18, paths, aapt=True)


def adaptive_monochrome():
    paths = [vd_path(*p) for p in mono_paths("#FF000000")]
    return vector(108, 108, f(72 / 512), 18, paths)


def status_bar_icon():
    # 24dp, white on transparent (Android tints status-bar icons itself). The
    # mono mark's outer edge (196 units) fills the frame with a 1dp margin.
    scale = 22 / (2 * 196)
    paths = [vd_path(*p) for p in mono_paths("#FFFFFFFF")]
    return vector(24, 24, f(scale), f(12 - C * scale), paths)


ADAPTIVE_XML = '''<?xml version="1.0" encoding="utf-8"?>
<!-- Radl launcher icon (API 26+). Layers come from tool/gen_icons.py. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>
</adaptive-icon>
'''


def main():
    brand = ROOT / "assets" / "branding"
    brand.mkdir(parents=True, exist_ok=True)
    (brand / "radl_icon.svg").write_text(icon_svg(DARK, rounded=False))
    (brand / "radl_icon_rounded.svg").write_text(icon_svg(DARK, rounded=True))
    (brand / "radl_icon_light.svg").write_text(icon_svg(LIGHT, rounded=True))
    (brand / "radl_mark_mono.svg").write_text(mono_svg())

    res = ROOT / "android" / "app" / "src" / "main" / "res"
    (res / "drawable" / "ic_launcher_foreground.xml").write_text(adaptive_foreground())
    (res / "drawable" / "ic_launcher_monochrome.xml").write_text(adaptive_monochrome())
    (res / "drawable" / "ic_stat_radl.xml").write_text(status_bar_icon())
    (res / "mipmap-anydpi-v26").mkdir(exist_ok=True)
    (res / "mipmap-anydpi-v26" / "ic_launcher.xml").write_text(ADAPTIVE_XML)
    (res / "values" / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- Generated by tool/gen_icons.py. -->\n'
        f'<resources>\n    <color name="ic_launcher_background">{DARK["bg"]}</color>\n</resources>\n')
    print("wrote assets/branding/*.svg and the Android vector drawables")


if __name__ == "__main__":
    main()
