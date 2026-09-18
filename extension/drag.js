/**
 * Коробка — окно перетаскивания (плавающая панель, как в Eagle).
 *
 * Что исправлено в v0.4.0 по отзыву пользователя:
 *  - в правой панели, где раньше было «Нет папок», теперь отображаются
 *    папки, созданные в приложении, и синхронизируются каждые 3 секунды;
 *  - кнопка «Создать или выбрать папку» реально работает: раскрывает поле
 *    и создаёт папку через приложение (POST /api/folder/create);
 *  - выбрасывание картинки/файла в левую зону сохраняет его в Коробку
 *    (в выбранную папку), включая файлы, перетащенные из Проводника;
 *  - страница Pinterest больше не запрашивает «доступ к приложениям и
 *    сервисам» — все запросы к приложению идут через сервис-воркер
 *    расширения, а не со страницы сайта.
 */

'use strict';

const els = {
  connDot: document.getElementById('conn-dot'),
  closeBtn: document.getElementById('close-btn'),
  dropZone: document.getElementById('drop-zone'),
  dropLabel: document.getElementById('drop-label'),
  dropStatus: document.getElementById('drop-status'),
  folderList: document.getElementById('folder-list'),
  toggleCreate: document.getElementById('toggle-create'),
  createBlock: document.getElementById('create-block'),
  nameInput: document.getElementById('new-folder-name'),
  createBtn: document.getElementById('create-folder'),
};

let selectedFolderId = null;
let connected = false;
let pollTimer = null;
let foldersJson = '';
let lastFolders = [];

// ─────────────────────────── УТИЛИТЫ ───────────────────────────

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

function setDropStatus(text, kind) {
  els.dropStatus.textContent = text;
  els.dropStatus.className = `drop-status${kind ? ` drop-status--${kind}` : ''}`;
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

// ─────────────────────────── ПАПКИ (синхронизация) ───────────────────────────

function renderFolders(folders) {
  const key = JSON.stringify(folders);
  if (key === foldersJson) return;
  foldersJson = key;
  lastFolders = folders;

  els.folderList.innerHTML = '';

  const root = document.createElement('div');
  root.className = 'folder-item' + (selectedFolderId === null ? ' folder-item--selected' : '');
  root.innerHTML =
    '<span class="folder-item__radio"></span>' +
    '<span>🗃️</span>' +
    '<span class="folder-item__name">Все картинки (корень)</span>';
  root.addEventListener('click', () => selectFolder(null));
  els.folderList.appendChild(root);

  if (folders.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'folder-empty';
    empty.innerHTML = 'В приложении пока нет папок.<br/>Создайте первую кнопкой ниже.';
    els.folderList.appendChild(empty);
    return;
  }

  const byId = new Map(folders.map((f) => [f.id, f]));
  for (const f of folders) {
    const depth = depthOf(f, byId);
    const item = document.createElement('div');
    item.className =
      'folder-item' + (String(selectedFolderId) === String(f.id) ? ' folder-item--selected' : '');
    item.style.paddingLeft = `${12 + depth * 14}px`;
    item.innerHTML =
      '<span class="folder-item__radio"></span>' +
      '<span>📁</span>' +
      `<span class="folder-item__name" title="${esc(f.name)}">${esc(f.name)}</span>`;
    item.addEventListener('click', () => selectFolder(f.id));
    els.folderList.appendChild(item);
  }
}

async function selectFolder(id) {
  selectedFolderId = id;
  await sendMessage({ type: 'setSettings', patch: { lastFolderId: id } });
  foldersJson = ''; // сброс кэша — перерисовать с новым выделением
  renderFolders(lastFolders);
}

async function loadFolders() {
  const res = await sendMessage({ type: 'getFolders' });
  if (res.ok) {
    connected = true;
    els.connDot.classList.add('conn-dot--on');
    els.connDot.title = 'Приложение запущено';
    renderFolders(res.folders || []);
    return;
  }
  connected = false;
  els.connDot.classList.remove('conn-dot--on');
  els.connDot.title = 'Приложение не найдено';
  els.folderList.innerHTML =
    '<div class="folder-empty">Нет связи с приложением.<br/>Запустите «Коробку».</div>';
}

// ─────────────────────────── СОЗДАНИЕ ПАПКИ ───────────────────────────

async function createFolder() {
  const name = els.nameInput.value.trim();
  if (!name) {
    els.nameInput.focus();
    setDropStatus('Введите имя папки', 'err');
    return;
  }
  els.createBtn.disabled = true;
  setDropStatus('Создаю папку…', 'busy');
  const res = await sendMessage({ type: 'createFolder', name });
  els.createBtn.disabled = false;
  if (res.ok) {
    els.nameInput.value = '';
    selectedFolderId = res.folder.id;
    setDropStatus(`Папка «${res.folder.name}» создана`, 'ok');
    foldersJson = '';
    const r2 = await sendMessage({ type: 'getFolders' });
    if (r2.ok) renderFolders(r2.folders || []);
    setTimeout(() => setDropStatus(''), 2000);
  } else {
    setDropStatus('Ошибка: ' + (res.error || '?'), 'err');
  }
}

// ─────────────────────────── ПРИЁМ БРОСКА ───────────────────────────

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

function urlFromElement(el) {
  if (!el || el.tagName !== 'IMG') return '';
  return el.currentSrc || el.getAttribute('src') || largestFromSrcset(el.getAttribute('srcset')) || '';
}

function urlFromDragHtml(html) {
  if (!html) return '';
  try {
    const doc = new DOMParser().parseFromString(html, 'text/html');
    return urlFromElement(doc.querySelector('img'));
  } catch (e) {
    return '';
  }
}

/** Читает файл из Проводника как data URL (drag из ОС). */
function fileToDataUrl(file) {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve({ base64: String(r.result), mime: file.type || '', filename: file.name || '' });
    r.onerror = () => reject(new Error('не удалось прочитать файл'));
    r.readAsDataURL(file);
  });
}

