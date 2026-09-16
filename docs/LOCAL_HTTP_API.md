# 🌐 Локальный HTTP-сервер «Коробки»

Начиная с версии **0.3.1** «Коробка» умеет принимать файлы от внешних
приложений — расширения браузера, скрипты, веб-интерфейсы, сторонние
десктоп-программы — через локальный HTTP-сервер. Это аналог **Eagle Browser
Extension API**: один POST-запрос, и файл появляется в коллекции без ручного
импорта через диалог.

## Принцип работы

* Сервер слушает только **`127.0.0.1`** (loopback) — извне, из интернета и
  из локальной сети, подключиться нельзя. Это безопасно по умолчанию.
* По умолчанию используется порт **`57323`** (как Eagle). Его можно сменить
  в настройках приложения (иконка шестерёнки → «Локальный HTTP-сервер»).
* Все запросы и ответы — **JSON** (`Content-Type: application/json`).
* На каждый ответ добавляются CORS-заголовки
  (`Access-Control-Allow-Origin: *`), поэтому запросы работают прямо из
  расширений браузера без прокси.
* Сервер не требует авторизации — он слушает только на локальном
  интерфейсе, и доступ к нему означает, что у пользователя уже есть доступ
  к машине.

## Включение

1. Откройте «Коробку».
2. В правом верхнем углу нажмите иконку **шестерёнки** (Настройки).
3. В разделе **«Локальный HTTP-сервер»** включите тумблер «Запущен».
4. При необходимости поменяйте порт и нажмите **«Применить»**.
5. В AppBar появится зелёная иконка `cloud_done` — сервер активен.
   Серый `cloud_off` — выключен.

Состояние сохраняется между запусками приложения: если сервер был включён,
он запустится автоматически при следующем старте.

## Эндпоинты

### `GET /api/health` (или `/api/heartbeat`, `/`)

Статус сервера и приложения.

**Ответ 200:**
```json
{
  "status": "ok",
  "app": "korobka",
  "version": "0.3.0",
  "port": 57323,
  "rootPath": "/home/user/korobka",
  "imagesPath": "/home/user/korobka/images",
  "timestamp": "2025-09-16T12:34:56.789Z"
}
```

### `GET /api/folders`

Список всех папок коллекции.

**Ответ 200:**
```json
{
  "folders": [
    { "id": 1, "name": "Скриншоты", "parentId": null, "color": null, "createdAt": 1700000000 },
    { "id": 2, "name": "Проекты",   "parentId": null, "color": "#ff8800", "createdAt": 1700000100 }
  ]
}
```

### `POST /api/folder/add`

Создать новую папку (опционально внутри родительской).

**Тело:**
```json
{ "name": "Идеи", "parentId": 2 }
```

**Ответ 200:**
```json
{ "status": "ok", "id": 3, "name": "Идеи", "parentId": 2 }
```

### `POST /api/item/add`

Добавить один элемент в коллекцию.

**Тело:**
```json
{
  "name":     "screenshot.png",
  "base64":   "iVBORw0KGgoAAAANSUhEUgAA...",
  "url":      "https://example.com/image.png",
  "folderId": 2,
  "tags":     ["веб", "референс"]
}
```

| Поле       | Тип      | Обязательное | Описание |
|------------|----------|--------------|----------|
| `name`     | string   | нет          | Имя файла. Если не указано, генерируется автоматически (`korobka_<timestamp>.<ext>`). |
| `base64`   | string   | да*          | Содержимое файла в base64. Поддерживает как чистый base64, так и Data URL (`data:image/png;base64,...`). |
| `url`      | string   | да*          | HTTP/HTTPS-URL файла — «Коробка» сама скачает его во временный файл и импортирует. |
| `folderId` | number   | нет          | ID существующей папки. Если не указан — элемент попадает в корень. |
| `tags`     | string[] | нет          | Имена тегов. Несуществующие теги создаются автоматически. |

\* Должно быть указано **либо** `base64`, **либо** `url`. Если нет ни одного
— `400 Bad Request`.

