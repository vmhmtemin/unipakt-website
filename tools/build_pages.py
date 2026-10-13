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
import re
import shutil
import sys
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
    "kampus": ("Kampüsünde UniPakt", "Her üniversiteden bir temsilci kulüp, kampüsler arası ortak etkinlikler ve tüm ağa ulaşan duyurular."),
    "iletisim": ("İletişim", "UniPakt'a soru, öneri ve iş birliği teklifleriniz için iletişim formu ve e-posta adresi."),
    "katil": ("Bize Katıl", "Üniversite kulübünü UniPakt ağına dahil etmek ya da şehrine geldiğimizde öncelikli olmak için başvur."),
    "kvkk": ("KVKK Aydınlatma Metni", "UniPakt'ın kişisel verileri hangi amaçla, hangi hukuki sebeple işlediği, kimlere aktardığı ve haklarınız."),
}

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

    # Serve files as they are (no Jekyll processing).
    (OUT / ".nojekyll").write_text("", encoding="utf-8")
    print(f"build_pages: {len(ROUTES)} route pages written to {OUT.relative_to(ROOT)}/")


if __name__ == "__main__":
    main()