async function resolveDrop(dataTransfer) {
  // 1) Реальные файлы (из Проводника или «перетащить картинку как файл»).
  if (dataTransfer.files && dataTransfer.files.length > 0) {
    const file = dataTransfer.files[0];
    if (file.type.startsWith('image/') || /\.(png|jpe?g|webp|gif|bmp|tiff|svg|ico)$/i.test(file.name)) {
      const data = await fileToDataUrl(file);
      return { image: data, label: file.name };
    }
  }

  // 2) HTML-представление (перетаскивание картинки со страницы).
  let html = '';
  try { html = dataTransfer.getData('text/html'); } catch (e) { /* защищено */ }
  let url = urlFromDragHtml(html);

  // 3) Ссылка/текст.
  if (!url) {
    let uri = '';
    try { uri = dataTransfer.getData('text/uri-list') || dataTransfer.getData('text/plain'); } catch (e) {}
    if (uri && /^https?:\/\//i.test(uri.trim())) url = uri.trim();
  }

  if (!url) return null;

  if (/^(blob|data):/i.test(url)) {
    // blob:/data: приложение скачать не может — читаем как data URL.
    // В окне перетаскивания blob: со страницы недоступен (другой origin),
    // поэтому просто пробуем fetch и честно сообщаем об ошибке.
    try {
      const resp = await fetch(url);
      const blob = await resp.blob();
      const data = await fileToDataUrl(new File([blob], 'image', { type: blob.type || 'image/png' }));
      return { image: data, label: 'картинка' };
    } catch (e) {
      return null;
    }
  }
  if (/^https?:/i.test(url)) {
    return { image: { url, filename: filenameFromUrl(url) }, label: 'картинка' };
  }
  return null;
}

function filenameFromUrl(u) {
  try {
    const p = new URL(u).pathname.split('/').pop();
    return p && /\.[a-z0-9]{2,5}$/i.test(p) ? decodeURIComponent(p) : '';
  } catch (e) { return ''; }
}

async function handleDrop(e) {
  e.preventDefault();
  els.dropZone.classList.remove('drop-zone--over');
  els.dropLabel.textContent = 'Перетащите файлы сюда';

  setDropStatus('Сохраняю…', 'busy');
  let drop;
  try {
    drop = await resolveDrop(e.dataTransfer);
  } catch (err) {
    setDropStatus('Не удалось прочитать: ' + err.message, 'err');
    return;
  }
  if (!drop) {
    setDropStatus('Это не похоже на картинку', 'err');
    return;
  }

  const res = await sendMessage({ type: 'saveImage', image: drop.image });
  if (res.ok) {
    setDropStatus(
      res.target === 'hotfolder'
        ? 'Приложение закрыто — сохранено в «Загрузки/Коробка»'
        : 'Сохранено в Коробку ✓',
      'ok',
    );
    await sendMessage({ type: 'dragSaved' });
    setTimeout(() => window.close(), 1400);
  } else {
    setDropStatus('Не сохранено: ' + (res.error || '?'), 'err');
  }
}

// ─────────────────────────── СОБЫТИЯ ───────────────────────────

els.dropZone.addEventListener('dragover', (e) => {
  e.preventDefault();
  e.dataTransfer.dropEffect = 'copy';
  els.dropZone.classList.add('drop-zone--over');
});
els.dropZone.addEventListener('dragleave', () => {
  els.dropZone.classList.remove('drop-zone--over');
});
els.dropZone.addEventListener('drop', handleDrop);

els.toggleCreate.addEventListener('click', () => {
  els.createBlock.hidden = !els.createBlock.hidden;
  if (!els.createBlock.hidden) els.nameInput.focus();
});

els.createBtn.addEventListener('click', createFolder);
els.nameInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') createFolder();
});

els.closeBtn.addEventListener('click', async () => {
  try {
    const win = await chrome.windows.getCurrent();
    await chrome.windows.remove(win.id);
  } catch (e) { /* окно уже закрыто */ }
});

// ─────────────────────────── СТАРТ ───────────────────────────

async function init() {
  const s = await sendMessage({ type: 'getSettings' });
  if (s.ok && s.settings) {
    selectedFolderId = s.settings.lastFolderId ?? s.settings.defaultFolderId ?? null;
  }
  await loadFolders();
  // Синхронизация папок с приложением, пока окно открыто.
  pollTimer = setInterval(loadFolders, 3000);
  window.addEventListener('unload', () => clearInterval(pollTimer));
}

init();
