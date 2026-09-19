/**
 * Коробка: папки приложения через локальный HTTP-сервер.
 *
 * Приложение «Коробка» поднимает локальный сервер на 127.0.0.1
 * (порты перебираются: 41595 → 41596 → 41597 — как в Eagle).
 *
 * Все HTTP-запросы выполняет фоновый service worker (у него есть
 * host_permissions и нет ограничений CORS). Контент-скрипты и страницы
 * расширения (попап, collect-window, batch-saver) получают список папок
 * и создают папки через chrome.runtime.sendMessage.
 *
 * Если приложение не запущено, возвращается пустой список —
 * интерфейс показывает «нет папок», а сохранение всё равно работает
 * (файлы попадают в «Загрузки/Коробка» через горячую папку).
 */
class Folder {
        /** Порты локального сервера приложения. */
        static PORTS = [41595, 41596, 41597];

        /** Время жизни кэша списка папок / «приложение закрыто», мс. */
        static CACHE_TTL = 3000;

        #cachedPort = 0;
        #portCheckedAt = 0;
        #foldersCache = null;
        #foldersCacheAt = 0;

        /** true только внутри service worker'а (в страницах расширения есть window). */
        static #isServiceWorker() {
                return "undefined" == typeof window && "undefined" != typeof importScripts;
        }

        constructor() {
                if (Folder.#isServiceWorker()) {
                        eagle.runtime.onMessage("korobka-folders", (msg, sender, sendResponse) => {
                                this.#fetchFolders()
                                        .then((folders) => sendResponse({ ok: true, folders }))
                                        .catch((error) => sendResponse({ ok: false, error: String(error && error.message || error) }));
                                return !0;
                        });
                        eagle.runtime.onMessage("korobka-folder-create", (msg, sender, sendResponse) => {
                                this.#apiCreateFolder(msg && msg.name, msg && msg.parentId)
                                        .then((folder) => sendResponse({ ok: true, folder }))
                                        .catch((error) => sendResponse({ ok: false, error: String(error && error.message || error) }));
                                return !0;
                        });
                        eagle.runtime.onMessage("korobka-folder-names", (msg, sender, sendResponse) => {
                                // {id: name} — фоновой сохран кладёт файл в подпапку горячей папки.
                                this.#fetchFolders()
                                        .then((folders) => {
                                                const map = {};
                                                (folders || []).forEach((f) => { map[String(f.id)] = f.name; });
                                                sendResponse({ ok: true, names: map });
                                        })
                                        .catch(() => sendResponse({ ok: true, names: {} }));
                                return !0;
                        });
                }
        }

        /** Последние папки (для окна перетаскивания, до 16 штук). */
        async recent() {
                const folders = await this.#fetchFolders();
                return folders.slice(0, 16).map((f) => this.#toDragItem(f));
        }

        /** Все папки коллекции (для панели выбора папки). */
        async all() {
                const folders = await this.#fetchFolders();
                return folders.map((f) => this.#toDragItem(f));
        }

        /** Создание папки в приложении (POST /api/folder/create). */
        async create(name, parent = void 0) {
                name = String(name == null ? "" : name).trim();
                if (!name) return null;
                let folder;
                if (Folder.#isServiceWorker()) {
                        folder = await this.#apiCreateFolder(name, parent ?? null);
                } else {
                        const resp = await eagle.runtime.sendMessage("korobka-folder-create", { name, parentId: parent ?? null });
                        if (!resp || !resp.ok) throw new Error(resp && resp.error || "не удалось создать папку");
                        folder = resp.folder;
                }
                // Обновим кэш, чтобы новая папка сразу появилась в списках.
                this.#foldersCache = null;
                this.#foldersCacheAt = 0;
                return this.#toDragItem(folder || { id: null, name });
        }

        /** Формат для drag-saver/панели папок: {id, name, icon, iconColor, extendTags}. */
        #toDragItem(f) {
                return {
                        id: f.id,
                        name: f.name,
                        icon: "folder",
                        // Цвет папки из настроек приложения (HEX без решётки) или
                        // стандартный чёрный — drag-saver подставит класс/стиль.
                        iconColor: (f.color && /^[0-9a-fA-F]{6}$/.test(f.color)) ? f.color : "black",
                        extendTags: [],
                };
        }

        /** Список папок с кэшем на Folder.CACHE_TTL. */
        async #fetchFolders() {
                // Контент-скрипты и страницы расширения спрашивают service worker —
                // только у него есть host_permissions для запросов к 127.0.0.1.
                if (!Folder.#isServiceWorker()) {
                        try {
                                const resp = await eagle.runtime.sendMessage("korobka-folders");
                                return resp && resp.ok && Array.isArray(resp.folders) ? resp.folders : [];
                        } catch (e) {
                                return [];
                        }
                }
                const now = Date.now();
                if (this.#foldersCache && now - this.#foldersCacheAt < Folder.CACHE_TTL) {
                        return this.#foldersCache;
                }
                const folders = await this.#request("GET", "/api/folder/list", null, 2500)
                        .then((json) => Array.isArray(json && json.data) ? json.data.filter((f) => f && f.id != null && f.name) : [])
                        .catch(() => []);
                this.#foldersCache = folders;
                this.#foldersCacheAt = Date.now();
                return folders;
        }

        /** Запрос к серверу приложения (с перебором портов и кэшем порта). */
        async #request(method, path, body, timeoutMs = 2500) {
                const port = await this.#findPort();
                if (!port) throw new Error("приложение «Коробка» не запущено");
                const url = `http://127.0.0.1:${port}${path}`;
                const options = { method, cache: "no-store" };
                if (void 0 !== body) {
                        options.headers = { "Content-Type": "application/json" };
                        options.body = JSON.stringify(body);
                }
                const res = await this.#fetchWithTimeout(url, options, timeoutMs);
                const json = await res.json().catch(() => null);
                if (!res.ok || !json || "success" !== json.status) {
                        throw new Error(json && json.message || `HTTP ${res.status}`);
                }
                return json;
        }

        /** Поиск порта приложения: сначала кэшированный, потом перебор. */
        async #findPort() {
                const now = Date.now();
                if (this.#cachedPort > 0 && now - this.#portCheckedAt < Folder.CACHE_TTL) {
                        return this.#cachedPort;
                }
                if (this.#cachedPort > 0 && await this.#tryPing(this.#cachedPort)) {
                        this.#portCheckedAt = Date.now();
                        return this.#cachedPort;
                }
                this.#cachedPort = 0;
                for (const port of Folder.PORTS) {
                        if (await this.#tryPing(port)) {
                                this.#cachedPort = port;
                                this.#portCheckedAt = Date.now();
                                return port;
                        }
                }
                return 0;
        }

        /** Пинг приложения на конкретном порту. */
        async #tryPing(port) {
                try {
                        const res = await this.#fetchWithTimeout(`http://127.0.0.1:${port}/api/ping`, { method: "GET", cache: "no-store" }, 1200);
                        if (!res || !res.ok) return !1;
                        const json = await res.json().catch(() => null);
                        // Коробка отвечает {status:"success", data:{name:"korobka", ...}}.
                        return !!(json && "success" === json.status && json.data && "korobka" === json.data.name);
                } catch (e) {
                        return !1;
                }
        }

        /** fetch с таймаутом (AbortController), чтобы не висеть на мёртвых портах. */
        async #fetchWithTimeout(url, options, ms) {
                const ctrl = new AbortController();
                const timer = setTimeout(() => ctrl.abort(), ms);
                try {
                        return await fetch(url, { ...options, signal: ctrl.signal });
                } finally {
                        clearTimeout(timer);
                }
        }

        /** Создание папки (выполняется только в service worker). */
        async #apiCreateFolder(name, parentId) {
                name = String(name == null ? "" : name).trim().slice(0, 100);
                if (!name) throw new Error("пустое имя папки");
                const json = await this.#request("POST", "/api/folder/create", { name, parentId: parentId ?? null }, 5000);
                this.#foldersCache = null;
                this.#foldersCacheAt = 0;
                return json.data || { id: null, name };
        }
}

eagle.folder = new Folder;
