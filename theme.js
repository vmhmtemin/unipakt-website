// UniPakt — marka rengi (site, panel, giriş kontrol sayfası, 404).
//
// Renk tek yerden gelir: Supabase'deki site_theme satırı (panel › Marka rengi).
// Bu dosya <head> içinde, stil dosyasından sonra ve senkron yüklenir:
//   1. Son görülen temayı (localStorage) hemen uygular — sayfa eski renkle yanıp sönmez.
//   2. Canlı temayı okur; farklıysa uygular ve saklar.
//   3. data-tint="ad" taşıyan logo görsellerini (/brand/ad.base.webp + ad.mask.webp)
//      yeni renge boyar. Sayfadaki görseller zaten derlemede (tools/build_pages.py)
//      o anki temayla boyanmış olarak gelir; boyama yalnızca tema derlemeden sonra
//      değiştiyse yapılır.
//
// CSS tarafı yalnızca şu değişkenleri kullanır:
//   --brand-grad      gradyan (1–4 renk)
//   --brand-on-dark   koyu zeminde okunan tek renk
//   --brand-on-light  açık zeminde okunan tek renk
//   --brand-on-accent gradyanın üstündeki yazı rengi
(function () {
  'use strict';
  var KEY = 'unipakt-theme-v1';
  var API = 'https://hcgotmcbwmleeklbvawb.supabase.co/rest/v1/site_theme?id=eq.1&select=colors,angle,on_dark,on_light,on_accent,updated_at';
  var PUBLIC_KEY = 'sb_publishable_RcHJDYGkpd-01DPYG9o3HQ_8prlhUQn'; // yayınlanabilir (tarayıcı) anahtar
  var HEX = /^#[0-9A-Fa-f]{6}$/;
  var root = document.documentElement;
  var current = null;

  function valid(t) {
    return !!t && Array.isArray(t.colors) && t.colors.length >= 1 && t.colors.length <= 4 &&
      t.colors.every(function (c) { return HEX.test(c); }) &&
      HEX.test(t.on_dark) && HEX.test(t.on_light) && HEX.test(t.on_accent) &&
      typeof t.angle === 'number' && isFinite(t.angle);
  }
  function keyOf(t) { return t.colors.join(',').toUpperCase() + '|' + Math.round(t.angle); }
  function gradient(t) {
    var c = t.colors.length === 1 ? [t.colors[0], t.colors[0]] : t.colors;
    return 'linear-gradient(' + Math.round(t.angle) + 'deg, ' + c.join(', ') + ')';
  }
  function hexToRgb(h) { var n = parseInt(h.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }

  // Canvas çizimleri (paylaşım görselleri, ağ animasyonu) için: koyu zeminde okunan marka rengi.
  window.brandColor = function (alpha) {
    var h = (current && current.on_dark) || getComputedStyle(root).getPropertyValue('--brand-on-dark').trim() || '#A94B86';
    if (alpha == null) return h;
    var c = hexToRgb(h);
    return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + alpha + ')';
  };

  // ---------- Logolar ----------
  var baked = (document.querySelector('meta[name="unipakt-theme-baked"]') || {}).content || '';
  function loadImg(src) {
    return new Promise(function (ok, fail) {
      var im = new Image();
      im.decoding = 'async';
      im.onload = function () { ok(im); };
      im.onerror = fail;
      im.src = src;
    });
  }
  // CSS linear-gradient açısını görselin kutusuna uygular (aynı geometri).
  function canvasGradient(ctx, w, h, t) {
    var a = (t.angle % 360) * Math.PI / 180;
    var dx = Math.sin(a), dy = -Math.cos(a);
    var half = (Math.abs(w * dx) + Math.abs(h * dy)) / 2;
    var g = ctx.createLinearGradient(w / 2 - dx * half, h / 2 - dy * half, w / 2 + dx * half, h / 2 + dy * half);
    var c = t.colors.length === 1 ? [t.colors[0], t.colors[0]] : t.colors;
    c.forEach(function (col, i) { g.addColorStop(i / (c.length - 1), col); });
    return g;
  }
  var tinted = {};
  function tint(name, t) {
    var k = name + '|' + keyOf(t);
    if (tinted[k]) return tinted[k];
    tinted[k] = Promise.all([loadImg('/brand/' + name + '.base.webp'), loadImg('/brand/' + name + '.mask.webp')]).then(function (pair) {
      var base = pair[0], mask = pair[1], w = base.naturalWidth, h = base.naturalHeight;
      var layer = document.createElement('canvas'); layer.width = w; layer.height = h;
      var lx = layer.getContext('2d');
      lx.fillStyle = canvasGradient(lx, w, h, t); lx.fillRect(0, 0, w, h);
      lx.globalCompositeOperation = 'multiply'; lx.drawImage(mask, 0, 0, w, h);      // gölgeler
      lx.globalCompositeOperation = 'destination-in'; lx.drawImage(mask, 0, 0, w, h); // yalnızca renkli kısımlar
      var out = document.createElement('canvas'); out.width = w; out.height = h;
      var ox = out.getContext('2d');
      ox.drawImage(base, 0, 0); ox.drawImage(layer, 0, 0);
      return out.toDataURL('image/png');
    });
    return tinted[k];
  }
  function paintLogos(t) {
    var imgs = document.querySelectorAll('img[data-tint]');
    Array.prototype.forEach.call(imgs, function (img) {
      if (!img.dataset.bakedSrc) img.dataset.bakedSrc = img.getAttribute('src');
      if (keyOf(t) === baked) { if (img.getAttribute('src') !== img.dataset.bakedSrc) img.src = img.dataset.bakedSrc; return; }
      tint(img.dataset.tint, t).then(function (url) { if (current === t) img.src = url; }, function () {});
    });
  }
  // Sonradan eklenen logolar (panel ekranları, giriş kontrol sayfası) da boyansın.
  if (window.MutationObserver) {
    new MutationObserver(function (list) {
      if (!current || keyOf(current) === baked) return;
      for (var i = 0; i < list.length; i++) {
        var added = list[i].addedNodes;
        for (var j = 0; j < added.length; j++) {
          var n = added[j];
          if (n.nodeType === 1 && (n.matches('img[data-tint]') || n.querySelector('img[data-tint]'))) { paintLogos(current); return; }
        }
      }
    }).observe(root, { childList: true, subtree: true });
  }
  // Paylaşım görseli gibi canvas'a logo çizen kodlar için: güncel renkte logo adresi.
  window.unipaktLogoSrc = function (name, fallback) {
    if (!current || keyOf(current) === baked) return Promise.resolve(fallback);
    return tint(name, current).catch(function () { return fallback; });
  };

  // ---------- Uygulama ----------
  function apply(t, opts) {
    if (!valid(t)) return false;
    current = t;
    var s = root.style;
    s.setProperty('--brand-grad', gradient(t));
    s.setProperty('--brand-on-dark', t.on_dark);
    s.setProperty('--brand-on-light', t.on_light);
    s.setProperty('--brand-on-accent', t.on_accent);
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta && meta.dataset.brand !== undefined) meta.content = t.colors[0];
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function () { if (current === t) paintLogos(t); }, { once: true });
    else paintLogos(t);
    if (!(opts && opts.preview)) { try { localStorage.setItem(KEY, JSON.stringify(t)); } catch (e) {} }
    try { document.dispatchEvent(new CustomEvent('unipakt-theme', { detail: t })); } catch (e) {}
    return true;
  }
  // Panel › Marka rengi önizlemesi ve kaydı da bunu kullanır.
  window.unipaktTheme = {
    apply: apply,
    current: function () { return current; },
    gradient: gradient,
    refresh: refresh,
  };

  try { var saved = JSON.parse(localStorage.getItem(KEY) || 'null'); if (valid(saved)) apply(saved); } catch (e) {}

  function refresh() {
    return fetch(API, { headers: { apikey: PUBLIC_KEY }, cache: 'no-store' })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (rows) {
        var t = rows && rows[0];
        if (!valid(t)) return null;
        t.colors = t.colors.map(function (c) { return c.toUpperCase(); });
        if (!current || keyOf(current) !== keyOf(t) || current.on_dark !== t.on_dark || current.on_light !== t.on_light || current.on_accent !== t.on_accent) apply(t);
        else { try { localStorage.setItem(KEY, JSON.stringify(t)); } catch (e) {} }
        return t;
      })
      .catch(function () { return null; });
  }
  refresh();
})();
