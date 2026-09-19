/**
 * Коробка: без сервера информация о библиотеках недоступна.
 * Заглушка возвращает безопасные значения по умолчанию.
 */
class Library {
	async info() {
		return { library: { path: "" }, libraries: [], path: "" };
	}
	async history() {
		return [];
	}
	async switch(a) {
		return "success";
	}
	normalizePath(a) {
		return a;
	}
	switchPromise(l) {
		return Promise.resolve();
	}
}

eagle.library = new Library;
