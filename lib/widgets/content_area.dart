class _ToolbarState extends State<_Toolbar> {
  late final TextEditingController _searchController;
  Timer? _debounce;

  /// Палитра цветов для быстрой фильтрации.
  static const _palette = <(String, Color)>[
    ('FF5722', Color(0xFFFF5722)), // оранжевый
    ('FFEB3B', Color(0xFFFFEB3B)), // жёлтый
    ('4CAF50', Color(0xFF4CAF50)), // зелёный
    ('2196F3', Color(0xFF2196F3)), // синий
    ('9C27B0', Color(0xFF9C27B0)), // фиолетовый
    ('F44336', Color(0xFFF44336)), // красный
    ('000000', Color(0xFF000000)), // чёрный
    ('FFFFFF', Color(0xFFFFFFFF)), // белый
  ];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.state.setSearchQuery(value);
    });
  }

  void _showColorFilter(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Фильтр по цвету'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (hex, color) in _palette)
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () {
                  widget.state.setColorFilter(hex);
                  Navigator.pop(context);
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade400),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.state.clearColorFilter();
              Navigator.pop(context);
            },
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final state = widget.state;
    final result = state.selectedItem != null
        ? await state.exportSelectedItem()
        : await state.exportCurrentItems();

    if (result == null) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Экспортировано: ${result.exported}, ошибок: ${result.failed}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 200,
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Поиск...',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Фильтр по цвету',
              icon: const Icon(Icons.palette_outlined),
              onPressed: () => _showColorFilter(context),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: () => widget.state.importFiles(),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Импорт'),
            ),
            TextButton.icon(
              onPressed: () => widget.state.importDirectory(),
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('Папка'),
            ),
            IconButton(
              tooltip: 'Экспорт',
              icon: const Icon(Icons.download_outlined),
              onPressed: () => _export(context),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Сетка',
              icon: const Icon(Icons.grid_view_outlined),
              onPressed: () => widget.state.setViewMode(ViewMode.grid),
            ),
            IconButton(
              tooltip: 'Список',
              icon: const Icon(Icons.view_list_outlined),
              onPressed: () => widget.state.setViewMode(ViewMode.list),
            ),
          ],
        ),
      ),
    );
  }
}