/**
 * Коробка — фоновый модуль сохранения (service worker).
 *
 * Порядок сохранения:
 *  1. Приложение «Коробка» запущено → POST /api/item/add — файл попадает
 *     прямо в коллекцию (в выбранную папку). URL-варианты пробуются по
 *     очереди (для Pinterest сначала …/originals/…), при неудаче — base64.
 *  2. Приложение закрыто (или сервер не смог скачать) → запасной путь:
 *     chrome.downloads в «Загрузки/Коробка[/Папка]» — приложение само
 *     подхватит файлы из горячей папки при следующем запуске.
 *
 * Сообщения, которые обрабатывает этот класс (только в service worker):
 *  - "korobka-save"          — сохранить файл {url, dataUrl, mime, title,
 *                              pageUrl, type, folderID, folderName}
 *  - "korobka-ping"          — найти приложение {ok, port, version}
 */
class KorobkaSaver {
	#listenerMap = null;

	/** Подпапка внутри «Загрузки» (запасной путь). */
	static FOLDER_NAME = "Коробка";

	/** Локальные порты приложения. */
	static PORTS = [41595, 41596, 41597];

	/** Белый список расширений (всё, что умеет приложение). */
	static EXT_WHITELIST = new Set([
		"jpg", "jpeg", "png", "gif", "svg", "webp", "avif", "bmp", "tif", "tiff", "ico",
		"mp4", "webm", "mov", "m4v", "avi", "mkv", "wmv", "flv",
		"mp3", "wav", "flac", "ogg", "m4a", "aac", "wma", "opus",
	]);

	/** MIME → расширение. */
	static MIME_EXT_MAP = {
		"image/jpeg": "jpg", "image/jpg": "jpg", "image/pjpeg": "jpg",
		"image/png": "png", "image/apng": "png",
		"image/gif": "gif", "image/webp": "webp", "image/avif": "avif",
		"image/svg+xml": "svg", "image/bmp": "bmp", "image/x-icon": "ico",
		"image/tiff": "tif",
		"video/mp4": "mp4", "video/webm": "webm", "video/quicktime": "mov",
		"video/x-msvideo": "avi", "video/x-matroska": "mkv",
		"audio/mpeg": "mp3", "audio/wav": "wav", "audio/x-wav": "wav",
		"audio/ogg": "ogg", "audio/flac": "flac", "audio/mp4": "m4a",
		"audio/aac": "aac",
	};

	#activePort = 0;
	#portCheckedAt = 0;
	#logQueue = [];
	#logTimer = null;

	constructor() {
		eagle.runtime.onMessage("korobka-save", (msg, sender, sendResponse) => {
			this.save(msg || {})
				.then((result) => sendResponse(result))
				.catch((error) => sendResponse({ ok: false, error: String(error && error.message || error) }));
			return !0;
		});
		eagle.runtime.onMessage("korobka-ping", (msg, sender, sendResponse) => {
			this.#findApp()
				.then((app) => sendResponse({ ok: !!app, port: app ? app.port : null, version: app ? app.version : null }))
				.catch(() => sendResponse({ ok: false }));
			return !0;
		});
	}

	// ─────────────────────── ГЛАВНАЯ ТОЧКА ВХОДА ───────────────────────

	/**
	 * msg: {url, dataUrl?, mime?, title?, pageUrl?, type?, folderID?, folderName?}
	 * Возвращает {ok:true, via:"app"|"download", filename?} либо {ok:false, error}.
	 */
	async save(msg) {
		try {
			const image = this.#buildImage(msg);

			if (!image.url && !image.base64) {
				return { ok: !1, error: "нечего сохранять: нет URL и данных картинки" };
			}

			// Попытка 1: приложение запущено — сохраняем напрямую в коллекцию.
			const app = await this.#findApp();
			if (app) {
				try {
					const data = await this.#apiAddItem(image, msg.folderID);
					await this.#pluginLog("INFO", `Сохранено в коллекцию (${image.altUrls && image.altUrls.length ? "вариант URL" : "URL"})`);
					return { ok: !0, via: "app", data };
				} catch (e) {
					await this.#pluginLog("WARN", `Сервер: ${e && e.message}`);
					// если и base64 не сработал — падаем в горячую папку
				}
			}

			// Попытка 2: горячая папка «Загрузки/Коробка» (работает и без приложения).
			const res = await this.#downloadToHotFolder(image, msg);
			await this.#pluginLog("INFO", `Файл сохранён в горячую папку (${res.filename})`);
			return { ok: !0, via: "download", filename: res.filename };
		} catch (e) {
			return { ok: !1, error: String(e && e.message || e) };
		}
	}

