if (filter.createdAfter != null) {
      where.add('created_at >= ?');
      args.add(filter.createdAfter);
    }

    // Фильтр по цвету палитры (ищем шестнадцатеричное значение в JSON).
    if (filter.paletteColor != null) {
      where.add('palette LIKE ?');
      args.add('%${filter.paletteColor!.toUpperCase()}%');
    }