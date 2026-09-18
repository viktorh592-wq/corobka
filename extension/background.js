/**
 * Коробка — фоновый сервис-воркер расширения.
 *
 * Отвечает за:
 *  - поиск приложения «Коробка» на локальных портах 41595…41597;
 *  - список папок, создание папок (POST /api/folder/create);
 *  - сохранение картинок в коллекцию (POST /api/item/add: url или base64);
 *  - запасной путь — загрузка в горячую папку «Загрузки/Коробка» через
 *    chrome.downloads, если приложение закрыто (подхватится при старте);
 *  - контекстное меню «Сохранить картинку в Коробку»;
 *  - пересылку журнала плагина в общий лог приложения.
 */

'use strict';

// ─────────────────────────── НАСТРОЙКИ/СОСТОЯНИЕ ───────────────────────────

const DEFAULT_PORTS = [41595, 41596, 41597];
const DEFAULT_SETTINGS = {
  defaultFolderId: null,   // папка по умолчанию (id из приложения)
  lastFolderId: null,      // последняя выбранная в попапе папка
  overlayEnabled: true,    // баннер при перетаскивании картинки
  saveToast: true,         // всплывающее подтверждение сохранения
  saveMode: 'auto',        // 'auto' | 'server' | 'hotfolder'
  dragWindow: true,        // окно с папками при перетаскивании (как в Eagle/v4.1.0)
  askFolder: false,        // спрашивать папку перед каждым сохранением.
                           // Хранится в chrome.storage.local — глобально для всех
                           // сайтов, не сбрасывается при переходах/перезагрузках.
};

let activePort = null;       // порт, на котором найдено приложение
let lastFolders = [];        // кэш списка папок (для fallback-имён)
let dragWindowId = null;     // id окна приёма файлов из Проводника
let lastWindowSaveAt = 0;    // время последнего сохранения через окно
let windowHasPending = false; // в окне ждёт выбора папки файл (режим «спрашивать»)
let idleCloseTimer = null;

// ─────────────────────────── УТИЛИТЫ ───────────────────────────

async function getSettings() {
  try {
    const stored = await chrome.storage.local.get(DEFAULT_SETTINGS);
    return { ...DEFAULT_SETTINGS, ...stored };
  } catch (e) {
    return { ...DEFAULT_SETTINGS };
  }
}

async function patchSettings(patch) {
  await chrome.storage.local.set(patch);
}

/** fetch с таймаутом (AbortController), чтобы не висеть на мёртвых портах. */
async function fetchWithTimeout(url, options = {}, ms = 2500) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), ms);
  try {
    return await fetch(url, { ...options, signal: ctrl.signal });
  } finally {
    clearTimeout(timer);
  }
}

// ─────────────────────────── ПОИСК ПРИЛОЖЕНИЯ ───────────────────────────

/** Однократный ping конкретного порта. */
async function pingPort(port) {
  try {
    const resp = await fetchWithTimeout(
      `http://127.0.0.1:${port}/api/ping`,
      { method: 'GET' },
      1200,
    );
    if (!resp.ok) return null;
    const json = await resp.json();
    if (json && json.status === 'success' && json.data && json.data.name === 'korobka') {
      return { port, version: json.data.version || '?' };
    }
    return null;
  } catch (e) {
    return null;
  }
}

/** Найти запущенное приложение. Кэширует найденный порт. */
async function findApp() {
  // Сначала быстрый путь — прошлая удачная попытка.
  if (activePort !== null) {
    const ok = await pingPort(activePort);
    if (ok) return ok;
    activePort = null;
  }
  for (const port of DEFAULT_PORTS) {
    const ok = await pingPort(port);
    if (ok) {
      activePort = port;
      await pluginLog('INFO', `Приложение найдено на порту ${port} (v${ok.version})`);
      return ok;
    }
  }
  return null;
}

