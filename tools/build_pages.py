#!/usr/bin/env python3
"""Build the folder GitHub Pages publishes (_site/).

The site is one page (index.html) that shows a different section for each
path: /story, /takvim, /kulupler ... GitHub Pages has no rewrites, so each of
those paths gets its own copy of index.html (_site/takvim/index.html, ...).
Each copy only differs in its <title>, description, canonical link and og:url,
so search engines and link previews see the right page.

Run locally:  python3 tools/build_pages.py && python3 -m http.server -d _site
"""
from __future__ import annotations

import base64
import hashlib
import html
import json
import re
import shutil
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "_site"
SITE = "https://unipakt.com"

# path segment -> (page title, meta description). Titles must match validRoutes and
# ROUTE_TITLES in index.html (and the route list in 404.html).
ROUTES = {
    "story": ("The Story", "UniPakt'ın hikâyesi: kulüplerin birbirinden güç aldığı bir ağ fikrinin nasıl doğduğu ve arkasındaki ekip."),
    "takvim": ("Takvim", "UniPakt ağındaki üniversite kulüplerinin ortak etkinlikleri, tek takvimde."),
    "kulupler": ("Ortak Kulüpler", "UniPakt ağına katılan İstanbul üniversite kulüpleri: yazılım, tasarım, girişimcilik, eğlence ve daha fazlası."),
    "hakkimizda": ("Hakkımızda", "UniPakt, üniversite kulüplerini ortak etkinliklerde buluşturan ve birbirlerini desteklemelerini sağlayan bir öğrenci kulüpleri ağıdır."),
    "iletisim": ("İletişim", "UniPakt'a soru, öneri ve iş birliği teklifleriniz için iletişim formu ve e-posta adresi."),
    "katil": ("Bize Katıl", "Üniversite kulübünü UniPakt ağına dahil etmek ya da şehrine geldiğimizde öncelikli olmak için başvur."),
    "etkinlik": ("Etkinlik", "UniPakt ağındaki bir üniversite kulübü etkinliğinin tarih, yer, kayıt ve bilet bilgileri."),
    "kulup": ("Kulüp", "UniPakt ağındaki bir üniversite kulübünün tanıtımı, iletişim bilgileri ve etkinlikleri."),
    "sponsorlar": ("Sponsorlar", "UniPakt ağındaki üniversite kulübü etkinliklerini destekleyen sponsorlar ve sponsorluk için iletişim adresi."),
    "hackfest27": ("HACKFEST27: MIXIT · Sponsorluk", "MIXIT sponsorluk dosyası: UniPakt'ın 6–7 Mart 2027'de İstanbul Kongre Merkezi'nde düzenlediği üniversite festivalinde markalar için kitle, alanlar ve iş birliği."),
    "mixit": ("HACKFEST27: MIXIT", "6–7 Mart 2027, İstanbul Kongre Merkezi: UniPakt'ın üniversite festivali MIXIT. Hackathon, e-spor, gastronomi ve dans yarışmaları, konuşmalar ve Büyük Final."),
    "kvkk": ("KVKK Aydınlatma Metni", "UniPakt'ın kişisel verileri hangi amaçla, hangi hukuki sebeple işlediği, kimlere aktardığı ve haklarınız."),
}

# Event share pages (/etkinlik/<id>/): a small page per published event so that link
# previews (WhatsApp, Instagram, X …) show the event's own title, date and poster.
# Visitors are sent on to the real event page (/etkinlik/?id=…).
SUPABASE = "https://hcgotmcbwmleeklbvawb.supabase.co"
PUBLIC_KEY = "sb_publishable_RcHJDYGkpd-01DPYG9o3HQ_8prlhUQn"   # publishable (browser) key
MONTHS = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
SAFE_IMG = re.compile(r"^https://[A-Za-z0-9.-]+\.supabase\.co/storage/v1/object/public/[^\s\"'<>]+$")

# Never published: source-only files.
SKIP = {".git", ".github", ".gitignore", "_site", "supabase", "tools", "README.md"}
SKIP_SUFFIXES = {".code-workspace"}


def replace_once(text: str, pattern: str, repl, label: str) -> str:
    new, count = re.subn(pattern, repl, text, count=1)
    if count != 1:
        sys.exit(f"build_pages: could not find {label} in index.html")
    return new


