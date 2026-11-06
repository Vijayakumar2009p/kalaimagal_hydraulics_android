import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Saves app data on the phone:
///  * settings, customer list and pending entries as JSON files (app-private folder)
///  * password and Odoo session in Android's encrypted secure storage
class LocalStore {
  LocalStore._(this._dir);

  final Directory _dir;
  static const _secure = FlutterSecureStorage();

  static Future<LocalStore> open() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/field_locator');
    if (!await dir.exists()) await dir.create(recursive: true);
    return LocalStore._(dir);
  }

  String get photosPath => '${_dir.path}/photos';

  File _file(String name) => File('${_dir.path}/$name.json');

  Future<dynamic> readJson(String name) async {
    final f = _file(name);
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null; // a damaged file is treated as empty
    }
  }

  final Map<String, Future<void>> _writing = {};

  /// Writes through a temp file so a crash never leaves half a file.
  /// Writes to the same file run one after another (never overlap), and a
  /// failed write never throws: the data is still in memory and is written
  /// again on the next save.
  Future<void> writeJson(String name, Object? data) {
    final text = jsonEncode(data); // snapshot now, write in order
    final previous = _writing[name] ?? Future<void>.value();
    final next = previous.then((_) async {
      try {
        final f = _file(name);
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(text, flush: true);
        await tmp.rename(f.path);
      } catch (_) {
        // Disk full or similar: keep going with the in-memory copy.
      }
    });
    _writing[name] = next;
    return next;
  }

  Future<void> delete(String name) async {
    final f = _file(name);
    if (await f.exists()) await f.delete();
  }

  // ---- secure values ----
  Future<String?> readSecret(String key) async {
    try {
      return await _secure.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeSecret(String key, String? value) async {
    try {
      if (value == null) {
        await _secure.delete(key: key);
      } else {
        await _secure.write(key: key, value: value);
      }
    } catch (_) {
      // Secure storage can fail on a few devices; the user just logs in again.
    }
  }

  /// Saves a photo into the app folder and returns its path.
  Future<String> keepPhoto(String sourcePath, String ref) async {
    final dir = Directory(photosPath);
    if (!await dir.exists()) await dir.create(recursive: true);
    final target = '${dir.path}/$ref.jpg';
    await File(sourcePath).copy(target);
    return target;
  }

  Future<void> deletePhoto(String? path) async {
    if (path == null || path.isEmpty) return;
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
