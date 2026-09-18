/**
 * Коробка — всплывающее окно.
 *
 * Ключевые исправления v0.4.0 (по отзыву пользователя):
 *  - в поле, где раньше было «нет папок», теперь реально загружается список
 *    папок из приложения (GET /api/folder/list);
 *  - список автоматически обновляется каждые 3 секунды, пока окно открыто,
 *    поэтому папки, созданные в приложении, подхватываются сами;
 *  - кнопка «Создать» действительно создаёт папку (POST /api/folder/create);
 *  - выбор папки работает и запоминается (сохранение по умолчанию);
 *  - любая ошибка показывается текстом, а не «пропадает» молча.
 */

'use strict';

const els = {
  statusDot: document.getElementById('status-dot'),
  connBanner: document.getElementById('conn-banner'),
  folderList: document.getElementById('folder-list'),
  refresh: document.getElementById('refresh-folders'),
  nameInput: document.getElementById('new-folder-name'),
  createBtn: document.getElementById('create-folder'),
  saveTabImage: document.getElementById('save-tab-image'),
  actionStatus: document.getElementById('action-status'),
  appInfo: document.getElementById('app-info'),
  openOptions: document.getElementById('open-options'),
};

let connected = false;
let selectedFolderId = null;   // null = корень коллекции («Все картинки»)
let foldersCache = '';
let pollTimer = null;
let appVersion = null;
let appPort = null;

// ─────────────────────────── ВСПОМОГАТЕЛЬНЫЕ ───────────────────────────

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

function setStatus(connState, version, port) {
  connected = connState;
  appVersion = version;
  appPort = port;
  els.statusDot.classList.toggle('status-dot--on', connState);
  els.statusDot.classList.toggle('status-dot--off', !connState);
  els.statusDot.title = connState
    ? `Приложение запущено (порт ${port}, версия ${version || '?'})`
    : 'Приложение не найдено';
  els.connBanner.classList.toggle('conn-banner--hidden', connState);
  els.appInfo.textContent = connState
    ? `Приложение: порт ${port}${version ? ' · v' + version : ''}`
    : 'Нет связи с приложением';
}

function showStatus(text, kind) {
  els.actionStatus.hidden = false;
  els.actionStatus.textContent = text;
  els.actionStatus.className = `action-status action-status--${kind}`;
}

function esc(s) {
  const d = document.createElement('div');
  d.textContent = String(s);
  return d.innerHTML;
}

/** Глубина вложенности папки (для отступа подпапок). */
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

// ─────────────────────────── СПИСОК ПАПОК ───────────────────────────

function renderFolders(folders) {
  const key = JSON.stringify(folders);
  if (key === foldersCache) return; // без изменений — не перерисовываем
  foldersCache = key;

  els.folderList.innerHTML = '';

  const root = document.createElement('div');
  root.className = 'folder-item' + (selectedFolderId === null ? ' folder-item--selected' : '');
  root.innerHTML =
    '<span class="folder-item__radio"></span>' +
    '<span class="folder-item__icon">🗃️</span>' +
    '<span class="folder-item__name">Все картинки (корень)</span>';
  root.addEventListener('click', () => selectFolder(null));
  els.folderList.appendChild(root);

  if (folders.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'folder-empty';
    empty.innerHTML = 'В приложении пока нет папок.<br/>Создайте первую ниже — она появится и в приложении.';
    els.folderList.appendChild(empty);
    return;
  }

  const byId = new Map(folders.map((f) => [f.id, f]));
  for (const f of folders) {
    const depth = depthOf(f, byId);
    const item = document.createElement('div');
    item.className = 'folder-item' + (String(selectedFolderId) === String(f.id) ? ' folder-item--selected' : '');
    item.style.paddingLeft = `${10 + depth * 16}px`;
    const color = f.color
      ? `<span class="folder-item__color" style="background:${esc(f.color)}"></span>`
      : '';
    item.innerHTML =
      '<span class="folder-item__radio"></span>' +
      '<span class="folder-item__icon">📁</span>' +
      `<span class="folder-item__name" title="${esc(f.name)}">${esc(f.name)}</span>` +
      color;
    item.addEventListener('click', () => selectFolder(f.id));
    els.folderList.appendChild(item);
  }
}

async function selectFolder(id) {
  selectedFolderId = id;
  await sendMessage({ type: 'setSettings', patch: { lastFolderId: id } });
  const folders = parseFolders(foldersCache);
  renderFoldersReset(folders);
}

function parseFolders(json) {
  try { return JSON.parse(json); } catch (e) { return []; }
}

