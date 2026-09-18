/**
 * Коробка — контент-скрипт.
 *
 * Что нового в v0.5.0 (объединение v0.4 + v4.1.0):
 *  - окно выбора папки теперь встраивается прямо в страницу и выглядит
 *    как в расширении v4.1.0: слева зона «Перетащите файлы сюда», справа
 *    папки приложения (автосинхронизация каждые 3 с), внизу кнопка
 *    «Создать или выбрать папку». Дизайн окна не менялся;
 *  - настройка «Спрашивать папку для сохранения» хранится глобально
 *    (chrome.storage.local): действует на всех сайтах, не сбрасывается
 *    при переходе на новую страницу, после её перезагрузки и после
 *    перезапуска браузера. Пока включена — каждое сохранение сначала
 *    открывает окно с папками, и картинка уходит в выбранную там папку;
 *  - файлы из Проводника по-прежнему принимаются отдельным окном;
 *  - прямое перетаскивание картинки по странице сохраняет её как в v0.4.
 */

'use strict';

(function () {
  // Не работаем во встроенных фреймах и не запускаемся дважды.
  if (window.__korobkaContentLoaded) return;
  window.__korobkaContentLoaded = true;

  // ───────────────────────── НАСТРОЙКИ ─────────────────────────

  const CFG_DEFAULTS = {
    overlayEnabled: true,  // баннер при перетаскивании
    saveToast: true,       // всплывающее подтверждение
    askFolder: false,      // спрашивать папку перед каждым сохранением
    dragWindow: true,      // окно с папками при перетаскивании
  };
  let cfg = { ...CFG_DEFAULTS };

  function refreshCfg() {
    return new Promise((resolve) => {
      try {
        chrome.storage.local.get(CFG_DEFAULTS, (stored) => {
          cfg = { ...CFG_DEFAULTS, ...(stored || {}) };
          resolve(cfg);
        });
      } catch (e) {
        resolve(cfg);
      }
    });
  }

  // Настройка меняется в одном месте — применяется сразу на всех страницах.
  try {
    chrome.storage.onChanged.addListener((changes, area) => {
      if (area !== 'local') return;
      for (const key of Object.keys(CFG_DEFAULTS)) {
        if (changes[key]) cfg[key] = changes[key].newValue;
      }
    });
  } catch (e) { /* нет доступа к storage — работаем с дефолтами */ }

  function sendMessage(msg) {
    return new Promise((resolve) => {
      try {
        chrome.runtime.sendMessage(msg, (res) => {
          if (chrome.runtime.lastError) {
            resolve({ ok: false, error: chrome.runtime.lastError.message });
          } else {
            resolve(res || { ok: false, error: 'нет ответа' });
          }
        });
      } catch (e) {
        resolve({ ok: false, error: e.message });
      }
    });
  }

  let dragImage = null;      // {startEl, startedAt} — перетаскивание картинки по странице
  let bannerEl = null;
  let osDragSent = false;    // открыт ли запрос окна для файлов из Проводника

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
    if (cfg.overlayEnabled === false) return; // подсказка отключена в настройках
    const b = ensureBanner();
    b.classList.add('korobka-drag-banner--visible');
  }

  function hideBanner() {
    if (bannerEl) bannerEl.classList.remove('korobka-drag-banner--visible');
  }

  // ───────────────────────── ВСПЛЫВАЮЩЕЕ ПОДТВЕРЖДЕНИЕ ─────────────────────────

  function showToast(message, kind) {
    if (cfg.saveToast === false) return; // подтверждения отключены в настройках
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

  /** Файл из Проводника → data URL (для броска в окно выбора папки). */
  function fileToDataUrl(file) {
    return new Promise((resolve, reject) => {
      const r = new FileReader();
      r.onload = () => resolve({ base64: String(r.result), mime: file.type || '', filename: file.name || '' });
      r.onerror = () => reject(new Error('не удалось прочитать файл'));
      r.readAsDataURL(file);
    });
  }

  function filenameFromUrl(u) {
    try {
      const p = new URL(u).pathname.split('/').pop();
      return p && /\.[a-z0-9]{2,5}$/i.test(p) ? decodeURIComponent(p) : '';
    } catch (e) { return ''; }
  }

  /**
   * Собирает сохраняемую картинку по dataTransfer броска.
   * Порядок: файлы из Проводника → элемент, с которого тянули →
   * HTML-представление → ссылка/текст.
   * Возвращает {image, label} или null, если картинки не было.
   */
  async function resolveFromDataTransfer(dataTransfer, startEl) {
    // 0) Реальные файлы (из Проводника или когда браузер отдаёт картинку файлом).
    if (dataTransfer && dataTransfer.files && dataTransfer.files.length > 0) {
      const file = dataTransfer.files[0];
      if ((file.type && file.type.startsWith('image/')) ||
          /\.(png|jpe?g|webp|gif|bmp|tiff|svg|ico)$/i.test(file.name || '')) {
        const data = await fileToDataUrl(file);
        return { image: data, label: file.name || 'файл' };
      }
      return null;
    }

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

  // ───────────────────────── ОКНО ВЫБОРА ПАПКИ ─────────────────────────
  // Встроено в страницу (shadow DOM), дизайн — как в расширении v4.1.0:
  // слева зона броска, справа папки приложения, внизу «Создать или выбрать папку».

  const picker = (function () {
    const W = 620;
    const H = 330;

    let host = null;
    let els = null;
    let open = false;
    let askMode = false;
    let mode = 'idle';          // idle | pending | saving | saved
    let pending = null;         // {image, label, thumbUrl}
    let selectedFolderId = null;
    let folders = [];
    let foldersKey = '';
    let connected = false;
    let pollTimer = null;
    let autoCloseTimer = null;

    const CSS = `
      * { box-sizing: border-box; margin: 0; padding: 0; }
      [hidden] { display: none !important; }
      .kcard {
        position: absolute;
        width: ${W}px;
        height: ${H}px;
        max-width: calc(100vw - 16px);
        max-height: calc(100vh - 16px);
        display: flex;
        flex-direction: column;
        background: #fff;
        border: 1px solid #ececec;
        border-radius: 14px;
        box-shadow: 0 18px 50px rgba(0,0,0,.22), 0 4px 14px rgba(0,0,0,.10);
        font: 14px/1.45 -apple-system, 'Segoe UI', Roboto, Arial, sans-serif;
        color: #1f2937;
        overflow: hidden;
        pointer-events: auto;
      }
      .kclose {
        position: absolute; top: 8px; right: 10px; z-index: 3;
        width: 26px; height: 26px;
        border: none; border-radius: 8px;
        background: transparent; color: #9aa3ad;
        font-size: 13px; line-height: 1; cursor: pointer;
        opacity: 0; transition: opacity .15s ease;
        pointer-events: none; /* невидимая кнопка не должна ловить клики */
      }
      .kcard:hover .kclose { opacity: 1; pointer-events: auto; }
      .kclose:hover { background: #f3f4f6; color: #374151; }
      .kbody { flex: 1; display: flex; min-height: 0; }
      .kdrop {
        flex: 1.12;
        margin: 14px 8px 14px 14px;
        border: 2px dashed #dcdfe4;
        border-radius: 10px;
        background: #f7f8fa;
        display: flex; flex-direction: column;
        align-items: center; justify-content: center;
        gap: 7px; padding: 12px; text-align: center;
        min-width: 0;
        transition: border-color .15s ease, background .15s ease;
      }
      .kdrop--over { border-color: #f59e0b; background: #fffbeb; }
      .kdrop-icon { font-size: 20px; color: #c3c9d1; }
      .kdrop-label { color: #9aa0a6; font-size: 14px; }
      .kdrop--over .kdrop-label { color: #b45309; }
      .kthumb {
        max-width: 72%; max-height: 92px;
        border-radius: 8px;
        box-shadow: 0 2px 8px rgba(0,0,0,.14);
        object-fit: contain;
        background: #fff;
      }
      .kpending-name {
        color: #6b7280; font-size: 12.5px; max-width: 88%;
        overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
      }
      .kpending-hint { color: #b45309; font-size: 12.5px; }
      .kstatus { min-height: 18px; font-size: 12.5px; color: #6b7280; max-width: 92%;
                 overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .kstatus--ok { color: #16a34a; }
      .kstatus--err { color: #dc2626; }
      .kstatus--busy { color: #d97706; }
      .kfolders {
        flex: 1;
        display: flex; flex-direction: column; min-width: 0;
        margin: 0 14px 0 8px;
        border-left: 1px solid #ececec;
      }
      .klist { flex: 1; overflow-y: auto; padding: 10px 4px; }
      .kempty {
        height: 100%; min-height: 120px;
        display: flex; align-items: center; justify-content: center;
        color: #9aa0a6; font-size: 13px; text-align: center; padding: 0 10px;
      }
      .kitem {
        display: flex; align-items: center; gap: 8px;
        padding: 7px 10px; margin: 0 4px;
        border-radius: 8px; cursor: pointer; min-width: 0;
      }
      .kitem:hover { background: #f6f7f8; }
      .kitem--sel { background: #fef3c7; }
      .kradio {
        width: 14px; height: 14px; flex: none;
        border: 2px solid #cbd5e1; border-radius: 50%; background: #fff;
      }
      .kitem--sel .kradio {
        border-color: #d97706;
        background: radial-gradient(circle, #d97706 0 45%, #fff 50%);
      }
      .kcolor { width: 9px; height: 9px; border-radius: 50%; flex: none; }
      .kname { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .kbar {
        flex: none; height: 52px;
        border-top: 1px solid #ececec;
        display: flex; align-items: stretch;
      }
      .kbar-btn {
        flex: 1; border: none; background: transparent;
        font: inherit; font-size: 14.5px; color: #374151; cursor: pointer;
      }
      .kbar-btn:hover { background: #fafafa; }
      .kcreate { flex: 1; display: flex; align-items: center; gap: 8px; padding: 0 12px; }
      .kinput {
        flex: 1; min-width: 0; padding: 8px 10px;
        border: 1px solid #e2e5e9; border-radius: 8px;
        font: inherit; font-size: 13px;
      }
      .kinput:focus { outline: none; border-color: #f59e0b; box-shadow: 0 0 0 2px rgba(245,158,11,.25); }
      .kbtn-create {
        border: none; border-radius: 8px;
        background: #f59e0b; color: #fff;
        font: 600 13px/1 inherit; font-family: inherit;
        padding: 9px 14px; cursor: pointer;
      }
      .kbtn-create:hover { background: #d97706; }
      .kbtn-create:disabled { opacity: .55; cursor: default; }
      .kbtn-cancel {
        border: none; background: transparent; color: #9aa3ad;
        font-size: 13px; cursor: pointer; padding: 6px;
      }
      .kbtn-cancel:hover { color: #374151; }
    `;

    const MARKUP = `
      <button class="kclose" title="Закрыть">✕</button>
      <div class="kbody">
        <div class="kdrop">
          <div class="khint">
            <div class="kdrop-icon">⬇</div>
            <div class="kdrop-label">Перетащите файлы сюда</div>
          </div>
          <img class="kthumb" hidden alt="" referrerpolicy="no-referrer" />
          <div class="kpending-name" hidden></div>
          <div class="kpending-hint" hidden>Выберите папку справа — картинка сохранится в неё</div>
          <div class="kstatus"></div>
        </div>
        <div class="kfolders">
          <div class="klist"></div>
        </div>
      </div>
      <div class="kbar">
        <button class="kbar-btn">Создать или выбрать папку</button>
        <div class="kcreate" hidden>
          <input class="kinput" type="text" placeholder="Новая папка…" maxlength="100" />
          <button class="kbtn-create">Создать</button>
          <button class="kbtn-cancel" title="Отмена">✕</button>
        </div>
      </div>
    `;

    function ensureBuilt() {
      if (host) return;
      host = document.createElement('div');
      host.style.cssText =
        'all:unset; position:fixed; inset:0 auto auto 0; width:100%; height:100%;' +
        'pointer-events:none; z-index:2147483647; display:none;';
      const root = host.attachShadow({ mode: 'closed' });
      const style = document.createElement('style');
      style.textContent = CSS;
      root.appendChild(style);
      const card = document.createElement('div');
      card.className = 'kcard';
      card.innerHTML = MARKUP;
      root.appendChild(card);

      els = {
        card,
        close: card.querySelector('.kclose'),
        drop: card.querySelector('.kdrop'),
        hint: card.querySelector('.khint'),
        thumb: card.querySelector('.kthumb'),
        pendingName: card.querySelector('.kpending-name'),
        pendingHint: card.querySelector('.kpending-hint'),
        status: card.querySelector('.kstatus'),
        list: card.querySelector('.klist'),
        barBtn: card.querySelector('.kbar-btn'),
        create: card.querySelector('.kcreate'),
        input: card.querySelector('.kinput'),
        createBtn: card.querySelector('.kbtn-create'),
        cancelBtn: card.querySelector('.kbtn-cancel'),
      };

      // Стили наведения на зону броска (сам бросок обрабатывается на document).
      els.drop.addEventListener('dragover', (e) => {
        e.preventDefault();
        if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
        els.drop.classList.add('kdrop--over');
      });
      els.drop.addEventListener('dragleave', () => {
        els.drop.classList.remove('kdrop--over');
      });

      els.close.addEventListener('click', () => hide());
      els.barBtn.addEventListener('click', () => {
        els.barBtn.hidden = true;
        els.create.hidden = false;
        els.input.focus();
      });
      els.cancelBtn.addEventListener('click', () => {
        els.create.hidden = true;
        els.barBtn.hidden = false;
        els.input.value = '';
      });
      els.createBtn.addEventListener('click', createFolder);
      els.input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') createFolder();
        if (e.key === 'Escape') { els.cancelBtn.click(); }
      });

      // Клик мимо окна — закрыть (как в v4.1.0).
      document.addEventListener('mousedown', (e) => {
        if (open && !host.contains(e.target)) hide();
      }, true);
      // Escape — закрыть.
      document.addEventListener('keydown', (e) => {
        if (open && e.key === 'Escape' && !els.create.hidden) {
          els.cancelBtn.click();
          return;
        }
        if (open && e.key === 'Escape') hide();
      }, true);
    }

    function esc(s) {
      const d = document.createElement('div');
      d.textContent = String(s);
      return d.innerHTML;
    }

    function depthOf(folder, byId, seen = new Set()) {
      let depth = 0;
      let cur = folder;
      while (cur && cur.parentId != null && !seen.has(cur.parentId)) {
        seen.add(cur.parentId);
        cur = byId.get(cur.parentId);
        depth += 1;
        if (depth > 10) break;
      }
      return depth;
    }

    function setStatus(text, kind) {
      els.status.textContent = text || '';
      els.status.className = 'kstatus' + (kind ? ` kstatus--${kind}` : '');
    }

    function render() {
      els.list.innerHTML = '';

      if (!connected) {
        els.list.innerHTML = '<div class="kempty">Нет связи с приложением.<br/>Запустите «Коробку».</div>';
        return;
      }
      if (folders.length === 0) {
        els.list.innerHTML = '<div class="kempty">Нет папок</div>';
        return;
      }

      const root = document.createElement('div');
      root.className = 'kitem' + (selectedFolderId === null ? ' kitem--sel' : '');
      root.innerHTML =
        '<span class="kradio"></span><span>🗃️</span>' +
        '<span class="kname">Все картинки (корень)</span>';
      root.addEventListener('click', () => onFolderClick(null));
      els.list.appendChild(root);

      const byId = new Map(folders.map((f) => [f.id, f]));
      for (const f of folders) {
        const depth = depthOf(f, byId);
        const item = document.createElement('div');
        item.className = 'kitem' + (String(selectedFolderId) === String(f.id) ? ' kitem--sel' : '');
        item.style.paddingLeft = `${10 + depth * 14}px`;
        const color = f.color
          ? `<span class="kcolor" style="background:${esc(f.color)}"></span>`
          : '';
        item.innerHTML =
          '<span class="kradio"></span><span>📁</span>' +
          `<span class="kname" title="${esc(f.name)}">${esc(f.name)}</span>` + color;
        item.addEventListener('click', () => onFolderClick(f.id));
        els.list.appendChild(item);
      }
    }

    async function loadFolders() {
      const res = await sendMessage({ type: 'getFolders' });
      if (res.ok) {
        connected = true;
        folders = Array.isArray(res.folders) ? res.folders : [];
      } else {
        connected = false;
        folders = [];
      }
      const key = JSON.stringify(folders) + String(connected) + String(selectedFolderId);
      if (key !== foldersKey) {
        foldersKey = key;
        render();
      }
    }

    function startPolling() {
      stopPolling();
      pollTimer = setInterval(loadFolders, 3000); // автосинхронизация папок
    }

    function stopPolling() {
      if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
    }

    async function initSelection() {
      const s = await sendMessage({ type: 'getSettings' });
      if (s.ok && s.settings) {
        selectedFolderId = s.settings.lastFolderId ?? s.settings.defaultFolderId ?? null;
      }
      foldersKey = '';
      render();
    }

    function resetUi() {
      els.hint.hidden = false;
      els.thumb.hidden = true;
      els.thumb.removeAttribute('src');
      els.pendingName.hidden = true;
      els.pendingHint.hidden = true;
      els.create.hidden = true;
      els.barBtn.hidden = false;
      els.input.value = '';
      setStatus('', '');
      els.drop.classList.remove('kdrop--over');
    }

    function positionCard(opts) {
      const vw = window.innerWidth;
      const vh = window.innerHeight;
      const w = Math.min(W, vw - 16);
      const h = Math.min(H, vh - 16);
      let left;
      let top;
      if (opts.center || (opts.x == null && opts.y == null)) {
        left = Math.round((vw - w) / 2);
        top = Math.round((vh - h) / 2);
      } else {
        // Возле курсора, не вылезая за края.
        left = Math.round(opts.x + 16);
        top = Math.round(opts.y + 18);
        if (left + w > vw - 8) left = Math.round(opts.x - w - 16);
        if (top + h > vh - 8) top = Math.round(opts.y - h - 18);
        left = Math.max(8, Math.min(left, vw - w - 8));
        top = Math.max(8, Math.min(top, vh - h - 8));
      }
      els.card.style.width = `${w}px`;
      els.card.style.height = `${h}px`;
      els.card.style.left = `${left}px`;
      els.card.style.top = `${top}px`;
    }

    /** Открыть окно (если уже открыто — не трогаем состояние и положение). */
    function ensureOpen(opts = {}) {
      ensureBuilt();
      if (open) return;
      askMode = !!opts.ask;
      mode = 'idle';
      pending = null;
      selectedFolderId = null;
      resetUi();
      positionCard(opts);
      open = true;
      host.style.display = 'block';
      if (autoCloseTimer) { clearTimeout(autoCloseTimer); autoCloseTimer = null; }
      startPolling();
      initSelection();
      loadFolders();
    }

    function hide() {
      if (!open) return;
      open = false;
      mode = 'idle';
      pending = null;
      host.style.display = 'none';
      stopPolling();
      if (autoCloseTimer) { clearTimeout(autoCloseTimer); autoCloseTimer = null; }
    }

    /** Пользователь отменил перетаскивание — закрыть, если ничего не ждёт. */
    function scheduleAutoCloseIfIdle() {
      if (!open) return;
      if (mode === 'pending' || mode === 'saving' || mode === 'saved') return;
      if (autoCloseTimer) clearTimeout(autoCloseTimer);
      autoCloseTimer = setTimeout(() => {
        autoCloseTimer = null;
        if (open && mode === 'idle' && !pending) hide();
      }, 900);
    }

    function setPending(item) {
      ensureBuilt();
      if (!open) ensureOpen({ ask: true, center: true });
      askMode = true; // setPending вызывается только в режиме «спрашивать папку»
      cancelAutoClose();
      pending = item;
      mode = 'pending';
      els.hint.hidden = true;
      els.pendingHint.hidden = false;
      if (item.thumbUrl) {
        els.thumb.src = item.thumbUrl;
        els.thumb.hidden = false;
        els.thumb.onerror = () => { els.thumb.hidden = true; };
      } else {
        els.thumb.hidden = true;
      }
      els.pendingName.hidden = !item.label;
      els.pendingName.textContent = item.label || '';
      setStatus(item.label ? `Готово к сохранению: «${item.label}»` : '', 'busy');
    }

    function cancelAutoClose() {
      if (autoCloseTimer) { clearTimeout(autoCloseTimer); autoCloseTimer = null; }
    }

    async function onFolderClick(id) {
      // Режим «Спрашивать папку»: клик по папке = сохранить в неё.
      if (askMode && mode === 'pending' && pending) {
        await doSave(id);
        return;
      }
      selectedFolderId = id;
      try { await sendMessage({ type: 'setSettings', patch: { lastFolderId: id } }); } catch (e) {}
      foldersKey = '';
      render();
    }

    async function doSave(folderId) {
      if (!pending) return;
      const item = pending;
      mode = 'saving';
      cancelAutoClose();
      setStatus('Сохраняю…', 'busy');
      const res = await sendMessage({
        type: 'saveImage',
        image: item.image,
        folderId: folderId === undefined ? null : folderId,
      });
      if (res && res.ok) {
        mode = 'saved';
        pending = null;
        setStatus(
          res.target === 'hotfolder'
            ? 'Приложение закрыто — сохранено в «Загрузки/Коробка»'
            : 'Сохранено в Коробку ✓',
          'ok',
        );
        try { chrome.runtime.sendMessage({ type: 'dragSaved' }); } catch (e) {}
        setTimeout(() => { if (mode === 'saved') hide(); }, 1400);
      } else {
        mode = 'pending';
        setStatus('Не сохранено: ' + ((res && res.error) || 'неизвестная ошибка'), 'err');
      }
    }

    /** Прямое сохранение брошенного в окно (без режима «спрашивать папку»). */
    async function saveNow(item) {
      cancelAutoClose();
      pending = item;
      await doSave(selectedFolderId);
    }

    async function createFolder() {
      const name = els.input.value.trim();
      if (!name) { els.input.focus(); setStatus('Введите имя папки', 'err'); return; }
      els.createBtn.disabled = true;
      setStatus('Создаю папку…', 'busy');
      const res = await sendMessage({ type: 'createFolder', name });
      els.createBtn.disabled = false;
      if (res.ok) {
        els.input.value = '';
        const created = res.folder;
        setStatus(`Папка «${created.name}» создана`, 'ok');
        folders = [];
        foldersKey = '';
        await loadFolders();
        // Режим «спрашивать папку»: создаём и сразу сохраняем в неё.
        if (askMode && mode === 'pending' && pending) {
          await doSave(created.id);
        } else {
          await onFolderClick(created.id);
          els.create.hidden = true;
          els.barBtn.hidden = false;
          setTimeout(() => setStatus(''), 2000);
        }
      } else {
        setStatus('Ошибка: ' + (res.error || '?'), 'err');
      }
    }

    return {
      ensureOpen,
      hide,
      isOpen: () => open,
      isAskMode: () => askMode,
      getMode: () => mode,
      containsTarget: (t) => !!(open && host && host.contains(t)),
      setPending,
      setStatus,
      saveNow,
      scheduleAutoCloseIfIdle,
      cancelAutoClose,
      refreshFolders: loadFolders,
    };
  })();

  // ───────────────────────── ФАЙЛЫ ИЗ ПРОВОДНИКА ─────────────────────────
  // Отдельное небольшое окно (как в v0.4): открываем, когда пользователь
  // тянет файл из Проводника над страницей. Сайты со своими dropzone
  // не затрагиваем — перехватываем только картинокные перетаскивания.

  function maybeOpenOsDragWindow(e) {
    if (osDragSent) return;
    if (!e.dataTransfer) return;
    const types = e.dataTransfer.types || [];
    if (types.length !== 1 || types[0] !== 'Files') return; // чистый drag файлов
    if (cfg.dragWindow === false && !cfg.askFolder) return; // окна выключены
    osDragSent = true;
    try {
      chrome.runtime.sendMessage({ type: 'dragStart', x: e.screenX, y: e.screenY });
    } catch (err) { /* окно не критично */ }
  }

  function endOsDrag() {
    if (!osDragSent) return;
    osDragSent = false;
    try { chrome.runtime.sendMessage({ type: 'dragEnded' }); } catch (e) { /* не критично */ }
  }

  // ───────────────────────── БРОСОК НА СТРАНИЦЕ ─────────────────────────

  async function handlePageDrop(dataTransfer, ctx) {
    picker.cancelAutoClose();
    let resolved = null;
    try {
      resolved = await resolveFromDataTransfer(dataTransfer, ctx.startEl);
    } catch (e) {
      showToast('Не удалось прочитать картинку: ' + e.message, 'error');
      return;
    }
    if (!resolved) {
      showToast('Это не похоже на картинку — в Коробку нечего сохранять', 'error');
      return;
    }

    await refreshCfg();

    if (cfg.askFolder) {
      // Спрашивать папку: показываем окно и ждём выбора папки.
      picker.ensureOpen({ ask: true, center: true });
      picker.setPending({
        image: resolved.image,
        label: resolved.image.filename || resolved.label || 'картинка',
        thumbUrl: resolved.image.base64 || resolved.image.url || null,
      });
      return;
    }

    // Обычный режим v0.4: сразу сохраняем в выбранную папку.
    let response;
    try {
      response = await sendMessage({ type: 'saveImage', image: resolved.image });
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
      try { chrome.runtime.sendMessage({ type: 'dragSaved' }); } catch (err) { /* не критично */ }
    } else {
      showToast('Не сохранено: ' + ((response && response.error) || 'неизвестная ошибка'), 'error');
    }
  }

  async function handlePickerDrop(dataTransfer) {
    picker.cancelAutoClose();
    let resolved = null;
    try {
      resolved = await resolveFromDataTransfer(dataTransfer, null);
    } catch (e) {
      picker.setStatus('Не удалось прочитать: ' + (e.message || e), 'err');
      return;
    }
    if (!resolved) {
      picker.setStatus('Это не похоже на картинку', 'err');
      return;
    }
    await refreshCfg();
    if (cfg.askFolder || picker.isAskMode()) {
      picker.setPending({
        image: resolved.image,
        label: resolved.image.filename || resolved.label || 'картинка',
        thumbUrl: resolved.image.base64 || resolved.image.url || null,
      });
    } else {
      await picker.saveNow(resolved);
    }
  }

  // ───────────────────────── ПЕРЕТАСКИВАНИЕ ─────────────────────────

  document.addEventListener(
    'dragstart',
    (e) => {
      const t = e.target;
      const isImg = t && (t.tagName === 'IMG' || (t.closest && t.closest('img, picture')));
      const styled = t && t.tagName !== 'IMG' && t.tagName !== 'PICTURE' && t.closest && t.closest('[style*="background"]');
      if (!isImg && !styled) return; // тексты, ссылки и файлы не перехватываем

      dragImage = { startEl: t, startedAt: Date.now() };
      refreshCfg().then(() => {
        // Окно с папками (как в Eagle / как в v4.1.0) или простой баннер.
        if (cfg.askFolder || cfg.dragWindow !== false) {
          picker.ensureOpen({ ask: cfg.askFolder, x: e.clientX, y: e.clientY });
        } else {
          showBanner();
        }
      });
    },
    true,
  );

  document.addEventListener(
    'dragover',
    (e) => {
      if (picker.isOpen()) {
        // Пока открыто окно — бросать можно в любом месте страницы.
        e.preventDefault();
        e.stopPropagation();
        if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
        return;
      }
      if (dragImage) {
        // Разрешаем бросок в любом месте страницы.
        e.preventDefault();
        e.stopPropagation();
        if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
        return;
      }
      maybeOpenOsDragWindow(e);
    },
    true,
  );

  document.addEventListener(
    'drop',
    (e) => {
      if (picker.isOpen()) {
        e.preventDefault();
        e.stopPropagation();
        handlePickerDrop(e.dataTransfer).catch((err) => {
          picker.setStatus('Ошибка: ' + (err.message || err), 'err');
        });
        return;
      }
      if (dragImage) {
        e.preventDefault();
        e.stopPropagation();
        const ctx = dragImage;
        dragImage = null;
        hideBanner();
        handlePageDrop(e.dataTransfer, ctx).catch((err) => {
          console.warn('[Коробка]', err);
          showToast('Ошибка: ' + (err.message || err), 'error');
        });
        return;
      }
      // Файл из Проводника бросили на страницу (мимо окна) — не мешаем сайту.
      if (osDragSent) endOsDrag();
    },
    true,
  );

  document.addEventListener(
    'dragend',
    () => {
      // Пользователь бросил картинку вне окна браузера или отменил перетаскивание.
      dragImage = null;
      hideBanner();
      if (picker.isOpen()) picker.scheduleAutoCloseIfIdle();
      endOsDrag();
    },
    true,
  );

  document.addEventListener(
    'dragleave',
    (e) => {
      // Drag из Проводника ушёл за пределы страницы.
      if (osDragSent && !e.relatedTarget) endOsDrag();
    },
    true,
  );

  // ───────────────── КОМАНДА ИЗ ФОНА (контекстное меню) ─────────────────

  try {
    chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
      if (msg && msg.type === 'askSave' && msg.image) {
        refreshCfg().then(() => {
          picker.ensureOpen({ ask: true, center: true });
          picker.setPending({
            image: msg.image,
            label: msg.image.filename || 'картинка',
            thumbUrl: msg.image.base64 || msg.image.url || null,
          });
          sendResponse({ ok: true });
        });
        return true; // асинхронный ответ
      }
      return undefined;
    });
  } catch (e) { /* onMessage недоступен — контекстное меню сохраняет напрямую */ }
})();
