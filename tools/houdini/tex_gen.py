"""Procedural, seamless 512x512 material textures for the Sandblood props (numpy + PIL, run inside hython).

Imported by build_textures.py. Every pattern is built from periodic sources (FFT-filtered noise, wrapped Worley cells,
integer-frequency sines, wrapped line strokes), so every map tiles with no seam.

Image axes: x (columns) = u = around a loft, y (rows) = v = along it. Wood grain and brushed metal run along v.

Kinds of map:
  <family>_albedo.png  sRGB base colour. Its linear mean is TEX_MEAN[name]; the material's baseColorFactor is
                       its own colour divided by that mean, so one texture can serve several tints.
  <family>_orm.png     linear R = occlusion (cavities), G = roughness (mean ORM_G_MEAN, so roughnessFactor =
                       material roughness / ORM_G_MEAN), B = metalness (255 for metal families, 0 otherwise).
  <family>_normal.png  tangent-space normal map, OpenGL / glTF convention (+Y = image up).
"""
import math
import os

import numpy as np
from PIL import Image

N = 512
ORM_G_MEAN = 0.9
_yy, _xx = np.mgrid[0:N, 0:N].astype(np.float64)
_FY = np.fft.fftfreq(N)[:, None]
_FX = np.fft.fftfreq(N)[None, :]


# ---------------------------------------------------------------- periodic building blocks

def rng(seed):
    return np.random.default_rng(seed)


def blur(a, sx, sy=None):
    """Gaussian blur with wrap-around (so it keeps the tiling)."""
    sy = sx if sy is None else sy
    k = np.exp(-2.0 * math.pi ** 2 * ((_FX * sx) ** 2 + (_FY * sy) ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * k))


def std(a):
    a = a - a.mean()
    s = a.std()
    return a / s if s > 0 else a


def noise(seed, sx, sy=None):
    """Tileable smooth noise with features about sx (and sy) pixels across; zero mean, unit deviation."""
    return std(blur(rng(seed).standard_normal((N, N)), sx, sy))


