/**
 * Коробка — сохранение элементов.
 *
 * Все способы сохранения (перетаскивание, контекстное меню, скриншоты,
 * пакетное сохранение, сохранение страницы) идут через chrome.downloads
 * в папку «Загрузки/Коробка». Никакой сервер не нужен: приложение
 * Коробка само подхватывает файлы из этой папки.
 */
class Item {
        /** Отправка задания на сохранение в фоновый service worker. */
        async #send(item) {
                const payload = {
                        url: item.src,
                        title: item.title,
                        pageUrl: item.url || (typeof location !== "undefined" ? location.href : ""),
                        type: item.elementType || "image",
                        // Папка приложения: id выбранной папки (панель выбора папки,
                        // окно перетаскивания, пакетное сохранение) — файл попадёт
                        // прямо в коллекцию приложения. folderName — запасное имя
                        // подпапки для режима горячей папки (когда приложение закрыто).
                        folderID: item.folderID ?? (Array.isArray(item.folderIDs) && item.folderIDs.length ? item.folderIDs[0] : null),
                        folderName: item.folderName || "",
                        // Коробка v0.6: комментарий и теги из окна сохранения —
                        // попадают в приложение (поле «Комментарий» элемента).
                        annotation: typeof item.annotation === "string" ? item.annotation.trim().slice(0, 2000) : "",
                        tags: Array.isArray(item.tags) ? item.tags.map((t) => String(t).trim()).filter(Boolean).slice(0, 30) : [],
                };

                // data:URL отдаём через blob (надёжно для больших файлов),
                // а сам data:URL вкладываем как резервный вариант.
                let blobUrl = null;
                if (item.src && item.src.startsWith("data:")) {
                        const m = /^data:([^;,]+)/.exec(item.src);
                        m && (payload.mime = m[1]);
                        blobUrl = await this.#toBlobUrl(item.src);
                        if (blobUrl) {
                                payload.url = blobUrl;
                                payload.dataUrl = item.src.length < 8e6 ? item.src : void 0;
                        }
                }

                let response;
                try {
                        response = await eagle.runtime.sendMessage("korobka-save", payload);
                } catch (e) {
                        response = { ok: !1, error: String(e && e.message || e) };
                }

                if (blobUrl) setTimeout(() => { try { URL.revokeObjectURL(blobUrl); } catch (e) {} }, 3e4);
                return response || { ok: !1, error: "нет ответа от фонового процесса" };
        }

        /** data:URL → blob:URL (в контексте страницы createObjectURL доступен). */
        async #toBlobUrl(dataUrl) {
                try {
                        const blob = await (await fetch(dataUrl)).blob();
                        return URL.createObjectURL(blob);
                } catch (e) {
                        return null;
                }
        }

        /** Плашка на странице о результате сохранения. */
        #toast(ok, error) {
                try {
                        // В страницах самого расширения плашка не нужна
                        if (typeof location !== "undefined" && "chrome-extension:" === location.protocol) return;
                        if (!document.body) return;
                        const theme = eagle.preference.displayTheme;
                        let el = document.getElementById("korobka-toast");
                        if (!el) {
                                el = document.createElement("div");
                                el.id = "korobka-toast";
                                el.setAttribute("translate", "no");
                                document.body.appendChild(el);
                        }
                        el.textContent = ok
                                ? (eagle.i18n.words["saver.saved"] || "Сохранено в Коробку")
                                : (eagle.i18n.words["saver.error"] || "Не удалось сохранить") + (error ? ` (${error})` : "");
                        el.setAttribute("data-result", ok ? "ok" : "error");
                        el.setAttribute("data-theme", theme);
                        el.classList.add("visible");
                        clearTimeout(this.#toastTimer);
                        this.#toastTimer = setTimeout(() => el.classList.remove("visible"), 2600);
                } catch (e) {}
        }

        #toastTimer = null;

        /** Сохранение одного элемента (drag&drop, контекстное меню, скриншоты). */
        async addFile(a) {
                a.title && (a.title = eagle.utils.clearWeirdCharactersAndAvoidLongFileName(a.title));
                a.tags && (a.tags = a.tags.map(e => e.trim()).filter(e => e));
                const result = await this.#send(a);
                this.#toast(result.ok, result.error);
                return result;
        }

        /** Совместимость с пакетным сохранением — то же, что addFile. */
        async addBatchSaveFile(a) {
                return this.addFile(a);
        }

        /** Скриншоты (область/страница/полная прокрутка). */
        async addScreenshot({ base64: e, indexStr: t = "" }) {
                t = eagle.utils.clearWeirdCharactersAndAvoidLongFileName(document.title) + t;
                const result = await this.#send({ src: e, title: t, url: location.href, type: "image" });
                this.#toast(result.ok, result.error);
                return result;
        }

        /** Сохранение страницы (скриншот страницы или превью видео). */
        async addURL(e) {
                var t = eagle.utils.clearWeirdCharactersAndAvoidLongFileName(document.title);
                let base64;
                if (e.videoThumb) {
                        base64 = await eagle.utils.urlToBase64(e.videoThumb, 1e4);
                } else {
                        base64 = await eagle.screenCapturer.captureCurrentTab({ format: "jpeg", quality: 85 });
                        if (base64) {
                                const r = await eagle.utils.resizeBase64ImageToMaxSize(e.src || base64, 720);
                                base64 = r["base64"] || base64;
                        }
                }
                if (!base64) return { ok: !1, error: "не удалось сделать скриншот" };
                const result = await this.#send({ src: base64, title: t, url: location.href, type: "image" });
                this.#toast(result.ok, result.error);
                return result;
        }

        /** Пакетное сохранение всех найденных картинок. */
        async batchSave(e) {
                e.forEach(e => {
                        e.title || (e.title = document.title);
                        e.title = eagle.utils.clearWeirdCharactersAndAvoidLongFileName(e.title);
                        e.src && -1 < e.src.indexOf(" ") && (e.src = e.src.trim().split(" ")[0]);
                });
                eagle.logger.info(`[background] batch save[${location.href}] count[${e.length}]`);

                let okCount = 0;
                for (const img of e) {
                        if (!img.src) continue;
                        try {
                                const r = await this.#send({ ...img, type: img.elementType || "image" });
                                r.ok && okCount++;
                        } catch (err) {}
                        await new Promise(r => setTimeout(r, 120));
                }

                const all = okCount === e.length;
                this.#toast(okCount > 0, null);
                return { ok: 0 < okCount, saved: okCount, total: e.length, all };
        }
}

eagle.item = new Item;