def page_for(index: str, route: str, title: str, description: str) -> str:
    url = f"{SITE}/{route}/"
    full_title = html.escape(f"{title} — UniPakt", quote=True)
    desc = html.escape(description, quote=False).replace('"', "&quot;")
    text = replace_once(index, r"<title>[^<]*</title>", f"<title>{full_title}</title>", "<title>")
    text = replace_once(text, r'(<link rel="canonical" href=")[^"]*(")', rf"\g<1>{url}\g<2>", "canonical link")
    text = replace_once(text, r'(<meta property="og:url" content=")[^"]*(")', rf"\g<1>{url}\g<2>", "og:url")
    text = replace_once(text, r'(<meta property="og:title" content=")[^"]*(")', rf"\g<1>{full_title}\g<2>", "og:title")
    text = replace_once(text, r'(<meta name="twitter:title" content=")[^"]*(")', rf"\g<1>{full_title}\g<2>", "twitter:title")
    text = replace_once(text, r'(<meta name="description" content=")[^"]*(")', lambda m: m.group(1) + desc + m.group(2), "meta description")
    text = replace_once(text, r'(<meta property="og:description" content=")[^"]*(")', lambda m: m.group(1) + desc + m.group(2), "og:description")
    text = replace_once(text, r'(<meta name="twitter:description" content=")[^"]*(")', lambda m: m.group(1) + desc + m.group(2), "twitter:description")
    return text


# Marka rengi (panel › Marka rengi): site_theme satırı. Okunamazsa repodaki varsayılan kalır.
DEFAULT_THEME = {"colors": ["#8F244D", "#A94B86"], "angle": 135, "on_dark": "#A94B86", "on_light": "#8F244D", "on_accent": "#FFFFFF"}
HEX_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")


def fetch_theme() -> dict:
    try:
        req = urllib.request.Request(f"{SUPABASE}/rest/v1/site_theme?id=eq.1&select=colors,angle,on_dark,on_light,on_accent",
                                     headers={"apikey": PUBLIC_KEY})
        with urllib.request.urlopen(req, timeout=20) as res:
            row = (json.load(res) or [None])[0]
        ok = (row and 1 <= len(row.get("colors") or []) <= 4 and all(HEX_RE.match(c) for c in row["colors"])
              and all(HEX_RE.match(str(row.get(k) or "")) for k in ("on_dark", "on_light", "on_accent")))
        if ok:
            row["colors"] = [c.upper() for c in row["colors"]]
            row["angle"] = int(row.get("angle") or 135) % 360
            return row
    except Exception as error:
        print(f"build_pages: theme not read ({error}); using the default")
    return dict(DEFAULT_THEME)


def css_gradient(t: dict) -> str:
    cols = t["colors"] if len(t["colors"]) > 1 else t["colors"] * 2
    return f"linear-gradient({t['angle']}deg, {', '.join(cols)})"


def apply_theme(t: dict) -> int:
    """Bakes the theme into every published page (CSS variables + meta) and repaints the logos."""
    baked = ",".join(t["colors"]) + f"|{t['angle']}"
    subs = [
        (r"--brand-grad: linear-gradient\([^;]*\);", f"--brand-grad: {css_gradient(t)};"),
        (r"--brand-on-dark: #[0-9A-Fa-f]{6};", f"--brand-on-dark: {t['on_dark']};"),
        (r"--brand-on-light: #[0-9A-Fa-f]{6};", f"--brand-on-light: {t['on_light']};"),
        (r"--brand-on-accent: #[0-9A-Fa-f]{6};", f"--brand-on-accent: {t['on_accent']};"),
        (r'(<meta name="unipakt-theme-baked" content=")[^"]*(")', rf"\g<1>{baked}\g<2>"),
    ]
    pages = 0
    for page in OUT.rglob("*.html"):
        text = page.read_text(encoding="utf-8")
        if "unipakt-theme-baked" not in text:
            continue
        for pattern, repl in subs:
            text = re.sub(pattern, repl, text)
        page.write_text(text, encoding="utf-8")
        pages += 1
    try:
        sys.path.insert(0, str(ROOT / "tools"))
        import brand  # needs Pillow + numpy
        logos = brand.write_logos(OUT, t["colors"], t["angle"])
    except ImportError as error:
        print(f"build_pages: logos not repainted ({error})")
        logos = 0
    print(f"build_pages: theme {baked} baked into {pages} pages and {logos} logos")
    return pages