/** Принудительная перерисовка (сброс кэша). */
function renderFoldersReset(folders) {
  foldersCache = '';
  renderFolders(folders || parseFolders(foldersCache));
}

async function loadFolders(force = false) {
  const res = await sendMessage({ type: 'getFolders' });
  if (res.ok) {
    setStatus(true, appVersion, appPort);
    if (force) {
      renderFoldersReset(res.folders || []);
    } else {
      renderFolders(res.folders || []);
    }
    return true;
  }
  setStatus(false, null, null);
  els.folderList.innerHTML =
    '<div class="folder-empty">Нет связи с приложением.<br/>Запустите «Коробку» и нажмите ⟳</div>';
  return false;
}

// ─────────────────────────── ПОДКЛЮЧЕНИЕ ───────────────────────────

async function connect(forceReload = true) {
  const ping = await sendMessage({ type: 'ping' });
  if (ping.ok) {
    setStatus(true, ping.version, ping.port);
    await loadFolders(forceReload);
    startPolling();
  } else {
    setStatus(false, null, null);
    els.folderList.innerHTML =
      '<div class="folder-empty">Нет связи с приложением.<br/>Запустите «Коробку» и нажмите ⟳</div>';
  }
}

function startPolling() {
  if (pollTimer) clearInterval(pollTimer);
  // Пока окно открыто — синхронизируем папки с приложением каждые 3 секунды.
  pollTimer = setInterval(async () => {
    if (!connected) {
      await connect(true);
      return;
    }
    await loadFolders(false);
  }, 3000);
}

// ─────────────────────────── СОЗДАНИЕ ПАПКИ ───────────────────────────

async function createFolder() {
  const name = els.nameInput.value.trim();
  if (!name) {
    els.nameInput.focus();
    showStatus('Введите имя папки', 'err');
    return;
  }
  if (!connected) {
    showStatus('Приложение не запущено — папку создать нельзя', 'err');
    return;
  }
  els.createBtn.disabled = true;
  showStatus('Создаю папку…', 'busy');
  const res = await sendMessage({ type: 'createFolder', name });
  els.createBtn.disabled = false;
  if (res.ok) {
    els.nameInput.value = '';
    selectedFolderId = res.folder.id;
    showStatus(`Папка «${res.folder.name}» создана и выбрана`, 'ok');
    await loadFolders(true);
  } else {
    showStatus('Не удалось создать папку: ' + (res.error || '?'), 'err');
  }
}

// ─────────────────── СОХРАНЕНИЕ КАРТИНКИ СО СТРАНИЦЫ ───────────────────

async function saveTabPageImage() {
  els.saveTabImage.disabled = true;
  showStatus('Ищу самую большую картинку на странице…', 'busy');
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab || !tab.id || !/^https?:/i.test(tab.url || '')) {
      showStatus('На этой странице расширение работать не может', 'err');
      return;
    }
    const results = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: () => {
        let best = null;
        let bestArea = 0;
        for (const img of document.images) {
          const r = img.getBoundingClientRect();
          const area = r.width * r.height;
          if (area > bestArea && (img.currentSrc || img.src)) {
            bestArea = area;
            best = { url: img.currentSrc || img.src, w: r.width, h: r.height };
          }
        }
        return best;
      },
    });
    const found = results && results[0] && results[0].result;
    if (!found) {
      showStatus('На странице не найдено картинок', 'err');
      return;
    }
    showStatus('Сохраняю в Коробку…', 'busy');
    const res = await sendMessage({ type: 'saveImage', image: { url: found.url } });
    if (res.ok) {
      showStatus(
        res.target === 'hotfolder'
          ? 'Приложение закрыто — сохранено в «Загрузки/Коробка»'
          : 'Сохранено в Коробку ✓',
        'ok',
      );
    } else {
      showStatus('Не сохранено: ' + (res.error || '?'), 'err');
    }
  } catch (e) {
    showStatus('Ошибка: ' + (e.message || e), 'err');
  } finally {
    els.saveTabImage.disabled = false;
  }
}

// ─────────────────────────── СТАРТ ───────────────────────────

async function init() {
  const res = await sendMessage({ type: 'getSettings' });
  if (res.ok && res.settings) {
    selectedFolderId = res.settings.lastFolderId ?? res.settings.defaultFolderId ?? null;
  }
  els.createBtn.addEventListener('click', createFolder);
  els.nameInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') createFolder();
  });
  els.refresh.addEventListener('click', () => connect(true));
  els.saveTabImage.addEventListener('click', saveTabPageImage);
  els.openOptions.addEventListener('click', () => chrome.runtime.openOptionsPage());
  await connect(true);
  els.nameInput.focus();
}

init();
