import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:chameleonultragui/helpers/card_save_converters.dart';
import 'package:chameleonultragui/helpers/case_report.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

/// Self-contained "case" zip: one card with everything needed to write a report
/// or use the card elsewhere (incl. a Flipper Zero). Pure byte-level logic so it
/// is unit-testable; filesystem glue lives in case_store.dart.
const String caseBundleFormat = 'chameleon-case-manager-card';
const int caseBundleVersion = 1;

/// A card imported from a case zip, with its photo bytes keyed by the relative
/// filename referenced in [CardSave.media].
class ImportedCard {
  final CardSave card;
  final Map<String, Uint8List> photos;
  ImportedCard(this.card, this.photos);
}

/// Build a shareable `.zip` for a single card.
///
/// [photoBytes] is keyed by the media filename stored on the card
/// (e.g. `photos/1.jpg`). Flipper files are generated best-effort: card types
/// Flipper cannot represent are simply omitted.
Uint8List buildCardZip(CardSave card, Map<String, Uint8List> photoBytes) {
  final archive = Archive();

  final manifest = {
    'format': caseBundleFormat,
    'version': caseBundleVersion,
    'generator': 'Chameleon Case Manager',
  };
  archive.add(ArchiveFile.string(
      'manifest.json', const JsonEncoder.withIndent('  ').convert(manifest)));
  archive.add(ArchiveFile.string('card.json', card.toJson()));
  archive.add(ArchiveFile.string('report.md', caseReportMarkdown(card)));

  // Photos referenced by the card.
  for (final media in card.media) {
    final bytes = photoBytes[media.filename];
    if (bytes != null) {
      archive.add(ArchiveFile.bytes(media.filename, bytes));
    }
  }

  // Auto-generated Flipper files so the recipient can use the card on a Flipper
  // Zero without the app. Unsupported types are skipped.
  final safeUid = card.uid.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
  final baseName = safeUid.isNotEmpty ? safeUid : 'card';
  if (canExportFlipperNfc(card.tag)) {
    archive.add(ArchiveFile.string(
        'flipper/$baseName.nfc', cardSaveToFlipperNfc(card)));
  } else if (canExportFlipperRfid(card.tag)) {
    archive.add(ArchiveFile.string(
        'flipper/$baseName.rfid', cardSaveToFlipperRfid(card)));
  }

  return ZipEncoder().encodeBytes(archive);
}

/// Parse a case `.zip` back into a card and its photo bytes.
///
/// Tolerant of zips that only contain a Flipper `.nfc`/`.rfid` (falls back to
/// the matching importer) so a bare export from another tool still loads.
ImportedCard importCardZip(Uint8List zipBytes) {
  final archive = ZipDecoder().decodeBytes(zipBytes);

  String? cardJson;
  String? nfc;
  String? rfid;
  final photos = <String, Uint8List>{};

  for (final file in archive.files) {
    if (!file.isFile) continue;
    final name = file.name;
    if (name == 'card.json') {
      cardJson = utf8.decode(file.content);
    } else if (name.endsWith('.nfc')) {
      nfc = utf8.decode(file.content);
    } else if (name.endsWith('.rfid')) {
      rfid = utf8.decode(file.content);
    } else if (name.startsWith('photos/')) {
      photos[name] = file.content;
    }
  }

  final CardSave card;
  if (cardJson != null) {
    card = CardSave.fromJson(cardJson);
  } else if (nfc != null) {
    card = flipperNfcToCardSave(nfc);
  } else if (rfid != null) {
    card = flipperRfidToCardSave(rfid);
  } else {
    throw const FormatException(
        'No card.json or Flipper file found in case bundle');
  }

  return ImportedCard(card, photos);
}
