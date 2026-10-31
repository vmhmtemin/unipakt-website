#!/usr/bin/env python3
"""Marka rengi: logoları temaya göre boyar.

Her renkli logo iki dosyadan oluşur (brand/ klasörü):
  <ad>.base.webp  logonun renksiz kısmı (beyaz yazılar, zemin) — renkli piksellerin yeri saydam
  <ad>.mask.webp  renkli kısımların maskesi: alfa = ne kadar renkli, gri ton = gölge (koyu = gölgeli)

compose() gradyanı maskeden geçirip tabanın üstüne koyar. Aynı işlemi tarayıcıda
theme.js (canvas) yapar; derlemede tools/build_pages.py bununla _site/ içindeki
logo dosyalarını canlı temayla yeniden yazar.

Yeni bir renkli logo eklerken (renkli kısımları düz tek bir renk olmalı):
    python3 tools/brand.py split <görsel> <ad> <renkli kısmın rengi, ör. #19C7B5>
ve LOGOS listesine (aşağıda) yayın yolunu ekle.
"""
from __future__ import annotations

import colorsys
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "brand"

# ad -> sitedeki dosya (derlemede bu dosyalar temanın rengiyle yeniden yazılır)
LOGOS = {
    "unipakt-logo-bg": "unipakt-logo-bg.png",
    "unipakt-logo-bg-white": "unipakt-logo-bg-white.png",
    "og-image": "og-image.png",
    "logo-full": "hackfest-media/logo-full.webp",
    "logo-full-nostar": "hackfest-media/logo-full-nostar.webp",
    "logo-star": "hackfest-media/logo-star.webp",
    "logo-hackfest": "hackfest-media/logo-hackfest.webp",
    "logo-unipakt": "hackfest-media/logo-unipakt.webp",
    "logo-mixit": "hackfest-media/logo-mixit.webp",
    "logo-hf27": "hackfest-media/logo-hf27.webp",
}


def _hex(c: str) -> np.ndarray:
    c = c.lstrip("#")
    return np.array([int(c[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)


def split(src: Path, name: str, accent: str) -> None:
    """Düz renkli bir logoyu taban + maske olarak ayırır."""
    im = Image.open(src).convert("RGBA")
    a = np.asarray(im).astype(np.float32)
    rgb = a[..., :3] / 255
    r, g, b = _hex(accent) / 255
    h0, _, v0 = colorsys.rgb_to_hsv(r, g, b)
    hsv = np.asarray(Image.fromarray(a[..., :3].astype(np.uint8)).convert("HSV")).astype(np.float32) / 255
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    hd = np.minimum(np.abs(h - h0), 1 - np.abs(h - h0))
    w = np.clip((0.10 - hd) / 0.05, 0, 1) * np.clip((s - 0.10) / 0.20, 0, 1)
    alpha = a[..., 3] / 255
    shade = np.clip(v / max(v0, 1e-3), 0, 1)
    base = a.copy()
    base[..., 3] = alpha * (1 - w) * 255
    mask = np.zeros_like(a)
    mask[..., 0] = mask[..., 1] = mask[..., 2] = shade * 255
    mask[..., 3] = alpha * w * 255
    BRAND.mkdir(exist_ok=True)
    Image.fromarray(base.round().clip(0, 255).astype(np.uint8), "RGBA").save(BRAND / f"{name}.base.webp", "WEBP", quality=95, method=6)
    Image.fromarray(mask.round().clip(0, 255).astype(np.uint8), "RGBA").save(BRAND / f"{name}.mask.webp", "WEBP", lossless=True, method=6)


def gradient(w: int, h: int, colors: list[str], angle: float) -> np.ndarray:
    """CSS linear-gradient(angle, colors…) ile aynı geometri, w×h×3."""
    cols = colors if len(colors) > 1 else colors * 2
    a = math.radians(angle % 360)
    dx, dy = math.sin(a), -math.cos(a)
    half = (abs(w * dx) + abs(h * dy)) / 2 or 1
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = (((xx + 0.5 - w / 2) * dx + (yy + 0.5 - h / 2) * dy) / (2 * half) + 0.5).clip(0, 1)
    stops = np.array([_hex(c) for c in cols])
    pos = t * (len(cols) - 1)
    i = np.minimum(pos.astype(int), len(cols) - 2)
    f = (pos - i)[..., None]
    return stops[i] * (1 - f) + stops[i + 1] * f


def compose(name: str, colors: list[str], angle: float) -> Image.Image:
    base = np.asarray(Image.open(BRAND / f"{name}.base.webp").convert("RGBA")).astype(np.float32) / 255
    mask = np.asarray(Image.open(BRAND / f"{name}.mask.webp").convert("RGBA")).astype(np.float32) / 255
    h, w = base.shape[:2]
    layer = gradient(w, h, colors, angle) / 255 * mask[..., :1]
    la = mask[..., 3:4]
    ba = base[..., 3:4]
    out_a = la + ba * (1 - la)
    out_rgb = (layer * la + base[..., :3] * ba * (1 - la)) / np.maximum(out_a, 1e-6)
    out = np.concatenate([out_rgb, out_a], axis=-1)
    return Image.fromarray((out * 255).round().clip(0, 255).astype(np.uint8), "RGBA")


def write_logos(out_root: Path, colors: list[str], angle: float) -> int:
    n = 0
    for name, rel in LOGOS.items():
        if not (BRAND / f"{name}.base.webp").exists():
            continue
        img = compose(name, colors, angle)
        target = out_root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        if rel.endswith(".webp"):
            img.save(target, "WEBP", quality=95, method=6)
        elif name == "og-image":
            img.convert("RGB").save(target, optimize=True)
        else:
            img.save(target, optimize=True)
        n += 1
    return n


if __name__ == "__main__":
    if len(sys.argv) == 5 and sys.argv[1] == "split":
        split(Path(sys.argv[2]), sys.argv[3], sys.argv[4])
    elif len(sys.argv) >= 3 and sys.argv[1] == "render":   # render <out dir> #c1 #c2 … [açı]
        args = sys.argv[3:]
        angle = float(args.pop()) if args and not args[-1].startswith("#") else 135
        print(write_logos(Path(sys.argv[2]), args, angle), "logo yazıldı")
    else:
        sys.exit(__doc__)
