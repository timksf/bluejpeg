#!/usr/bin/env python3
"""Render .excalidraw scenes to plain SVG without Excalidraw itself.

    python3 assets/excalidraw_svg.py assets/toplevel.excalidraw [-o assets/toplevel.svg]

Draws the elements with straight strokes instead of Excalidraw's hand-drawn style, which keeps the
output small, deterministic and diffable. Supported: rectangle, ellipse, diamond, line, arrow
(triangle, triangle_outline, arrow, bar, dot heads), text (also bound to containers), freedraw;
rotation, dashed/dotted strokes, solid fills and opacity. Images and frames are skipped.
"""
import argparse
import json
import math
from html import escape
from pathlib import Path

FONT = "Helvetica, Arial, sans-serif"
PAD = 16


def fmt(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def stroke_attrs(e):
    w = e.get("strokeWidth", 2)
    a = f'stroke="{e.get("strokeColor", "#1e1e1e")}" stroke-width="{fmt(w)}" stroke-linecap="round" stroke-linejoin="round"'
    style = e.get("strokeStyle", "solid")
    if style == "dashed":
        a += f' stroke-dasharray="{fmt(8 * w / 2)} {fmt(6 * w / 2)}"'
    elif style == "dotted":
        a += f' stroke-dasharray="1.5 {fmt(6 * w / 2)}"'
    return a


def fill_attr(e):
    bg = e.get("backgroundColor", "transparent")
    return 'fill="none"' if bg in ("transparent", None, "") else f'fill="{bg}"'


def group_open(e):
    cx, cy = e["x"] + e["width"] / 2, e["y"] + e["height"] / 2
    attrs = []
    if e.get("angle"):
        attrs.append(f'transform="rotate({fmt(math.degrees(e["angle"]))} {fmt(cx)} {fmt(cy)})"')
    if e.get("opacity", 100) != 100:
        attrs.append(f'opacity="{fmt(e["opacity"] / 100)}"')
    return f'<g {" ".join(attrs)}>' if attrs else "<g>"


def arrowhead(kind, tip, prev, e):
    """Arrowhead at tip, pointing away from prev."""
    if not kind:
        return ""
    w = e.get("strokeWidth", 2)
    ang = math.atan2(tip[1] - prev[1], tip[0] - prev[0])
    size = 10 + 2 * w
    col = e.get("strokeColor", "#1e1e1e")

    def at(dist, off):
        return (tip[0] - dist * math.cos(ang) + off * math.sin(ang), tip[1] - dist * math.sin(ang) - off * math.cos(ang))

    if kind in ("triangle", "triangle_outline"):
        p = [tip, at(size, size * 0.45), at(size, -size * 0.45)]
        pts = " ".join(f"{fmt(x)},{fmt(y)}" for x, y in p)
        fill = col if kind == "triangle" else "#ffffff"
        return f'<polygon points="{pts}" fill="{fill}" stroke="{col}" stroke-width="{fmt(w)}" stroke-linejoin="round"/>'
    if kind == "bar":
        a, b = at(0, size * 0.5), at(0, -size * 0.5)
        return f'<line x1="{fmt(a[0])}" y1="{fmt(a[1])}" x2="{fmt(b[0])}" y2="{fmt(b[1])}" stroke="{col}" stroke-width="{fmt(w)}" stroke-linecap="round"/>'
    if kind in ("dot", "circle", "circle_outline"):
        c = at(size * 0.3, 0)
        fill = "#ffffff" if kind == "circle_outline" else col
        return f'<circle cx="{fmt(c[0])}" cy="{fmt(c[1])}" r="{fmt(size * 0.3)}" fill="{fill}" stroke="{col}" stroke-width="{fmt(w)}"/>'
    a, b = at(size, size * 0.45), at(size, -size * 0.45)  # "arrow" and anything unknown: open chevron
    return f'<polyline points="{fmt(a[0])},{fmt(a[1])} {fmt(tip[0])},{fmt(tip[1])} {fmt(b[0])},{fmt(b[1])}" fill="none" stroke="{col}" stroke-width="{fmt(w)}" stroke-linecap="round" stroke-linejoin="round"/>'


def render_element(e):
    t = e["type"]
    x, y, w, h = e["x"], e["y"], e["width"], e["height"]
    out = [group_open(e)]
    if t == "rectangle":
        r = min(w, h) * 0.25 if e.get("roundness") else 0
        r = min(r, 32) if e.get("roundness") and e["roundness"].get("type") == 3 else r
        out.append(f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" rx="{fmt(r)}" {fill_attr(e)} {stroke_attrs(e)}/>')
    elif t == "ellipse":
        out.append(f'<ellipse cx="{fmt(x + w / 2)}" cy="{fmt(y + h / 2)}" rx="{fmt(w / 2)}" ry="{fmt(h / 2)}" {fill_attr(e)} {stroke_attrs(e)}/>')
    elif t == "diamond":
        pts = f"{fmt(x + w / 2)},{fmt(y)} {fmt(x + w)},{fmt(y + h / 2)} {fmt(x + w / 2)},{fmt(y + h)} {fmt(x)},{fmt(y + h / 2)}"
        out.append(f'<polygon points="{pts}" {fill_attr(e)} {stroke_attrs(e)}/>')
    elif t in ("line", "arrow", "freedraw"):
        pts = [(x + px, y + py) for px, py in e.get("points", [])]
        if len(pts) >= 2:
            s = " ".join(f"{fmt(px)},{fmt(py)}" for px, py in pts)
            closed = t == "line" and pts[0] == pts[-1] and len(pts) > 2
            fill = fill_attr(e) if closed else 'fill="none"'
            out.append(f'<polyline points="{s}" {fill} {stroke_attrs(e)}/>')
            if t == "arrow":
                out.append(arrowhead(e.get("endArrowhead"), pts[-1], pts[-2], e))
                out.append(arrowhead(e.get("startArrowhead"), pts[0], pts[1], e))
    elif t == "text":
        size = e.get("fontSize", 20)
        lh = size * e.get("lineHeight", 1.25)
        lines = e.get("text", "").split("\n")
        align = e.get("textAlign", "left")
        anchor, tx = {"left": ("start", x), "center": ("middle", x + w / 2), "right": ("end", x + w)}[align]
        top = y + (h - lh * len(lines)) / 2 if e.get("verticalAlign") == "middle" else y
        spans = "".join(f'<tspan x="{fmt(tx)}" y="{fmt(top + lh * (i + 0.5))}">{escape(line) or " "}</tspan>' for i, line in enumerate(lines))
        out.append(f'<text font-family="{FONT}" font-size="{fmt(size)}" fill="{e.get("strokeColor", "#1e1e1e")}" text-anchor="{anchor}" dominant-baseline="central">{spans}</text>')
    else:
        return ""
    out.append("</g>")
    return "".join(out)


def bounds(e):
    """Axis-aligned bounds of an element, including rotation."""
    if e["type"] in ("line", "arrow", "freedraw") and e.get("points"):
        xs = [e["x"] + p[0] for p in e["points"]]
        ys = [e["y"] + p[1] for p in e["points"]]
        corners = list(zip(xs, ys))
    else:
        corners = [(e["x"], e["y"]), (e["x"] + e["width"], e["y"]), (e["x"], e["y"] + e["height"]), (e["x"] + e["width"], e["y"] + e["height"])]
    a = e.get("angle", 0)
    if a:
        cx, cy = e["x"] + e["width"] / 2, e["y"] + e["height"] / 2
        corners = [(cx + (px - cx) * math.cos(a) - (py - cy) * math.sin(a), cy + (px - cx) * math.sin(a) + (py - cy) * math.cos(a)) for px, py in corners]
    return min(c[0] for c in corners), min(c[1] for c in corners), max(c[0] for c in corners), max(c[1] for c in corners)


def render(scene):
    els = [e for e in scene["elements"] if not e.get("isDeleted") and e["type"] not in ("image", "frame", "magicframe", "embeddable")]
    bs = [bounds(e) for e in els]
    x0, y0 = min(b[0] for b in bs) - PAD, min(b[1] for b in bs) - PAD
    x1, y1 = max(b[2] for b in bs) + PAD, max(b[3] for b in bs) + PAD
    bg = scene.get("appState", {}).get("viewBackgroundColor", "#ffffff")
    body = "\n".join(filter(None, (render_element(e) for e in els)))
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{fmt(x0)} {fmt(y0)} {fmt(x1 - x0)} {fmt(y1 - y0)}" width="{fmt(x1 - x0)}" height="{fmt(y1 - y0)}">\n'
            f'<rect x="{fmt(x0)}" y="{fmt(y0)}" width="{fmt(x1 - x0)}" height="{fmt(y1 - y0)}" fill="{bg}"/>\n{body}\n</svg>\n')


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("scene", type=Path)
    ap.add_argument("-o", "--output", type=Path, help="default: the scene path with .svg")
    args = ap.parse_args()
    out = args.output or args.scene.with_suffix(".svg")
    out.write_text(render(json.loads(args.scene.read_text())))
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