/** Убедиться, что есть соединение; бросает понятную ошибку. */
async function requireApp() {
  const app = activePort !== null ? await pingPort(activePort) : null;
  if (app) return app;
  const found = await findApp();
  if (!found) {
    const err = new Error('Приложение «Коробка» не запущено (или сервер интеграции недоступен)');
    err.code = 'APP_NOT_RUNNING';
    throw err;
  }
  return found;
}

// ─────────────────────────── API ПРИЛОЖЕНИЯ ───────────────────────────

async function apiGetFolders() {
  const app = await requireApp();
  const resp = await fetchWithTimeout(
    `http://127.0.0.1:${app.port}/api/folder/list`,
    { method: 'GET' },
    2500,
  );
  const json = await resp.json();
  if (!resp.ok || json.status !== 'success') {
    throw new Error((json && json.message) || `HTTP ${resp.status}`);
  }
  lastFolders = Array.isArray(json.data) ? json.data : [];
  return lastFolders;
}

async function apiCreateFolder(name, parentId = null) {
  const app = await requireApp();
  const resp = await fetchWithTimeout(
    `http://127.0.0.1:${app.port}/api/folder/create`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, parentId }),
    },
    5000,
  );
  const json = await resp.json();
  if (!resp.ok || json.status !== 'success') {
    throw new Error((json && json.message) || `HTTP ${resp.status}`);
  }
  return json.data; // {id, name, parentId}
}

/**
 * Сохранение картинки в коллекцию.
 * image: {url?, base64?, mime?, filename?} — url приоритетнее, если есть оба.
 * Пробует варианты URLs по очереди (для Pinterest: сначала /originals/).
 */
async function apiAddItem(image, folderId) {
  const app = await requireApp();

  const urls = [];
  if (image.url) urls.push(image.url);
  if (image.url && image.altUrls) urls.push(...image.altUrls);

  for (const url of urls) {
    try {
      const resp = await fetchWithTimeout(
        `http://127.0.0.1:${app.port}/api/item/add`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ url, folderId }),
        },
        60000, // скачивание большой картинки может идти долго
      );
      const json = await resp.json();
      if (resp.ok && json.status === 'success') return json.data;
      await pluginLog('WARN', `Не удалось сохранить по URL (${shortUrl(url)}): ${json && json.message}`);
    } catch (e) {
      await pluginLog('WARN', `Ошибка запроса к приложению (${shortUrl(url)}): ${e.message}`);
    }
  }

  // URL-пути исчерпаны — пробуем base64, если он есть.
  if (image.base64) {
    const resp = await fetchWithTimeout(
      `http://127.0.0.1:${app.port}/api/item/add`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          base64: image.base64,
          mime: image.mime || '',
          filename: image.filename || '',
          folderId,
        }),
      },
      60000,
    );
    const json = await resp.json();
    if (resp.ok && json.status === 'success') return json.data;
    throw new Error((json && json.message) || `HTTP ${resp.status}`);
  }

  if (urls.length === 0 && !image.base64) {
    throw new Error('Не передан ни URL, ни данные картинки');
  }
  throw new Error('Приложение не смогло скачать картинку по всем вариантам ссылки');
}

// ───────────────────── ЗАПАСНОЙ ПУТЬ: ГОРЯЧАЯ ПАПКА ─────────────────────

/** Имя папки коллекции по id (для подпапки в «Загрузки/Коробка»). */
function folderNameById(id) {
  if (id == null) return '';
  const f = lastFolders.find((x) => String(x.id) === String(id));
  return f ? sanitizeSegment(f.name) : '';
}

