import 'package:korobka/data/app_database.dart';

/// Общий тестовый хелпер: подмена пути БД (используется несколькими
/// тестовыми файлами).
class AppDatabaseTest {
  static void setDatabasePath(String path) {
    AppDatabase.overridePath = path;
  }
}