def fbm(seed, scale, octaves=4, gain=0.5, aniso=(1.0, 1.0)):
    out = np.zeros((N, N))
    amp = 1.0
    for o in range(octaves):
        s = scale / (2 ** o)
        out += amp * noise(seed * 31 + o, max(s * aniso[0], 0.6), max(s * aniso[1], 0.6))
        amp *= gain
    return std(out)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def worley(seed, cells):
    """Wrapped Worley noise: F1, F2 (in pixels) and a random value per nearest cell."""
    r = rng(seed)
    pts = r.random((cells, cells, 2))
    val = r.random((cells, cells))
    cs = N / cells
    cx = (_xx // cs).astype(int)
    cy = (_yy // cs).astype(int)
    f1 = np.full((N, N), 1e9)
    f2 = np.full((N, N), 1e9)
    v1 = np.zeros((N, N))
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            nx = cx + dx
            ny = cy + dy
            wx = nx % cells
            wy = ny % cells
            px = (nx + pts[wy, wx, 0]) * cs
            py = (ny + pts[wy, wx, 1]) * cs
            d = np.hypot(_xx + 0.5 - px, _yy + 0.5 - py)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            v1 = np.where(closer, val[wy, wx], v1)
            f1 = np.where(closer, d, f1)
    return f1, f2, v1


def strokes(seed, count, length, angle, spread, width=0.6, strength=(0.4, 1.0)):
    """Thin wrapped line strokes (scratches). angle 0 = along x (u), pi/2 = along y (v)."""
    r = rng(seed)
    img = np.zeros((N, N))
    for _ in range(count):
        x0, y0 = r.random(2) * N
        a = angle + r.normal(0.0, spread)
        L = length * (0.3 + r.random())
        s = r.uniform(*strength)
        bend = r.normal(0.0, 0.0006)
        t = np.arange(0.0, L, 0.5)
        aa = a + bend * t
        xs = (x0 + np.cos(aa) * t) % N
        ys = (y0 + np.sin(aa) * t) % N
        fade = np.sin(np.pi * t / L) ** 0.5
        np.add.at(img, (ys.astype(int), xs.astype(int)), s * fade)
    img = np.minimum(img, 1.5)
    return np.clip(blur(img, width) * 2.0, 0.0, 1.0)


def dots(seed, count, radius):
    r = rng(seed)
    img = np.zeros((N, N))
    ys = r.integers(0, N, count)
    xs = r.integers(0, N, count)
    img[ys, xs] = r.uniform(0.5, 1.0, count)
    out = blur(img, radius)
    return np.clip(out / (out.max() + 1e-9), 0.0, 1.0)


# ---------------------------------------------------------------- encoding

def lin2srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def srgb2lin(c):
    return np.where(c <= 0.04045, c / 12.92, np.power((c + 0.055) / 1.055, 2.4))


def to8(a):
    return np.clip(np.round(a * 255.0), 0, 255).astype(np.uint8)


def normal_from_height(h, strength):
    """h in pixels-of-height units scaled by strength; returns an RGB normal map (OpenGL +Y up)."""
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength  # rows grow downward = -up
    nx, ny, nz = -dx, dy, np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5


# ---------------------------------------------------------------- material families
# Each builder returns dict(albedo=linear RGB array, height=array or None, normal_strength=float,
#                           rough=array around 1.0 relative, ao=array 0..1, metal=bool)

def _lin(c):
    return np.array(c, dtype=np.float64)[None, None, :]


def fam_stone():
    grain = fbm(11, 3.0, 3)
    blot = fbm(12, 70.0, 3)
    f1, f2, cv = worley(13, 6)
    crack = 1.0 - smoothstep(0.0, 3.5 + 1.5 * (fbm(14, 20, 2) > 0), f2 - f1)  # thin cracks on cell borders
    crack *= smoothstep(0.3, 0.9, fbm(15, 40, 2))  # only some borders crack
    chips = dots(16, 160, 2.2) * (fbm(17, 6.0, 2) > -0.2)
    v = 1.0 + 0.05 * grain + 0.08 * blot + 0.10 * (cv - 0.5) - 0.42 * crack - 0.18 * chips
    hue = 1.0 + 0.04 * fbm(18, 90.0, 2)[..., None] * np.array([1.0, 0.2, -1.0])
    alb = _lin((0.66, 0.6, 0.5)) * v[..., None] * hue
    height = 0.6 * grain + 1.2 * blot + 2.0 * (cv - 0.5) - 6.0 * crack - 3.0 * chips
    rough = 1.0 + 0.05 * grain + 0.05 * crack
    ao = 1.0 - 0.45 * crack - 0.25 * chips
    return dict(albedo=alb, height=height, normal_strength=0.55, rough=rough, ao=ao, metal=False)


def fam_marble():
    t = fbm(21, 60.0, 4)
    vein = np.abs(np.sin(2 * math.pi * (2 * _xx + 1 * _yy) / N + 2.6 * t))
    vein = 1.0 - smoothstep(0.0, 0.22, vein)
    fine = np.abs(np.sin(2 * math.pi * (3 * _xx - 2 * _yy) / N + 3.5 * fbm(22, 40.0, 4)))
    fine = 1.0 - smoothstep(0.0, 0.04, fine)
    cloud = fbm(23, 90.0, 3)
    v = 1.0 + 0.03 * cloud - 0.16 * vein - 0.12 * fine
    tint = np.array([0.92, 0.95, 0.98])  # veins lean grey-green
    alb = _lin((0.86, 0.83, 0.77)) * (v[..., None] * (1 - (vein + fine)[..., None] * (1 - tint)))
    rough = 1.0 + 0.06 * cloud + 0.1 * vein
    return dict(albedo=alb, height=None, normal_strength=0.0, rough=rough, ao=np.ones((N, N)), metal=False)


def fam_wood():
    warp = fbm(31, 30.0, 3, aniso=(1.0, 6.0))
    rings = np.sin(2 * math.pi * 20 * _xx / N + 4.0 * warp)
    late = smoothstep(0.55, 0.95, rings)  # dark latewood lines
    pores = noise(32, 0.7, 14.0)
    streak = fbm(33, 12.0, 3, aniso=(1.0, 8.0))
    knot_f1, _, _ = worley(34, 3)
    knot = np.exp(-(knot_f1 / 9.0) ** 2) * (fbm(35, 40, 1) > 0.6)
    v = 1.0 + 0.10 * streak - 0.30 * late - 0.06 * (pores > 1.2) - 0.35 * knot
    alb = _lin((0.42, 0.27, 0.14)) * v[..., None] * (1.0 + 0.05 * streak[..., None] * np.array([1.0, 0.6, 0.2]))
    height = 1.5 * streak - 2.5 * late - 0.8 * (pores > 1.0) - 2.0 * knot
    rough = 1.0 + 0.04 * late + 0.04 * streak
    ao = 1.0 - 0.2 * late - 0.1 * (pores > 1.2)
    return dict(albedo=alb, height=height, normal_strength=0.45, rough=rough, ao=ao, metal=False)


def _metal_common():
    dents = fbm(41, 45.0, 3)
    scr_v = strokes(42, 180, 60.0, math.pi / 2, 0.25, 0.5, (0.15, 0.5))  # mostly along the part (v)
    scr_x = strokes(43, 90, 30.0, 0.0, 1.2, 0.5, (0.1, 0.4))
    scr = np.clip(scr_v + scr_x, 0.0, 1.0)
    pits = dots(44, 220, 1.1)
    brushed = noise(45, 0.8, 30.0)
    return dents, scr, pits, brushed


def fam_metal():
    """Shared metal ORM + normal (dents, scratches, pits); albedo maps are per metal below."""
    dents, scr, pits, brushed = _metal_common()
    height = 2.0 * dents - 1.6 * scr - 2.5 * pits + 0.25 * brushed
    rough = 1.0 + 0.08 * fbm(46, 60.0, 3) - 0.25 * scr + 0.15 * pits + 0.04 * brushed
    ao = 1.0 - 0.3 * pits - 0.1 * scr
    return dict(albedo=None, height=height, normal_strength=0.35, rough=rough, ao=ao, metal=True)


def alb_iron():
    dents, scr, pits, brushed = _metal_common()
    blot = fbm(51, 50.0, 3)
    rust = smoothstep(1.4, 2.2, fbm(52, 16.0, 4)) + 0.6 * pits
    v = 1.0 + 0.12 * blot + 0.35 * scr + 0.03 * brushed
    base = _lin((0.28, 0.28, 0.30)) * v[..., None]
    rustc = _lin((0.30, 0.14, 0.06))
    r = np.clip(rust, 0, 1)[..., None] * 0.7
    return base * (1 - r) + rustc * r


def alb_steel():
    # Reference colour is aluminium (the brightest steel-like metal); steel = factor 0.8.
    dents, scr, pits, brushed = _metal_common()
    v = 1.0 + 0.04 * brushed + 0.05 * fbm(61, 60.0, 3) + 0.18 * scr - 0.2 * pits
    return _lin((0.78, 0.79, 0.82)) * v[..., None]


def alb_bronze():
    dents, scr, pits, brushed = _metal_common()
    tarnish = fbm(71, 40.0, 4)
    patina = np.clip(smoothstep(1.6, 2.4, fbm(72, 9.0, 4)) + 0.6 * pits, 0, 1)[..., None] * 0.6
    v = 1.0 + 0.12 * tarnish + 0.3 * scr
    base = _lin((0.55, 0.37, 0.18)) * v[..., None]
    pc = _lin((0.25, 0.42, 0.33))
    return base * (1 - patina) + pc * patina


def alb_gold():
    # Reference colour is gold; brass and trim use tint factors.
    dents, scr, pits, brushed = _metal_common()
    v = 1.0 + 0.06 * fbm(81, 40.0, 4) + 0.08 * scr - 0.35 * pits + 0.02 * brushed
    warm = 1.0 + 0.04 * fbm(82, 70.0, 2)[..., None] * np.array([0.2, 0.0, -1.0])
    return _lin((0.83, 0.62, 0.22)) * v[..., None] * warm


def alb_verdigris():
    dents, scr, pits, brushed = _metal_common()
    m = fbm(91, 25.0, 5)
    crust = 1.0 + 0.16 * m + 0.08 * fbm(92, 3.0, 2)
    show = np.clip(smoothstep(1.2, 1.9, fbm(93, 30.0, 4)) + 0.7 * scr, 0, 1)[..., None]  # bronze shows through
    base = _lin((0.34, 0.5, 0.42)) * crust[..., None] * (1.0 + 0.06 * m[..., None] * np.array([-1.0, 0.3, 0.6]))
    br = _lin((0.5, 0.33, 0.17))
    return base * (1 - show) + br * show


def fam_cloth():
    """Neutral (white-ish) plain weave: the material colour comes from baseColorFactor."""
    T = 64  # threads per tile
    p = N / T
    fx = (_xx % p) / p
    fy = (_yy % p) / p
    ix = (_xx // p).astype(int)
    iy = (_yy // p).astype(int)
    over = (ix + iy) % 2 == 0
    warp = np.sin(np.pi * fx) ** 0.6 * (0.6 + 0.4 * np.sin(np.pi * fy))  # vertical thread, bulges mid-cell
    weft = np.sin(np.pi * fy) ** 0.6 * (0.6 + 0.4 * np.sin(np.pi * fx))
    h = np.where(over, warp, weft)
    thread = noise(101, 0.5, 40.0) * 0.5 + noise(102, 40.0, 0.5) * 0.5  # slubs along threads
    dirt = fbm(103, 60.0, 3)
    v = 0.78 + 0.16 * h + 0.03 * thread + 0.04 * dirt
    alb = np.repeat(v[..., None], 3, -1)
    height = 2.0 * h + 0.2 * thread
    rough = 1.0 - 0.04 * h + 0.03 * dirt
    ao = 0.75 + 0.25 * h
    return dict(albedo=alb, height=height, normal_strength=0.9, rough=rough, ao=ao, metal=False)


def fam_leather():
    """Neutral pebbled grain with creases; tinted per material (leather, grip, laurel)."""
    f1, f2, cv = worley(111, 40)
    pebble = smoothstep(0.0, 1.0, (f2 - f1) / 4.0)
    crease = 1.0 - smoothstep(0.0, 0.07, np.abs(fbm(112, 50.0, 4)))
    blot = fbm(113, 70.0, 3)
    v = 0.8 + 0.06 * pebble + 0.04 * (cv - 0.5) - 0.12 * crease + 0.05 * blot
    alb = np.repeat(v[..., None], 3, -1)
    height = 1.2 * pebble - 2.0 * crease
    rough = 1.0 + 0.05 * crease - 0.06 * pebble + 0.04 * blot
    ao = 1.0 - 0.25 * crease - 0.1 * (1 - pebble)
    return dict(albedo=alb, height=height, normal_strength=0.6, rough=rough, ao=ao, metal=False)


def fam_sand():
    grain = blur(rng(121).standard_normal((N, N)), 1.1)
    grain = std(grain)
    pebbles = dots(122, 400, 1.3)
    darkg = dots(123, 900, 0.7)
    ripple = np.sin(2 * math.pi * (6 * _yy + 2 * _xx) / N + 1.5 * fbm(124, 50, 2))
    v = 1.0 + 0.05 * grain + 0.15 * pebbles - 0.3 * darkg + 0.04 * ripple + 0.05 * fbm(125, 60, 3)
    alb = _lin((0.76, 0.6, 0.38)) * v[..., None]
    height = 0.6 * grain + 2.0 * pebbles + 1.5 * ripple
    rough = 1.0 + 0.02 * grain
    ao = 1.0 - 0.15 * darkg
    return dict(albedo=alb, height=height, normal_strength=0.4, rough=rough, ao=ao, metal=False)


def fam_organic():
    """Glossy wet tissue: neutral-ish mottling with darker purple veins; tinted per organ by factor."""
    mott = fbm(131, 35.0, 4)
    big = fbm(132, 90.0, 2)
    vn = np.abs(fbm(133, 28.0, 4))
    veins = 1.0 - smoothstep(0.0, 0.12, vn)
    vn2 = np.abs(fbm(134, 12.0, 3))
    capil = 1.0 - smoothstep(0.0, 0.08, vn2)
    v = 0.82 + 0.06 * mott + 0.05 * big
    rgb = np.repeat(v[..., None], 3, -1)
    vt = np.array([0.55, 0.45, 0.75])  # veins: darker, bluish-purple
    m = np.clip(0.75 * veins + 0.3 * capil, 0, 1)[..., None]
    rgb = rgb * (1 - m * (1 - vt))
    rgb = rgb * (1.0 + 0.05 * mott[..., None] * np.array([0.5, -0.5, -0.3]))
    bumps = fbm(135, 14.0, 3)
    height = 1.5 * bumps + 2.0 * big + 1.2 * veins
    wet = fbm(136, 20.0, 3)
    rough = 1.0 + 0.25 * wet - 0.1 * veins  # wet sheen breaks up
    ao = 1.0 - 0.1 * veins
    return dict(albedo=rgb, height=height, normal_strength=0.5, rough=rough, ao=ao, metal=False)


# ---------------------------------------------------------------- texture sets and material mapping

# family -> builder (shared ORM + normal); None normal_strength = no normal map
FAMILIES = {
    "stone": fam_stone,
    "marble": fam_marble,
    "wood": fam_wood,
    "metal": fam_metal,
    "cloth": fam_cloth,
    "leather": fam_leather,
    "sand": fam_sand,
    "organic": fam_organic,
}
EXTRA_ALBEDO = {
    "iron": alb_iron,
    "steel": alb_steel,
    "bronze": alb_bronze,
    "gold": alb_gold,
    "verdigris": alb_verdigris,
}
# Linear mean each albedo is pinned to: the material colour from the build scripts (None = neutral, tinted by factor).
ALBEDO_REF = {
    "stone": (0.66, 0.6, 0.5), "marble": (0.86, 0.83, 0.77), "wood": (0.42, 0.27, 0.14), "sand": (0.76, 0.6, 0.38),
    "iron": (0.28, 0.28, 0.30), "steel": (0.78, 0.79, 0.82), "bronze": (0.55, 0.37, 0.18), "gold": (0.83, 0.62, 0.22),
    "verdigris": (0.34, 0.5, 0.42), "cloth": None, "leather": None, "organic": None,
}
# ORM / normal sharing: these families reuse another family's ORM and normal maps.
ORM_FROM = {}
NORMAL_FROM = {"marble": None}

# material -> (albedo texture, orm texture, normal texture or None)
MATERIAL_TEX = {
    "stone": ("stone", "stone", "stone"),
    "marble": ("marble", "marble", None),
    "sand": ("sand", "sand", "sand"),
    "wood": ("wood", "wood", "wood"),
    "wood_wet": ("wood", "wood", "wood"),
    "iron": ("iron", "metal", "metal"),
    "steel": ("steel", "metal", "metal"),
    "aluminium": ("steel", "metal", "metal"),
    "bronze": ("bronze", "metal", "metal"),
    "gold": ("gold", "metal", "metal"),
    "brass": ("gold", "metal", "metal"),
    "trim": ("gold", "metal", "metal"),
    "verdigris": ("verdigris", "metal", "metal"),
    "cloth": ("cloth", "cloth", "cloth"),
    "crest": ("cloth", "cloth", "cloth"),
    "scutum_red": ("cloth", "cloth", "cloth"),
    "cord": ("cloth", "cloth", "cloth"),
    "wrap": ("cloth", "cloth", "cloth"),
    "leather": ("leather", "leather", "leather"),
    "grip": ("leather", "leather", "leather"),
    "laurel": ("leather", "leather", "leather"),
    "intestine": ("organic", "organic", "organic"),
    "gut_dark": ("organic", "organic", "organic"),
    "liver": ("organic", "organic", "organic"),
    "stomach": ("organic", "organic", "organic"),
    "heart": ("organic", "organic", "organic"),
    "fat": ("organic", "organic", "organic"),
    "vessel": ("organic", "organic", "organic"),
}


def save(path, arr8):
    mode = {1: "L", 3: "RGB"}[arr8.shape[2]] if arr8.ndim == 3 else "L"
    img = Image.fromarray(arr8 if arr8.ndim == 2 or arr8.shape[2] > 1 else arr8[..., 0], mode)
    img.save(path, optimize=True)


def build_all(out_dir, log=print):
    """Write every PNG; return {albedo name: linear mean RGB, '<family>_orm': mean G} measured from the written files."""
    os.makedirs(out_dir, exist_ok=True)
    means = {}

    def write_albedo(name, lin):
        # Pin the mean to the material's current colour (neutral maps: brightest channel mean 0.9) so tints stay <= 1.
        m = lin.reshape(-1, 3).mean(0)
        ref = np.array(ALBEDO_REF[name]) if ALBEDO_REF.get(name) else m * (0.9 / m.max())
        a8 = to8(lin2srgb(lin * (ref / m)[None, None, :]))
        save(os.path.join(out_dir, name + "_albedo.png"), a8)
        means[name] = tuple(float(x) for x in srgb2lin(a8 / 255.0).reshape(-1, 3).mean(0))

    for fam, fn in FAMILIES.items():
        d = fn()
        if d["albedo"] is not None:
            write_albedo(fam, d["albedo"])
        if ORM_FROM.get(fam, fam) == fam:
            g = d["rough"] / d["rough"].mean() * ORM_G_MEAN
            orm = np.stack([np.clip(d["ao"], 0, 1), np.clip(g, 0.02, 1.0),
                            np.full((N, N), 1.0 if d["metal"] else 0.0)], -1)
            o8 = to8(orm)
            save(os.path.join(out_dir, fam + "_orm.png"), o8)
            means[fam + "_orm"] = float(o8[..., 1].mean() / 255.0)
        if d["height"] is not None and NORMAL_FROM.get(fam, fam) == fam and d["normal_strength"] > 0:
            save(os.path.join(out_dir, fam + "_normal.png"), to8(normal_from_height(d["height"], d["normal_strength"])))
        log("  built family", fam)
    for name, fn in EXTRA_ALBEDO.items():
        write_albedo(name, fn())
        log("  built albedo", name)
    return means