def fetch_events() -> list[dict]:
    req = urllib.request.Request(f"{SUPABASE}/rest/v1/rpc/public_events", data=b"{}", method="POST",
                                 headers={"apikey": PUBLIC_KEY, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as res:
        rows = json.load(res)
    return rows if isinstance(rows, list) else []


def share_page(e: dict, link_color: str = "#A94B86") -> str | None:
    eid = str(e.get("id") or "").lower()
    title = " ".join(str(e.get("title") or "").split())[:140]
    if not UUID_RE.match(eid) or not title:
        return None
    occ = e.get("occurrences") or [{"date": e.get("event_date"), "time": e.get("event_time")}]
    first = occ[0] if occ else {}
    day = ""
    try:
        y, m, d = (int(x) for x in str(first.get("date") or e.get("event_date"))[:10].split("-"))
        day = f"{d} {MONTHS[m - 1]} {y}"
    except (ValueError, IndexError):
        pass
    time = str(first.get("time") or "")[:5]
    where = ", ".join(x for x in [str(e.get("place") or "").strip(), str(e.get("city") or "").strip()] if x)
    who = str(e.get("organizer") or "").strip()
    desc = " · ".join(x for x in [day + (f" {time}" if time else ""), where] if x)
    if who:
        desc = f"{desc} — {who}" if desc else who
    image = next((u for u in [e.get("poster_url"), e.get("banner_url")] if u and SAFE_IMG.match(str(u))), f"{SITE}/og-image.png")
    url = f"{SITE}/etkinlik/{eid}/"
    target = f"/etkinlik/?id={eid}"
    script = f"location.replace({json.dumps(target)} + location.hash);"
    digest = base64.b64encode(hashlib.sha256(script.encode("utf-8")).digest()).decode()
    q = lambda v: html.escape(v, quote=True)
    return f"""<!doctype html>
<html lang="tr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'sha256-{digest}'; style-src 'unsafe-inline'; img-src https:; base-uri 'none'">
<title>{q(title)} — UniPakt</title>
<meta name="description" content="{q(desc)}">
<link rel="canonical" href="{q(url)}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="UniPakt">
<meta property="og:locale" content="tr_TR">
<meta property="og:url" content="{q(url)}">
<meta property="og:title" content="{q(title)}">
<meta property="og:description" content="{q(desc)}">
<meta property="og:image" content="{q(image)}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{q(title)}">
<meta name="twitter:description" content="{q(desc)}">
<meta name="twitter:image" content="{q(image)}">
<script>{script}</script>
<style>body{{margin:0;min-height:100vh;display:grid;place-items:center;background:#0C0C0D;color:#F2F1EE;font:16px/1.5 system-ui,sans-serif;text-align:center;padding:24px}}a{{color:{link_color}}}</style>
</head>
<body><p><strong>{q(title)}</strong><br>{q(desc)}<br><br><a href="{q(target)}">Etkinlik sayfasını aç →</a></p></body>
</html>
"""


def write_share_pages(theme: dict) -> int:
    try:
        events = fetch_events()
    except Exception as error:  # the site still builds; old links fall back through 404.html
        print(f"build_pages: event share pages skipped ({error})")
        return 0
    count = 0
    for e in events:
        page = share_page(e, theme["on_dark"])
        if not page:
            continue
        folder = OUT / "etkinlik" / str(e["id"]).lower()
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "index.html").write_text(page, encoding="utf-8")
        count += 1
    return count


def check_404_csp() -> None:
    """404.html allows exactly its own inline script by hash; fail if they drifted apart."""
    page = (ROOT / "404.html").read_text(encoding="utf-8")
    script = re.search(r"<script>(.*?)</script>", page, re.S)
    if not script:
        return
    digest = base64.b64encode(hashlib.sha256(script.group(1).encode("utf-8")).digest()).decode()
    if f"'sha256-{digest}'" not in page:
        sys.exit(f"build_pages: 404.html script changed; set script-src to 'sha256-{digest}' in its CSP")


def main() -> None:
    check_404_csp()
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir()

    for item in ROOT.iterdir():
        if item.name in SKIP or item.suffix in SKIP_SUFFIXES:
            continue
        target = OUT / item.name
        if item.is_dir():
            shutil.copytree(item, target)
        else:
            shutil.copy2(item, target)

    index = (ROOT / "index.html").read_text(encoding="utf-8")
    for route, (title, description) in ROUTES.items():
        if (OUT / route).exists():
            sys.exit(f"build_pages: {route}/ already exists in the repo")
        (OUT / route).mkdir()
        (OUT / route / "index.html").write_text(page_for(index, route, title, description), encoding="utf-8")

    theme = fetch_theme()
    shares = write_share_pages(theme)
    apply_theme(theme)

    # Serve files as they are (no Jekyll processing).
    (OUT / ".nojekyll").write_text("", encoding="utf-8")
    print(f"build_pages: {len(ROUTES)} route pages and {shares} event share pages written to {OUT.relative_to(ROOT)}/")


if __name__ == "__main__":
    main()
