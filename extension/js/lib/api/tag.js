/**
 * Коробка: без сервера теги приложения недоступны — пустые списки.
 */
class Tag {
	async recent() {
		return [];
	}
	async all() {
		return [];
	}
	async list() {
		return [];
	}
}

eagle.tag = new Tag;