**Ответ 200:**
```json
{
  "status": "ok",
  "id": 42,
  "title": "screenshot.png",
  "path": "/home/user/korobka/images/screenshot.png",
  "folderId": 2
}
```

**Ответ 400** (нет `base64` и `url`):
```json
{ "error": "bad_request", "message": "either `base64` or `url` is required" }
```

### `POST /api/items/add`

Пакетный импорт нескольких элементов. Тело — массив объектов той же
структуры, что и у `POST /api/item/add`.

**Тело:**
```json
{
  "items": [
    { "name": "a.png", "base64": "iVBORw0KGgo..." },
    { "name": "b.png", "base64": "iVBORw0KGgo..." },
    { "url": "https://example.com/c.png" }
  ]
}
```

**Ответ 200:**
```json
{
  "status": "ok",
  "added": 2,
  "total": 3,
  "results": [
    { "status": "ok", "id": 42, "title": "a.png", "path": "...", "folderId": null },
    { "status": "ok", "id": 43, "title": "b.png", "path": "...", "folderId": null },
    { "status": "error", "error": "import_failed", "message": "HTTP 404 for https://..." }
  ]
}
```

## Примеры использования

### cURL — отправить PNG из base64

```bash
curl -X POST http://127.0.0.1:57323/api/item/add \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "pixel.png",
    "base64": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC",
    "tags": ["test"]
  }'
```

### cURL — отправить файл по URL

```bash
curl -X POST http://127.0.0.1:57323/api/item/add \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "logo.png",
    "url": "https://raw.githubusercontent.com/flutter/website/main/src/assets/images/logo.png",
    "folderId": 1
  }'
```

### JavaScript (расширение браузера)

```javascript
// Получаем текущую вкладку как изображение и отправляем в «Коробку».
chrome.tabs.captureVisibleTab(null, { format: 'png' }, async (dataUrl) => {
  const resp = await fetch('http://127.0.0.1:57323/api/item/add', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      name: `screenshot-${Date.now()}.png`,
      base64: dataUrl,           // можно передать data: URL напрямую
      tags: ['браузер', 'скриншот'],
    }),
  });
  const result = await resp.json();
  console.log('Сохранено в «Коробку»:', result.id);
});
```

### Python

```python
import base64, requests

with open('image.png', 'rb') as f:
    b64 = base64.b64encode(f.read()).decode()

requests.post('http://127.0.0.1:57323/api/item/add', json={
    'name': 'image.png',
    'base64': b64,
    'tags': ['python'],
})
```

## Совместимость с Eagle API

Протокол вдохновлён Eagle, но **не идентичен** ему. Основные отличия:

* «Коробка» принимает поле `base64` или `url`, Eagle — только `base64`.
* «Коробка» не требует поля `token` (Eagle использует его для авторизации
  расширения).
* Поля ответа могут отличаться — не рассчитывайте на побайтовую
  совместимость с Eagle.

Если вы портируете расширение Eagle — замените URL `http://localhost:57323`
на `http://127.0.0.1:57323` (или ваш порт) и уберите поле `token`.

## Безопасность

* Сервер слушает **только на loopback-интерфейсе**. К нему нельзя
  подключиться с другой машины в локальной сети или из интернета.
* Любой процесс на этой машине может отправлять файлы — это нормальный
  сценарий (расширение браузера, скрипты и т.д.).
* Если вы хотите отключить сервер, выключите тумблер в настройках — он не
  будет запущен при следующем старте приложения.

## Устранение неполадок

| Симптом | Решение |
|---------|---------|
| `Connection refused` | Сервер не запущен — включите его в настройках. |
| `Address already in use` при смене порта | Порт занят другим процессом. Выберите свободный порт (например, 57324). |
| Файл не появляется в коллекции | Проверьте `status` в ответе сервера — если `error`, посмотрите поле `message`. |
| Слишком большие файлы | Сервер не имеет жёсткого лимита, но `base64` увеличивает объём на ~33%. Для больших файлов предпочтительнее `url`. |