function sanitizeSegment(name) {
  return String(name)
    .replace(/[\\/:*?"<>|]/g, '_')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 80);
}

function extForImage(image) {
  const fromMime = {
    'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp',
    'image/gif': 'gif', 'image/bmp': 'bmp', 'image/svg+xml': 'svg',
  };
  if (image.mime && fromMime[image.mime]) return fromMime[image.mime];
  const m = (image.url || image.filename || '').match(/\.(png|jpe?g|webp|gif|bmp|svg|tiff?|ico)(?:[?#]|$)/i);
  if (m) {
    const e = m[1].toLowerCase().replace('jpeg', 'jpg').replace('tiff', 'tiff');
    return e;
  }
  return 'jpg';
}

/**
 * Сохранение через chrome.downloads в «Загрузки/Коробка[/Папка]».
 * Работает и когда приложение закрыто — файл подхватится при старте.
 */
async function downloadToHotFolder(image, folderId) {
  // folderId уже разрешён в saveImageSmart (null = явный корень — без подпапки).
  const sub = folderNameById(folderId);
  const dir = sub ? `Коробка/${sub}/` : 'Коробка/';
  const stamp = Date.now();
  const filename = `${dir}korobka_${stamp}.${extForImage(image)}`;

  let source = image.url || '';
  if (!source && image.base64) {
    source = `data:${image.mime || 'image/jpeg'};base64,${image.base64}`;
  }
  if (!source) throw new Error('Нечего сохранять: нет URL и данных картинки');

  const id = await chrome.downloads.download({
    url: source,
    filename,
    conflictAction: 'uniquify',
    saveAs: false,
  });
  await pluginLog('INFO', `Файл сохранён в горячую папку (${filename}), id загрузки: ${id}`);
  return { saved: 'hotfolder', filename };
}

// ───────────────────── ВЫСОКОУРОВНЕВОЕ СОХРАНЕНИЕ ─────────────────────

/** Единая точка сохранения: пробует сервер, потом горячую папку.
 * folderIdRaw: undefined — выбора не было (берём папку по умолчанию);
 * null — пользователь ЯВНО выбрал корень («Все картинки»); число — папка. */
async function saveImageSmart(image, folderIdRaw) {
  const settings = await getSettings();
  const folderId = folderIdRaw !== undefined
    ? folderIdRaw
    : settings.lastFolderId ?? settings.defaultFolderId ?? null;

  const mode = settings.saveMode || 'auto';
  const serverOk = mode === 'auto' || mode === 'server';

  if (serverOk) {
    try {
      await ensureFoldersLoaded();
      const data = await apiAddItem(image, folderId);
      return { ok: true, target: 'server', data };
    } catch (e) {
      await pluginLog('WARN', `Сервер: ${e.message}`);
      if (mode === 'server') throw e;
    }
  }
  // auto → горячая папка; hotfolder → сразу сюда.
  const res = await downloadToHotFolder(image, folderId);
  return { ok: true, target: 'hotfolder', data: res };
}

async function ensureFoldersLoaded() {
  if (lastFolders.length === 0) {
    try { await apiGetFolders(); } catch (e) { /* нет соединения — ок */ }
  }
}

// ───────────────────── ЖУРНАЛ (общий с приложением) ─────────────────────

let logQueue = [];
let logTimer = null;

function pluginLog(level, message) {
  const entry = { level, descriptor: message, ts: Date.now() };
  logQueue.push(entry);
  if (logQueue.length > 200) logQueue = logQueue.slice(-200);
  if (!logTimer) logTimer = setTimeout(flushLogs, 2000);
  return Promise.resolve();
}

async function flushLogs() {
  logTimer = null;
  if (logQueue.length === 0) return;
  const batch = logQueue.splice(0, logQueue.length);
  if (activePort === null) return; // приложение недоступно — журнал остаётся локально
  for (const entry of batch) {
    try {
      await fetchWithTimeout(
        `http://127.0.0.1:${activePort}/api/log`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ level: entry.level, descriptor: entry.descriptor }),
        },
        1500,
      );
    } catch (e) { /* молча — журнал не критичен */ }
  }
}

function shortUrl(u) {
  try {
    const url = new URL(u);
    return url.pathname.split('/').pop() || url.hostname;
  } catch (e) { return String(u).slice(0, 60); }
}

// ───────────────────── КОНТЕКСТНОЕ МЕНЮ ─────────────────────

const MENU_SAVE = 'korobka-save-image';

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: MENU_SAVE,
      title: 'Сохранить картинку в Коробку',
      contexts: ['image'],
    });
  });
});
chrome.runtime.onStartup.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: MENU_SAVE,
      title: 'Сохранить картинку в Коробку',
      contexts: ['image'],
    });
  });
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId !== MENU_SAVE) return;
  const srcUrl = info.srcUrl;
  if (!srcUrl) return;
  const image = { url: srcUrl, altUrls: pinterestVariants(srcUrl), filename: filenameFromUrl(srcUrl) };
  try {
    // Режим «Спрашивать папку для сохранения»: сначала окно с выбором папки.
    const settings = await getSettings();
    if (settings.askFolder && tab && tab.id != null) {
      const asked = await askTabToChooseFolder(tab.id, image);
      if (asked) {
        await pluginLog('INFO', 'Открыто окно выбора папки (контекстное меню)');
        return;
      }
      // На странице нет контент-скрипта (chrome:// и т.п.) — сохраняем напрямую.
    }
    const res = await saveImageSmart(image);
    await notifyUser(res.target === 'hotfolder'
      ? 'Приложение закрыто — картинка сохранена в «Загрузки/Коробка»'
      : 'Картинка сохранена в Коробку');
  } catch (e) {
    await notifyUser(`Ошибка сохранения: ${e.message}`, true);
  }
});

