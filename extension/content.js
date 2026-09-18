/**
 * Коробка — контент-скрипт.
 *
 * Перехватывает перетаскивание картинок прямо на странице сайта:
 *  - пользователь тянет <img> → появляется баннер «Отпустите — сохраню в Коробку»;
 *  - отпускание кнопки мыши в любом месте страницы → картинка уходит
 *    в приложение (через фоновый сервис-воркер);
 *  - показывает всплывающее подтверждение (успех/ошибка).
 *
 * Умеет вытаскивать настоящий URL картинки: currentSrc/src, srcset,
 * background-image, ленивые data-src; blob:-картинки конвертирует в base64;
 * для Pinterest добавляет вариант ссылки в полном размере (/originals/).
 */

'use strict';

(function () {
  // Не работаем во встроенных фреймах и не запускаемся дважды.
  if (window.__korobkaContentLoaded) return;
  window.__korobkaContentLoaded = true;

  let dragImage = null;      // {resolve(): Promise<{image, label}>}
  let bannerEl = null;

  // ───────────────────────── БАННЕР ПРИ ПЕРЕТАСКИВАНИИ ─────────────────────────

  function ensureBanner() {
    if (bannerEl) return bannerEl;
    bannerEl = document.createElement('div');
    bannerEl.className = 'korobka-drag-banner';
    bannerEl.textContent = 'Отпустите картинку в любом месте — она будет сохранена в Коробку';
    (document.documentElement || document.body).appendChild(bannerEl);
    return bannerEl;
  }

  function showBanner() {
    const b = ensureBanner();
    b.classList.add('korobka-drag-banner--visible');
  }

  function hideBanner() {
    if (bannerEl) bannerEl.classList.remove('korobka-drag-banner--visible');
  }

  // ───────────────────────── ВСПЛЫВАЮЩЕЕ ПОДТВЕРЖДЕНИЕ ─────────────────────────

  function showToast(message, kind) {
    try {
      const toast = document.createElement('div');
      toast.className = `korobka-toast korobka-toast--${kind === 'error' ? 'error' : 'ok'}`;
      toast.textContent = message;
      (document.documentElement || document.body).appendChild(toast);
      setTimeout(() => toast.classList.add('korobka-toast--visible'), 10);
      setTimeout(() => {
        toast.classList.remove('korobka-toast--visible');
        setTimeout(() => toast.remove(), 400);
      }, 3800);
    } catch (e) { /* DOM может быть недоступен — игнорируем */ }
  }

  // ───────────────────────── ПОИСК НАСТОЯЩЕЙ КАРТИНКИ ─────────────────────────

  /** Самый большой кандидат из srcset/атрибутивных вариантов. */
  function largestFromSrcset(srcset) {
    let best = null;
    let bestW = -1;
    for (const part of String(srcset || '').split(',')) {
      const chunk = part.trim();
      if (!chunk) continue;
      const [url, w] = chunk.split(/\s+/);
      const width = w && w.endsWith('w') ? parseInt(w, 10) || 0 : 0;
      if (width >= bestW) { best = url; bestW = width; }
    }
    return best;
  }

  function proxied(el) {
    // Некоторые сайты кладут настоящий адрес в атрибуты ленивой загрузки.
    const attrs = ['data-src', 'data-original', 'data-lazy-src', 'data-ll-src', 'data-real-src'];
    for (const a of attrs) {
      const v = el.getAttribute && el.getAttribute(a);
      if (v && v.trim()) return v.trim();
    }
    return '';
  }

  function urlFromElement(el) {
    if (!el) return '';

    if (el.tagName === 'IMG') {
      return el.currentSrc || el.src || proxied(el) || largestFromSrcset(el.getAttribute('srcset')) || '';
    }
    if (el.tagName === 'PICTURE') {
      const img = el.querySelector('img');
      return urlFromElement(img);
    }
    if (el.tagName === 'VIDEO' || el.tagName === 'SOURCE') {
      return el.poster || el.src || '';
    }
    // Картинка фоном (div со стилем background-image).
    const style = window.getComputedStyle(el);
    const bg = style.backgroundImage || '';
    const m = bg.match(/url\(["']?(.+?)["']?\)/);
    if (m) return m[1];
    const inner = el.querySelector && el.querySelector('img');
    if (inner) return urlFromElement(inner);
    return '';
  }

  /** URL из HTML-фрагмента, который браузер кладёт в dataTransfer при dragstart. */
  function urlFromDragHtml(html) {
    if (!html) return '';
    try {
      const doc = new DOMParser().parseFromString(html, 'text/html');
      return urlFromElement(doc.querySelector('img')) || '';
    } catch (e) {
      return '';
    }
  }

  /** blob:/data: — приложение само такое скачать не может, конвертируем здесь. */
  async function toBase64Image(rawUrl, hintMime) {
    if (rawUrl.startsWith('data:')) {
      const semi = rawUrl.indexOf(';');
      const mime = semi > 5 ? rawUrl.slice(5, semi) : (hintMime || 'image/png');
      return { base64: rawUrl, mime, filename: '' };
    }
    const resp = await fetch(rawUrl); // blob: — это тот же origin страницы
    const blob = await resp.blob();
    if (!blob.type.startsWith('image/')) {
      throw new Error('Это не изображение: ' + blob.type);
    }
    const buf = new Uint8Array(await blob.arrayBuffer());
    // Крупные файлы конвертируем по частям (лимит на аргументы функции).
    let binary = '';
    const CHUNK = 0x8000;
    for (let i = 0; i < buf.length; i += CHUNK) {
      binary += String.fromCharCode.apply(null, buf.subarray(i, i + CHUNK));
    }
    const base64 = 'data:' + blob.type + ';base64,' + btoa(binary);
    const ext = (blob.type.split('/')[1] || 'png').replace('jpeg', 'jpg').replace('+xml', '');
    return { base64, mime: blob.type, filename: `korobka_${Date.now()}.${ext}` };
  }

  /**
   * Собирает сохраняемую картинку по «следу» перетаскивания.
   * Возвращает {image, label} или null, если картинки не было.
   */
  async function resolveDraggedImage(dataTransfer, startEl) {
    let url = '';
    let label = '';

    // 1) Сначала элемент, с которого начали перетаскивание.
    const start = startEl && startEl.closest ? startEl.closest('img, picture, [style*="background"]') : null;
    if (start) {
      url = urlFromElement(start);
      if (url) label = start.tagName.toLowerCase();
    }

    // 2) HTML-представление из dataTransfer (надёжнее всего — это то,
    //    что браузер сам считает перетаскиваемой картинкой).
    if (!url && dataTransfer) {
      let html = '';
      try { html = dataTransfer.getData('text/html'); } catch (e) { /* защищено */ }
      url = urlFromDragHtml(html) || url;
    }

    // 3) Картинка под курсором в момент броска.
    if (!url && dataTransfer) {
      let uri = '';
      try { uri = dataTransfer.getData('text/uri-list') || dataTransfer.getData('text/plain'); } catch (e) {}
      if (uri && /^https?:\/\//i.test(uri.trim())) url = uri.trim();
    }

    if (!url) return null;

    let image;
    if (url.startsWith('blob:') || url.startsWith('data:')) {
      try {
        image = await toBase64Image(url);
      } catch (e) {
        // Не получилось прочитать blob — пробуем как обычный URL (вдруг прокси).
        if (!/^https?:/i.test(url)) throw e;
        image = { url };
      }
    } else if (/^https?:/i.test(url)) {
      image = { url, filename: filenameFromUrl(url) };
    } else {
      return null; // chrome://, javascript: и прочее не сохраняем
    }
    return { image, label };
  }

  function filenameFromUrl(u) {
    try {
      const p = new URL(u).pathname.split('/').pop();
      return p && /\.[a-z0-9]{2,5}$/i.test(p) ? decodeURIComponent(p) : '';
    } catch (e) { return ''; }
  }

  // ───────────────────────── ПЕРЕТАСКИВАНИЕ ─────────────────────────

  document.addEventListener(
    'dragstart',
    (e) => {
      const t = e.target;
      const isImg = t && (t.tagName === 'IMG' || (t.closest && t.closest('img, picture')));
      const styled = t && t.tagName !== 'IMG' && t.tagName !== 'PICTURE' && t.closest && t.closest('[style*="background"]');
      if (!isImg && !styled) return; // тексты и ссылки не перехватываем

      dragImage = { startEl: t, startedAt: Date.now() };
      showBanner();
    },
    true,
  );

  document.addEventListener(
    'dragover',
    (e) => {
      if (!dragImage) return;
      // Разрешаем бросок в любом месте страницы.
      e.preventDefault();
      e.stopPropagation();
      if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
    },
    true,
  );

  document.addEventListener(
    'drop',
    (e) => {
      if (!dragImage) return;
      e.preventDefault();
      e.stopPropagation();
      const ctx = dragImage;
      dragImage = null;
      hideBanner();
      handleDrop(e.dataTransfer, ctx).catch((err) => {
        console.warn('[Коробка]', err);
        showToast('Ошибка: ' + (err.message || err), 'error');
      });
    },
    true,
  );

  document.addEventListener(
    'dragend',
    () => {
      // Пользователь бросил картинку вне окна браузера или отменил перетаскивание.
      dragImage = null;
      hideBanner();
    },
    true,
  );

  async function handleDrop(dataTransfer, ctx) {
    let resolved = null;
    try {
      resolved = await resolveDraggedImage(dataTransfer, ctx.startEl);
    } catch (e) {
      showToast('Не удалось прочитать картинку: ' + e.message, 'error');
      return;
    }
    if (!resolved) {
      showToast('Это не похоже на картинку — в Коробку нечего сохранять', 'error');
      return;
    }

    let response;
    try {
      response = await chrome.runtime.sendMessage({
        type: 'saveImage',
        image: resolved.image,
      });
    } catch (e) {
      showToast('Расширение недоступно: ' + (e.message || e), 'error');
      return;
    }

    if (response && response.ok) {
      showToast(
        response.target === 'hotfolder'
          ? 'Приложение закрыто — картинка сохранена в «Загрузки/Коробка»'
          : 'Сохранено в Коробку ✓',
        'ok',
      );
    } else {
      showToast('Не сохранено: ' + ((response && response.error) || 'неизвестная ошибка'), 'error');
    }
  }

  // ──────────────── НАСТРОЙКИ: уважаем выключенный оверлей ────────────────

  try {
    chrome.storage.local.get({ overlayEnabled: true, saveToast: true }, (cfg) => {
      if (cfg.overlayEnabled === false) {
        // Баннер отключён — перетаскивание по-прежнему работает, но без подсказки.
        showBanner = () => {};
        hideBanner = () => {};
      }
      if (cfg.saveToast === false) {
        showToast = function () {};
      }
    });
    chrome.storage.onChanged.addListener((changes, area) => {
      if (area !== 'local') return;
      if (changes.overlayEnabled && changes.overlayEnabled.newValue === false) {
        showBanner = () => {};
        hideBanner = () => {};
      }
      if (changes.saveToast && changes.saveToast.newValue === false) {
        showToast = function () {};
      }
    });
  } catch (e) { /* storage может быть недоступен — работает с подсказками */ }
})();