	/** Собирает объект картинки: url + pinterest-варианты + base64. */
	#buildImage(msg) {
		let url = msg.url || "";
		if (url && url.startsWith("blob:") && msg.dataUrl) url = msg.dataUrl;

		const image = {
			url: /^https?:/i.test(url) ? url : "",
			altUrls: [],
			base64: "",
			mime: msg.mime || "",
			filename: msg.filename || "",
		};

		if (!image.url && url.startsWith("data:")) {
			const m = /^data:([^;,]*);?base64,(.*)$/s.exec(url);
			if (m) {
				image.mime = image.mime || m[1] || "image/png";
				image.base64 = m[2];
			}
		} else if (!image.url && msg.dataUrl && msg.dataUrl.startsWith("data:")) {
			const m = /^data:([^;,]*);?base64,(.*)$/s.exec(msg.dataUrl);
			if (m) {
				image.mime = image.mime || m[1] || "image/png";
				image.base64 = m[2];
			}
		}

		if (image.url) {
			image.altUrls = this.pinterestVariants(image.url);
			if (!image.filename) image.filename = this.#filenameFromUrl(image.url);
		}
		return image;
	}

	// ─────────────────────── API ПРИЛОЖЕНИЯ ───────────────────────

	/** Поиск приложения (кэш порта на 3 секунды). */
	async #findApp() {
		const now = Date.now();
		if (this.#activePort > 0 && now - this.#portCheckedAt < 3000) {
			return { port: this.#activePort, version: "?" };
		}
		if (this.#activePort > 0 && await this.#pingPort(this.#activePort)) {
			this.#portCheckedAt = now;
			return this.#activePort;
		}
		this.#activePort = 0;
		for (const port of KorobkaSaver.PORTS) {
			const ok = await this.#pingPort(port);
			if (ok) {
				this.#activePort = port;
				this.#portCheckedAt = Date.now();
				return ok;
			}
		}
		return null;
	}

	/** Пинг конкретного порта: {status:"success", data:{name:"korobka"}}. */
	async #pingPort(port) {
		try {
			const resp = await this.#fetchWithTimeout(`http://127.0.0.1:${port}/api/ping`, { method: "GET", cache: "no-store" }, 1200);
			if (!resp.ok) return null;
			const json = await resp.json().catch(() => null);
			if (json && "success" === json.status && json.data && "korobka" === json.data.name) {
				return { port, version: json.data.version || "?" };
			}
			return null;
		} catch (e) {
			return null;
		}
	}

	/**
	 * POST /api/item/add. URL-варианты по очереди (Pinterest originals
	 * первым), затем base64. Возвращает data успешного ответа.
	 */
	async #apiAddItem(image, folderIdRaw) {
		// id может прийти строкой из HTML-атрибутов панели — нормализуем к числу.
		let folderId = null;
		if (void 0 !== folderIdRaw && null !== folderIdRaw && "" !== folderIdRaw) {
			folderId = /^\d+$/.test(String(folderIdRaw)) ? Number(folderIdRaw) : folderIdRaw;
		}
		const urls = [image.url, ...image.altUrls].filter(Boolean);

		for (const url of urls) {
			try {
				const resp = await this.#fetchWithTimeout(
					`http://127.0.0.1:${this.#activePort}/api/item/add`,
					{
						method: "POST",
						headers: { "Content-Type": "application/json" },
						body: JSON.stringify({ url, folderId }),
					},
					60000,
				);
				const json = await resp.json().catch(() => null);
				if (resp.ok && json && "success" === json.status) return json.data;
				await this.#pluginLog("WARN", `Не удалось сохранить по URL (${this.#shortUrl(url)}): ${json && json.message}`);
			} catch (e) {
				await this.#pluginLog("WARN", `Ошибка запроса к приложению (${this.#shortUrl(url)}): ${e && e.message}`);
			}
		}

		if (image.base64) {
			const resp = await this.#fetchWithTimeout(
				`http://127.0.0.1:${this.#activePort}/api/item/add`,
				{
					method: "POST",
					headers: { "Content-Type": "application/json" },
					body: JSON.stringify({ base64: image.base64, mime: image.mime || "", filename: image.filename || "", folderId }),
				},
				60000,
			);
			const json = await resp.json().catch(() => null);
			if (resp.ok && json && "success" === json.status) return json.data;
			throw new Error(json && json.message || `HTTP ${resp.status}`);
		}

		throw new Error("приложение не смогло скачать картинку по всем вариантам ссылки");
	}

	// ─────────────────── ЗАПАСНОЙ ПУТЬ: ГОРЯЧАЯ ПАПКА ───────────────────

	async #downloadToHotFolder(image, msg) {
		if (!chrome?.downloads?.download) {
			throw new Error("chrome.downloads недоступен");
		}

		// Имя подпапки: из выбранной папки приложения (для порядка в очереди).
		let sub = this.sanitize(msg.folderName || "");
		if (!sub && null != msg.folderID && "" !== msg.folderID) {
			sub = await this.#folderNameById(msg.folderID);
		}

		const ext = this.#resolveExt(image, msg);
		const name = this.buildFilename(msg.title, msg.pageUrl, ext);
		const filename = sub ? `${KorobkaSaver.FOLDER_NAME}/${sub}/${name}` : `${KorobkaSaver.FOLDER_NAME}/${name}`;

		let source = image.url || "";
		if (!source && image.base64) {
			source = `data:${image.mime || "image/jpeg"};base64,${image.base64}`;
		}
		if (!source) throw new Error("нечего сохранять: нет URL и данных картинки");

		const downloadId = await chrome.downloads.download({
			url: source,
			filename,
			conflictAction: "uniquify",
			saveAs: !1,
		});
		if ("number" != typeof downloadId) {
			throw new Error("браузер отклонил загрузку");
		}
		return { filename, downloadId };
	}

	async #folderNameById(id) {
		try {
			const folders = await eagle.folder.all();
			const f = (folders || []).find((x) => String(x.id) === String(id));
			return f ? this.sanitize(f.name) : "";
		} catch (e) {
			return "";
		}
	}

	/** Определение расширения файла. */
	#resolveExt(image, msg) {
		let mime = image.mime || msg.mime;
		if (!mime && image.url && image.url.startsWith("data:")) {
			const m = /^data:([^;,]+)/.exec(image.url);
			if (m) mime = m[1];
		}
		if (mime && KorobkaSaver.MIME_EXT_MAP[mime.toLowerCase()]) {
			return KorobkaSaver.MIME_EXT_MAP[mime.toLowerCase()];
		}
		const fromUrl = this.#extFromUrlPath(image.url || msg.url || "");
		if (fromUrl) return fromUrl;
		if ("video" === msg.type) return "mp4";
		if ("audio" === msg.type) return "mp3";
		return "";
	}

	#extFromUrlPath(url) {
		if (!url || url.startsWith("data:") || url.startsWith("blob:")) return "";
		try {
			let pathname = url;
			try { pathname = new URL(url).pathname; } catch (e) { /* относительный — берём как есть */ }
			const name = pathname.split("/").pop() || "";
			const dot = name.lastIndexOf(".");
			if (dot < 0) return "";
			const ext = name.slice(dot + 1).toLowerCase().slice(0, 5);
			return /^[a-z0-9]+$/.test(ext) && KorobkaSaver.EXT_WHITELIST.has(ext) ? ext : "";
		} catch (e) {
			return "";
		}
	}

	/** Имя файла: «Имя.ext» (подпапку добавляет #downloadToHotFolder). */
	buildFilename(title, pageUrl, ext) {
		let name = title || "";
		if (!name) {
			try { name = new URL(pageUrl).hostname; } catch (e) { name = ""; }
		}
		name = this.sanitize(name) || "image";
		return `${name}${ext ? "." + ext : ""}`;
	}

	/** Очистка имени от запрещённых символов Windows/Chrome. */
	sanitize(str) {
		return String(str == null ? "" : str)
			.replace(/[\u0000-\u001F\u007F]/g, " ")
			.replace(/[\\/:*?"<>|]/g, " ")
			.replace(/\s+/g, " ")
			.replace(/^[\s.]+|[\s.]+$/g, "")
			.slice(0, 80)
			.trim();
	}

	#filenameFromUrl(u) {
		try {
			const p = new URL(u).pathname.split("/").pop();
			return p && /\.[a-z0-9]{2,5}$/i.test(p) ? decodeURIComponent(p) : "";
		} catch (e) {
			return "";
		}
	}

	/**
	 * Pinterest отдаёт превью фиксированного размера
	 * (…/236x/…, …/474x/…, …/736x/…). Оригинал лежит в …/originals/….
	 * Возвращаем варианты от лучшего к худшему.
	 */
	pinterestVariants(url) {
		const variants = [];
		const m = String(url || "").match(/^(https?:\/\/i\.pinimg\.com\/)(?:\d+x|originals)(\/.+)$/i);
		if (m) {
			variants.push(`${m[1]}originals${m[2]}`);
			variants.push(`${m[1]}736x${m[2]}`);
			variants.push(`${m[1]}564x${m[2]}`);
		}
		return variants.filter((v) => v !== url);
	}

	// ───────────────────── ЖУРНАЛ (общий с приложением) ─────────────────────

	async #pluginLog(level, message) {
		const entry = { level, descriptor: message, ts: Date.now() };
		this.#logQueue.push(entry);
		if (this.#logQueue.length > 200) this.#logQueue = this.#logQueue.slice(-200);
		if (!this.#logTimer) this.#logTimer = setTimeout(() => this.#flushLogs(), 2000);
	}

	async #flushLogs() {
		this.#logTimer = null;
		if (0 === this.#logQueue.length) return;
		const batch = this.#logQueue.splice(0, this.#logQueue.length);
		if (!(this.#activePort > 0)) return; // приложение недоступно — журнал остаётся локально
		for (const entry of batch) {
			try {
				await this.#fetchWithTimeout(
					`http://127.0.0.1:${this.#activePort}/api/log`,
					{
						method: "POST",
						headers: { "Content-Type": "application/json" },
						body: JSON.stringify({ level: entry.level, descriptor: entry.descriptor }),
					},
					1500,
				);
			} catch (e) { /* молча — журнал не критичен */ }
		}
	}

	// ─────────────────────────── УТИЛИТЫ ───────────────────────────

	async #fetchWithTimeout(url, options, ms) {
		const ctrl = new AbortController();
		const timer = setTimeout(() => ctrl.abort(), ms);
		try {
			return await fetch(url, { ...options, signal: ctrl.signal });
		} finally {
			clearTimeout(timer);
		}
	}

	#shortUrl(u) {
		try {
			const url = new URL(u);
			return url.pathname.split("/").pop() || url.hostname;
		} catch (e) {
			return String(u).slice(0, 60);
		}
	}
}

/* Класс работает только в service worker'е (в страницах расширения есть window). */
var korobkaSaver = "undefined" == typeof window ? new KorobkaSaver : null;
