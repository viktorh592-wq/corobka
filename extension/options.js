/**
 * Коробка — страница настроек.
 *
 * Исправления v0.4.0: страница больше не падает с ошибкой (раньше
 * неинициализированные настройки вызывали сбой и «ошибка» в настройках —
 * скрин 3). Все значения читаются с запасными значениями по умолчанию,
 * каждая ошибка соединения показывается понятным текстом.
 */

'use strict';

const els = {
  testConn: document.getElementById('test-conn'),
  connResult: document.getElementById('conn-result'),
  defaultFolder: document.getElementById('default-folder'),
  reloadFolders: document.getElementById('reload-folders'),
  folderStatus: document.getElementById('folder-status'),
  overlayEnabled: document.getElementById('overlay-enabled'),
  saveToast: document.getElementById('save-toast'),
  saveMode: document.getElementById('save-mode'),
};

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

function setConnResult(text, kind) {
  els.connResult.textContent = text;
  els.connResult.className = 'conn-result' + (kind ? ` conn-result--${kind}` : '');
}

// ─────────────────────────── ПРОВЕРКА СВЯЗИ ───────────────────────────

async function testConnection() {
  els.testConn.disabled = true;
  setConnResult('Проверяю…', 'busy');
  const res = await sendMessage({ type: 'ping' });
  els.testConn.disabled = false;
  if (res.ok) {
    setConnResult(`✓ Приложение запущено — порт ${res.port}, версия ${res.version || '?'}`, 'ok');
  } else {
    setConnResult('✗ Приложение не найдено. Запустите «Коробку» на этом компьютере.', 'err');
  }
}

// ─────────────────────────── ПАПКИ ───────────────────────────

async function loadFolders() {
  els.folderStatus.textContent = 'Загружаю папки из приложения…';
  const res = await sendMessage({ type: 'getFolders' });
  if (!res.ok) {
    els.folderStatus.textContent = 'Не удалось загрузить папки: приложение не запущено.';
    return;
  }
  const folders = Array.isArray(res.folders) ? res.folders : [];
  const current = els.defaultFolder.value;

  els.defaultFolder.innerHTML = '';
  const rootOpt = document.createElement('option');
  rootOpt.value = '';
  rootOpt.textContent = 'Все картинки (корень)';
  els.defaultFolder.appendChild(rootOpt);
  for (const f of folders) {
    const opt = document.createElement('option');
    opt.value = String(f.id);
    opt.textContent = f.name;
    els.defaultFolder.appendChild(opt);
  }
  // Восстанавливаем прежний выбор, если папка ещё существует.
  if ([...els.defaultFolder.options].some((o) => o.value === current)) {
    els.defaultFolder.value = current;
  }
  els.folderStatus.textContent =
    folders.length > 0
      ? `В приложении ${folders.length} пап(ок/а). Список актуален.`
      : 'В приложении пока нет папок — создайте их в «Коробке» или во всплывающем окне.';
}

// ─────────────────────────── ЗАГРУЗКА/СОХРАНЕНИЕ ───────────────────────────

async function loadSettings() {
  const res = await sendMessage({ type: 'getSettings' });
  const s = res.ok && res.settings ? res.settings : {};
  // Все поля с запасными значениями — страница не должна падать никогда.
  els.overlayEnabled.checked = s.overlayEnabled !== false;
  els.saveToast.checked = s.saveToast !== false;
  els.saveMode.value = ['auto', 'server', 'hotfolder'].includes(s.saveMode) ? s.saveMode : 'auto';
  els.defaultFolder.value = s.defaultFolderId != null ? String(s.defaultFolderId) : '';
}

async function saveSetting(patch) {
  await sendMessage({ type: 'setSettings', patch });
}

// ─────────────────────────── СТАРТ ───────────────────────────

async function init() {
  els.testConn.addEventListener('click', testConnection);
  els.reloadFolders.addEventListener('click', loadFolders);
  els.defaultFolder.addEventListener('change', () => {
    const raw = els.defaultFolder.value;
    saveSetting({ defaultFolderId: raw === '' ? null : Number(raw) });
  });
  els.overlayEnabled.addEventListener('change', () => {
    saveSetting({ overlayEnabled: els.overlayEnabled.checked });
  });
  els.saveToast.addEventListener('change', () => {
    saveSetting({ saveToast: els.saveToast.checked });
  });
  els.saveMode.addEventListener('change', () => {
    saveSetting({ saveMode: els.saveMode.value });
  });

  await loadSettings();
  await loadFolders();
}

init();
