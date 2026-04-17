#!/usr/bin/env python3
"""Generate app icon for LuxSwitch — diagonal sun/moon split with cycle arrows."""

import math
from PIL import Image, ImageDraw, ImageFilter

MASTER_SIZE = 1024

ICON_VARIANTS = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]


def lerp_color(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def draw_icon(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cx, cy = size / 2, size / 2
    r = size * 0.46

    # --- Draw the main circle with a clean diagonal split ---
    # Diagonal line from top-right to bottom-left (perpendicular to the line y = x)
    # Points above-left of the diagonal are "light", below-right are "dark"
    for y in range(size):
        for x in range(size):
            dx, dy = x - cx, y - cy
            dist = math.sqrt(dx * dx + dy * dy)
            if dist > r:
                continue

            # Signed distance to the diagonal (x + y = cx + cy, i.e. y = -x + size)
            # Positive = below-right (dark), negative = above-left (light)
            diag_dist = (dx + dy) / math.sqrt(2)

            # Sharp split with a very thin anti-aliased edge (2px)
            aa_width = 1.5
            if diag_dist < -aa_width:
                t = 0.0  # light side
            elif diag_dist > aa_width:
                t = 1.0  # dark side
            else:
                t = (diag_dist + aa_width) / (2 * aa_width)
                t = t * t * (3 - 2 * t)  # smoothstep

            # Light side: warm golden gradient (slightly varies with position)
            norm_dist = dist / r
            light_color = lerp_color((255, 200, 50), (245, 170, 30), norm_dist * 0.6)
            # Dark side: deep indigo gradient
            dark_color = lerp_color((35, 45, 95), (18, 22, 55), norm_dist * 0.5)

            color = lerp_color(light_color, dark_color, t)

            # Subtle edge shading for depth
            edge_factor = max(0, (norm_dist - 0.88)) / 0.12
            if edge_factor > 0:
                color = tuple(int(c * (1.0 - edge_factor * 0.2)) for c in color)

            img.putpixel((x, y), (*color, 255))

    # --- Sun disc on the light side (upper-left area) ---
    sun_cx = cx - r * 0.35
    sun_cy = cy - r * 0.35
    sun_r = r * 0.18

    # Sun glow/rays
    for y in range(max(0, int(sun_cy - sun_r * 2.5)), min(size, int(sun_cy + sun_r * 2.5))):
        for x in range(max(0, int(sun_cx - sun_r * 2.5)), min(size, int(sun_cx + sun_r * 2.5))):
            mdx, mdy = x - cx, y - cy
            if math.sqrt(mdx * mdx + mdy * mdy) > r:
                continue
            # Only on light side
            if (mdx + mdy) / math.sqrt(2) > 0:
                continue

            sdx, sdy = x - sun_cx, y - sun_cy
            sdist = math.sqrt(sdx * sdx + sdy * sdy)
            if sdist < sun_r or sdist > sun_r * 2.2:
                continue

            angle = math.atan2(sdy, sdx)
            ray = (math.sin(angle * 9 + 0.5) + 1) / 2
            ray_intensity = ray * max(0, 1 - (sdist - sun_r) / (sun_r * 1.2))
            ray_intensity *= 0.35

            if ray_intensity > 0.03:
                existing = img.getpixel((x, y))
                glow = (255, 245, 190)
                blended = lerp_color(existing[:3], glow, ray_intensity)
                img.putpixel((x, y), (*blended, 255))

    # Sun disc
    for y in range(max(0, int(sun_cy - sun_r - 2)), min(size, int(sun_cy + sun_r + 2))):
        for x in range(max(0, int(sun_cx - sun_r - 2)), min(size, int(sun_cx + sun_r + 2))):
            sdx, sdy = x - sun_cx, y - sun_cy
            sdist = math.sqrt(sdx * sdx + sdy * sdy)
            if sdist > sun_r + 1:
                continue
            aa = max(0, 1 - max(0, sdist - (sun_r - 1.2)) / 1.2)
            if aa > 0:
                sc = lerp_color((255, 240, 140), (255, 225, 90), sdist / sun_r)
                existing = img.getpixel((x, y))
                blended = lerp_color(existing[:3], sc, aa)
                img.putpixel((x, y), (*blended, 255))

    # --- Moon crescent on the dark side (lower-right area) ---
    moon_cx = cx + r * 0.33
    moon_cy = cy + r * 0.33
    moon_r = r * 0.18
    bite_cx = moon_cx + moon_r * 0.5
    bite_cy = moon_cy - moon_r * 0.5
    bite_r = moon_r * 0.75

    for y in range(max(0, int(moon_cy - moon_r - 2)), min(size, int(moon_cy + moon_r + 2))):
        for x in range(max(0, int(moon_cx - moon_r - 2)), min(size, int(moon_cx + moon_r + 2))):
            mdx, mdy = x - cx, y - cy
            if math.sqrt(mdx * mdx + mdy * mdy) > r:
                continue

            dx, dy = x - moon_cx, y - moon_cy
            dist = math.sqrt(dx * dx + dy * dy)
            if dist > moon_r + 1:
                continue

            bdx, bdy = x - bite_cx, y - bite_cy
            bite_dist = math.sqrt(bdx * bdx + bdy * bdy)

            # Anti-alias moon edge
            moon_aa = max(0, 1 - max(0, dist - (moon_r - 1.2)) / 1.2)
            # Anti-alias bite edge (inverted — inside bite = transparent)
            bite_aa = max(0, min(1, (bite_dist - bite_r + 1.2) / 1.2))

            aa = moon_aa * bite_aa
            if aa > 0.01:
                mc = lerp_color((195, 205, 235), (170, 182, 218), dist / moon_r)
                existing = img.getpixel((x, y))
                blended = lerp_color(existing[:3], mc, aa)
                img.putpixel((x, y), (*blended, 255))

    # --- Small stars on the dark side ---
    stars = [
        (cx + r * 0.58, cy + r * 0.05, r * 0.022),
        (cx + r * 0.08, cy + r * 0.55, r * 0.018),
        (cx + r * 0.48, cy + r * 0.48, r * 0.015),
        (cx + r * 0.60, cy + r * 0.32, r * 0.013),
        (cx + r * 0.18, cy + r * 0.38, r * 0.016),
    ]
    for sx, sy, sr in stars:
        mdx, mdy = sx - cx, sy - cy
        if math.sqrt(mdx * mdx + mdy * mdy) + sr > r * 0.92:
            continue
        # Only on dark side
        if (mdx + mdy) / math.sqrt(2) < 2:
            continue
        for y2 in range(max(0, int(sy - sr - 2)), min(size, int(sy + sr + 2))):
            for x2 in range(max(0, int(sx - sr - 2)), min(size, int(sx + sr + 2))):
                d = math.sqrt((x2 - sx) ** 2 + (y2 - sy) ** 2)
                if d > sr + 1:
                    continue
                aa = max(0, 1 - max(0, d - (sr - 0.7)) / 0.7)
                if aa > 0:
                    existing = img.getpixel((x2, y2))
                    blended = lerp_color(existing[:3], (215, 220, 250), aa * 0.8)
                    img.putpixel((x2, y2), (*blended, 255))

    # --- Cycle/refresh arrows in the center ---
    arrow_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    arrow_r = r * 0.22          # radius of the arrow circle
    arrow_thick = r * 0.05      # thickness of the arrow stroke

    # Two arcs — defined by start and end angle.
    # On screen, increasing atan2 angle = clockwise visually (y is down).
    arc_spans = [
        (math.radians(-10), math.radians(105)),
        (math.radians(170), math.radians(285)),
    ]

    head_len = arrow_thick * 2.2        # how far the tip extends past the arc end
    head_half_w = arrow_thick * 1.75   # half-width of the arrowhead base

    def angle_in_range(a, start, end):
        a = a % (2 * math.pi)
        s = start % (2 * math.pi)
        e = end % (2 * math.pi)
        if s <= e:
            return s <= a <= e
        else:
            return a >= s or a <= e

    def cross_2d(ax, ay, bx, by):
        return ax * by - ay * bx

    def point_in_triangle(px, py, t0, t1, t2):
        """Signed-area test. Returns a smooth 0–1 value for anti-aliasing."""
        d0 = cross_2d(t1[0] - t0[0], t1[1] - t0[1], px - t0[0], py - t0[1])
        d1 = cross_2d(t2[0] - t1[0], t2[1] - t1[1], px - t1[0], py - t1[1])
        d2 = cross_2d(t0[0] - t2[0], t0[1] - t2[1], px - t2[0], py - t2[1])

        has_neg = (d0 < 0) or (d1 < 0) or (d2 < 0)
        has_pos = (d0 > 0) or (d1 > 0) or (d2 > 0)
        inside = not (has_neg and has_pos)

        if inside:
            return 1.0

        # Distance to nearest edge for AA fringe
        def dist_to_seg(px, py, ax, ay, bx, by):
            abx, aby = bx - ax, by - ay
            apx, apy = px - ax, py - ay
            t = max(0, min(1, (apx * abx + apy * aby) / max(1e-9, abx * abx + aby * aby)))
            return math.sqrt((apx - t * abx) ** 2 + (apy - t * aby) ** 2)

        d = min(
            dist_to_seg(px, py, *t0, *t1),
            dist_to_seg(px, py, *t1, *t2),
            dist_to_seg(px, py, *t2, *t0),
        )
        if d < 1.2:
            return max(0, 1.0 - d / 1.2)
        return 0.0

    # Precompute arrowhead triangles so arcs can avoid drawing under them
    arrowheads = []
    for _start, end in arc_spans:
        # Tangent (clockwise on screen) and radial at the arc end
        tan_x = -math.sin(end)
        tan_y = math.cos(end)
        rad_x = math.cos(end)
        rad_y = math.sin(end)

        # Base of arrowhead sits at the arc end, same width as stroke
        base_x = cx + arrow_r * math.cos(end)
        base_y = cy + arrow_r * math.sin(end)
        base1 = (base_x + rad_x * head_half_w, base_y + rad_y * head_half_w)
        base2 = (base_x - rad_x * head_half_w, base_y - rad_y * head_half_w)
        # Tip extends forward along the tangent
        tip = (base_x + tan_x * head_len, base_y + tan_y * head_len)

        arrowheads.append((tip, base1, base2))

    # Draw arcs
    scan_margin = arrow_r + arrow_thick + head_len + 4
    for y in range(max(0, int(cy - scan_margin)),
                   min(size, int(cy + scan_margin))):
        for x in range(max(0, int(cx - scan_margin)),
                       min(size, int(cx + scan_margin))):
            dx, dy = x - cx, y - cy
            dist = math.sqrt(dx * dx + dy * dy)
            ring_dist = abs(dist - arrow_r)
            if ring_dist > arrow_thick + 1.5:
                continue

            angle = math.atan2(dy, dx)
            if angle < 0:
                angle += 2 * math.pi

            in_arc = any(angle_in_range(angle, s, e) for s, e in arc_spans)
            if not in_arc:
                continue

            aa = max(0, 1 - max(0, ring_dist - (arrow_thick - 1.0)) / 1.0)
            if aa > 0:
                existing = arrow_layer.getpixel((x, y))
                new_a = int(aa * 230)
                if new_a > existing[3]:
                    arrow_layer.putpixel((x, y), (255, 255, 255, new_a))

    # Draw arrowheads with per-pixel anti-aliasing
    for tip, base1, base2 in arrowheads:
        # Bounding box of the triangle
        xs = [tip[0], base1[0], base2[0]]
        ys = [tip[1], base1[1], base2[1]]
        min_x, max_x = int(min(xs)) - 2, int(max(xs)) + 3
        min_y, max_y = int(min(ys)) - 2, int(max(ys)) + 3

        for y in range(max(0, min_y), min(size, max_y)):
            for x in range(max(0, min_x), min(size, max_x)):
                aa = point_in_triangle(x + 0.5, y + 0.5, tip, base1, base2)
                if aa > 0:
                    existing = arrow_layer.getpixel((x, y))
                    new_a = int(aa * 230)
                    if new_a > existing[3]:
                        arrow_layer.putpixel((x, y), (255, 255, 255, new_a))

    # Add a subtle drop shadow behind the arrows for readability on both halves
    shadow_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for y in range(size):
        for x in range(size):
            a = arrow_layer.getpixel((x, y))[3]
            if a > 10:
                shadow_layer.putpixel((x, y), (0, 0, 0, min(255, int(a * 0.4))))

    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=size * 0.006))
    # Offset shadow slightly down-right
    shadow_offset = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset = max(1, int(size * 0.003))
    shadow_offset.paste(shadow_layer, (offset, offset))

    img = Image.alpha_composite(img, shadow_offset)
    img = Image.alpha_composite(img, arrow_layer)

    return img


def main():
    import os
    import json

    base_dir = os.path.join(
        os.path.dirname(__file__),
        "LuxSwitch", "Assets.xcassets", "AppIcon.appiconset"
    )

    print("Generating master icon at 1024x1024...")
    master = draw_icon(MASTER_SIZE)

    contents_images = []
    for points, scale in ICON_VARIANTS:
        px = points * scale
        filename = f"icon_{points}x{points}@{scale}x.png"
        filepath = os.path.join(base_dir, filename)

        print(f"  {filename} ({px}x{px}px)")
        resized = master.resize((px, px), Image.LANCZOS)
        resized.save(filepath, "PNG")

        contents_images.append({
            "filename": filename,
            "idiom": "mac",
            "scale": f"{scale}x",
            "size": f"{points}x{points}",
        })

    contents = {
        "images": contents_images,
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(base_dir, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)

    print(f"Done! Written to {base_dir}")


if __name__ == "__main__":
    main()
