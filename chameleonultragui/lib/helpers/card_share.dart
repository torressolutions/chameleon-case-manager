import 'dart:convert';
import 'dart:io';

import 'package:chameleonultragui/helpers/card_save_converters.dart';
import 'package:chameleonultragui/helpers/case_store.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

String _safeName(String name) {
  final s = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return s.isEmpty ? 'card' : s;
}

/// Present the per-card share/export options: a self-contained case zip (share
/// via the system sheet or save to a file) and, where supported, a Flipper Zero
/// file. See [buildCardZip]/[cardSaveToFlipperNfc] for the formats.
Future<void> showCaseExportDialog(BuildContext context, CardSave card) async {
  final hasNfc = canExportFlipperNfc(card.tag);
  final hasRfid = canExportFlipperRfid(card.tag);

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Share / export card'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.share),
            title: const Text('Share case bundle (.zip)'),
            subtitle:
                const Text('Card data, photos, report + Flipper file'),
            onTap: () async {
              Navigator.pop(ctx);
              await _shareZip(context, card);
            },
          ),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('Save case bundle (.zip)'),
            onTap: () async {
              Navigator.pop(ctx);
              await _saveZip(context, card);
            },
          ),
          if (hasNfc || hasRfid)
            ListTile(
              leading: const Icon(Icons.sim_card),
              title: const Text('Export Flipper file'),
              subtitle: Text(hasNfc ? '.nfc (HF)' : '.rfid (LF)'),
              onTap: () async {
                Navigator.pop(ctx);
                await _saveFlipper(context, card);
              },
            ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
      ],
    ),
  );
}

Future<void> _shareZip(BuildContext context, CardSave card) async {
  try {
    final bytes = await CaseStore.exportZip(card);
    final tmp = await getTemporaryDirectory();
    final file = File(p.join(tmp.path, '${_safeName(card.name)}.zip'));
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/zip')],
      subject: card.name,
    ));
  } catch (e) {
    if (context.mounted) _snack(context, 'Share failed: $e');
  }
}

Future<void> _saveZip(BuildContext context, CardSave card) async {
  try {
    final bytes = await CaseStore.exportZip(card);
    await FilePicker.saveFile(
      dialogTitle: 'Save case bundle:',
      fileName: '${_safeName(card.name)}.zip',
      bytes: bytes,
    );
  } catch (e) {
    if (context.mounted) _snack(context, 'Save failed: $e');
  }
}

Future<void> _saveFlipper(BuildContext context, CardSave card) async {
  try {
    final String content;
    final String ext;
    if (canExportFlipperNfc(card.tag)) {
      content = cardSaveToFlipperNfc(card);
      ext = 'nfc';
    } else {
      content = cardSaveToFlipperRfid(card);
      ext = 'rfid';
    }
    await FilePicker.saveFile(
      dialogTitle: 'Save Flipper file:',
      fileName: '${_safeName(card.name)}.$ext',
      bytes: const Utf8Encoder().convert(content),
    );
  } catch (e) {
    if (context.mounted) _snack(context, 'Flipper export failed: $e');
  }
}

void _snack(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));
}