/** Попросить страницу показать окно выбора папки. false — если не удалось. */
async function askTabToChooseFolder(tabId, image) {
  try {
    const resp = await chrome.tabs.sendMessage(tabId, { type: 'askSave', image });
    return !!(resp && resp.ok);
  } catch (e) {
    return false;
  }
}

function filenameFromUrl(u) {
  try {
    const p = new URL(u).pathname.split('/').pop();
    return p && /\.[a-z0-9]{2,5}$/i.test(p) ? decodeURIComponent(p) : '';
  } catch (e) { return ''; }
}

/**
 * Pinterest отдаёт превью фиксированного размера
 * (…/236x/…, …/474x/…, …/736x/…). Оригинал лежит в …/originals/….
 * Возвращаем варианты от лучшего к худшему.
 */
function pinterestVariants(url) {
  const variants = [];
  const m = url.match(/^(https?:\/\/i\.pinimg\.com\/)(?:\d+x|originals)(\/.+)$/i);
  if (m) {
    variants.push(`${m[1]}originals${m[2]}`);
    variants.push(`${m[1]}736x${m[2]}`);
    variants.push(`${m[1]}564x${m[2]}`);
  }
  return variants.filter((v) => v !== url);
}

// ───────────────────── УВЕДОМЛЕНИЯ ─────────────────────

async function notifyUser(message, isError = false) {
  try {
    await chrome.notifications.create({
      type: 'basic',
      iconUrl: 'icons/icon128.png',
      title: 'Коробка',
      message,
      silent: !isError,
    });
  } catch (e) { /* уведомления могут быть запрещены — не критично */ }
}

// ───────────────────── ПЛАВАЮЩЕЕ ОКНО ПЕРЕТАСКИВАНИЯ ─────────────────────

const DRAG_WIN_W = 470;
const DRAG_WIN_H = 300;

/** Показать (или передвинуть) окно приёма файлов рядом с курсором.
 * Гейт по настройкам делает контент-скрипт — здесь не фильтруем,
 * чтобы режим «Спрашивать папку» работал и при выключенном dragWindow. */
async function showDragWindow(screenX, screenY) {
  const settings = await getSettings();
  if (settings.dragWindow === false && settings.askFolder !== true) return;

  const left = Math.max(0, Math.round(screenX - DRAG_WIN_W / 2));
  const top = Math.max(0, Math.round(screenY + 24));

  try {
    if (dragWindowId !== null) {
      await chrome.windows.get(dragWindowId);
      await chrome.windows.update(dragWindowId, { left, top, drawAttention: false });
      return;
    }
  } catch (e) {
    dragWindowId = null; // окно уже закрыто пользователем
  }

  try {
    const win = await chrome.windows.create({
      url: 'drag.html',
      type: 'popup',
      width: DRAG_WIN_W,
      height: DRAG_WIN_H,
      left,
      top,
      focused: false, // не отбираем фокус во время перетаскивания
    });
    dragWindowId = win.id;
  } catch (e) {
    await pluginLog('WARN', `Не удалось открыть окно перетаскивания: ${e.message}`);
  }
}

