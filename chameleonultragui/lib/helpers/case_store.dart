import 'dart:io';
import 'dart:typed_data';

import 'package:chameleonultragui/helpers/card_save_converters.dart';
import 'package:chameleonultragui/helpers/case_bundle.dart';
import 'package:chameleonultragui/helpers/case_report.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// On-disk per-card "case folder": `<documents>/cases/<cardId>/` holding
/// `card.json`, `report.md`, auto-generated Flipper files, and `photos/`.
/// This is the source of truth for photo bytes (SharedPreferences only keeps
/// the lightweight [CardMedia] references).
class CaseStore {
  static Future<Directory> _rootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'cases'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> cardDir(String cardId) async {
    final root = await _rootDir();
    final dir = Directory(p.join(root.path, cardId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> _photosDir(String cardId) async {
    final card = await cardDir(cardId);
    final dir = Directory(p.join(card.path, 'photos'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Copy a captured photo into the card's folder. Returns the relative
  /// filename (e.g. `photos/3.jpg`) to store on the [CardSave].
  static Future<String> addPhoto(String cardId, File source,
      {String extension = 'jpg'}) async {
    final dir = await _photosDir(cardId);
    final existing = (await dir.list().toList())
        .whereType<File>()
        .length;
    final relative = 'photos/${existing + 1}.$extension';
    final dest = File(p.join((await cardDir(cardId)).path, relative));
    await source.copy(dest.path);
    return relative;
  }

  /// Resolve a media reference to its file on disk, if present.
  static Future<File?> photoFile(String cardId, String relativeName) async {
    final dir = await cardDir(cardId);
    final file = File(p.join(dir.path, relativeName));
    return await file.exists() ? file : null;
  }

  /// Write `card.json`, `report.md`, and any Flipper file for the card.
  /// Call after the card changes so the folder stays report-ready.
  static Future<void> writeCardFiles(CardSave card) async {
    final dir = await cardDir(card.id);
    await File(p.join(dir.path, 'card.json')).writeAsString(card.toJson());
    await File(p.join(dir.path, 'report.md'))
        .writeAsString(caseReportMarkdown(card));

    final safeUid = card.uid.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    final base = safeUid.isNotEmpty ? safeUid : 'card';
    final flipperDir = Directory(p.join(dir.path, 'flipper'));
    if (canExportFlipperNfc(card.tag)) {
      if (!await flipperDir.exists()) await flipperDir.create(recursive: true);
      await File(p.join(flipperDir.path, '$base.nfc'))
          .writeAsString(cardSaveToFlipperNfc(card));
    } else if (canExportFlipperRfid(card.tag)) {
      if (!await flipperDir.exists()) await flipperDir.create(recursive: true);
      await File(p.join(flipperDir.path, '$base.rfid'))
          .writeAsString(cardSaveToFlipperRfid(card));
    }
  }

  /// Build a shareable case zip from the card and its on-disk photos.
  static Future<Uint8List> exportZip(CardSave card) async {
    final photoBytes = <String, Uint8List>{};
    for (final media in card.media) {
      final file = await photoFile(card.id, media.filename);
      if (file != null) {
        photoBytes[media.filename] = await file.readAsBytes();
      }
    }
    return buildCardZip(card, photoBytes);
  }

  /// Import a case zip: writes the imported photos into the card's folder and
  /// returns the [CardSave] (with a fresh id so it never clobbers an existing
  /// card). The caller is responsible for persisting the card.
  static Future<CardSave> importZip(Uint8List zipBytes) async {
    final imported = importCardZip(zipBytes);
    final card = imported.card;
    for (final entry in imported.photos.entries) {
      final dir = await cardDir(card.id);
      final dest = File(p.join(dir.path, entry.key));
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(entry.value);
    }
    await writeCardFiles(card);
    return card;
  }

  /// Remove a card's entire case folder (photos included).
  static Future<void> deleteCase(String cardId) async {
    final root = await _rootDir();
    final dir = Directory(p.join(root.path, cardId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
