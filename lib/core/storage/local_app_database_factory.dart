import 'local_app_database.dart';

Future<LocalAppDatabase> openLocalAppDatabase() {
  return LocalAppDatabase.open();
}