/** Закрыть окно приёма файлов, если через него не сохраняют прямо сейчас.
 * Закрытие отложенное: бросок из Проводника летит в окно уже ПОСЛЕ того,
 * как курсор покинул страницу, поэтому закрываем с задержкой и только
 * если за это время в окне ничего не появилось и ничего не сохранили. */
function closeDragWindowIfIdle() {
  if (Date.now() - lastWindowSaveAt < 3000) return; // сохранение через окно — не мешаем
  if (windowHasPending) return; // в окне ждёт выбора папки файл
  if (idleCloseTimer) return;
  idleCloseTimer = setTimeout(() => {
    idleCloseTimer = null;
    if (Date.now() - lastWindowSaveAt < 3000) return;
    if (windowHasPending) return;
    closeDragWindow();
  }, 2500); // хватает времени донести файл из Проводника до окна
}

async function closeDragWindow() {
  if (dragWindowId === null) return;
  try {
    await chrome.windows.remove(dragWindowId);
  } catch (e) { /* уже закрыто */ }
  dragWindowId = null;
}

chrome.windows.onRemoved.addListener((wid) => {
  if (wid === dragWindowId) dragWindowId = null;
});

// ───────────────────── ОБРАБОТЧИК СООБЩЕНИЙ ─────────────────────

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  (async () => {
    try {
      switch (msg && msg.type) {
        case 'ping': {
          const app = await findApp();
          sendResponse({ ok: !!app, port: app ? app.port : null, version: app ? app.version : null });
          break;
        }
        case 'getFolders': {
          const folders = await apiGetFolders();
          sendResponse({ ok: true, folders });
          break;
        }
        case 'createFolder': {
          const data = await apiCreateFolder(String(msg.name || '').trim(), msg.parentId ?? null);
          try { await apiGetFolders(); } catch (e) { /* обновим кэш при случае */ }
          sendResponse({ ok: true, folder: data });
          break;
        }
        case 'saveImage': {
          const image = msg.image || {};
          if (!image.url && !image.base64) {
            sendResponse({ ok: false, error: 'Нет данных картинки' });
            break;
          }
          if (!image.altUrls && image.url) image.altUrls = pinterestVariants(image.url);
          const res = await saveImageSmart(image, msg.folderId);
          await pluginLog('INFO', `Сохранено (${res.target === 'hotfolder' ? 'горячая папка' : 'сервер'})`);
          sendResponse({ ok: true, target: res.target, data: res.data });
          break;
        }
        case 'getSettings': {
          sendResponse({ ok: true, settings: await getSettings() });
          break;
        }
        case 'setSettings': {
          await patchSettings(msg.patch || {});
          sendResponse({ ok: true });
          break;
        }
        case 'log': {
          await pluginLog((msg.level || 'INFO').toUpperCase(), msg.message || '');
          sendResponse({ ok: true });
          break;
        }
        case 'dragStart': {
          await showDragWindow(msg.x || 0, msg.y || 0);
          sendResponse({ ok: true });
          break;
        }
        case 'dragEnded': {
          closeDragWindowIfIdle();
          sendResponse({ ok: true });
          break;
        }
        case 'dragSaved': {
          lastWindowSaveAt = Date.now();
          sendResponse({ ok: true });
          break;
        }
        case 'windowDrop': {
          // В окно приёма файлов что-то бросили — не закрывать его.
          lastWindowSaveAt = Date.now();
          sendResponse({ ok: true });
          break;
        }
        case 'windowPending': {
          windowHasPending = !!msg.value;
          sendResponse({ ok: true });
          break;
        }
        default:
          sendResponse({ ok: false, error: `Неизвестная команда: ${msg && msg.type}` });
      }
    } catch (e) {
      sendResponse({ ok: false, error: e.message || String(e), code: e.code || null });
    }
  })();
  return true; // асинхронный ответ
});
