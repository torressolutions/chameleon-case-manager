import 'dart:typed_data';

import 'package:chameleonultragui/helpers/card_save_converters.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Flipper .nfc export (HF)', () {
    test('Mifare Classic 1K round-trips through the importer', () {
      // 64 blocks of 16 bytes => Mifare Classic 1K.
      final List<Uint8List> blocks = List.generate(
          64, (i) => Uint8List.fromList(List<int>.filled(16, i & 0xFF)));
      // Block 0 carries a realistic manufacturer block.
      blocks[0] = hexToBytes('BA E2 7C 9D B9 18 02 00 46 44 53 37 30 56 30 31');

      final card = CardSave(
        uid: '01 02 03 04',
        name: 'test 1k',
        tag: TagType.mifare1K,
        sak: 0x08,
        atqa: Uint8List.fromList([0x00, 0x04]),
        data: blocks,
      );

      final nfc = cardSaveToFlipperNfc(card);
      expect(nfc, contains('Filetype: Flipper NFC device'));
      expect(nfc, contains('Version: 4'));
      expect(nfc, contains('Device type: Mifare Classic'));
      expect(nfc, contains('Mifare Classic type: 1K'));
      expect(nfc, contains('ATQA: 00 04'));
      expect(nfc, contains('SAK: 08'));

      final back = flipperNfcToCardSave(nfc);
      expect(hexToBytes(back.uid), equals(hexToBytes(card.uid)));
      expect(back.sak, equals(card.sak));
      expect(back.atqa, equals(card.atqa));
      expect(back.tag, equals(TagType.mifare1K));
      expect(back.data.length, equals(card.data.length));
      expect(back.data[0], equals(card.data[0]));
      expect(back.data[63], equals(card.data[63]));
    });

    test('unsupported HF type throws instead of writing a bad file', () {
      final card = CardSave(uid: 'DE AD BE EF', name: 'x', tag: TagType.hf14a4);
      expect(() => cardSaveToFlipperNfc(card), throwsUnsupportedError);
    });
  });

  group('Flipper .rfid export (LF)', () {
    test('EM4100 round-trips through the importer', () {
      final card = CardSave(
        uid: '11 22 33 44 55',
        name: 'em',
        tag: TagType.em410X64,
      );

      final rfid = cardSaveToFlipperRfid(card);
      expect(rfid, contains('Filetype: Flipper RFID key'));
      expect(rfid, contains('Key type: EM4100'));
      expect(rfid, contains('Data: 11 22 33 44 55'));

      final back = flipperRfidToCardSave(rfid);
      expect(hexToBytes(back.uid), equals(hexToBytes(card.uid)));
      expect(back.tag, equals(TagType.em410X64));
    });

    test('non-EM LF type throws', () {
      final card = CardSave(uid: '01 02 03', name: 'v', tag: TagType.viking);
      expect(() => cardSaveToFlipperRfid(card), throwsUnsupportedError);
    });
  });

  group('frequency classification', () {
    test('LF below 1000, HF at/above 1000', () {
      expect(tagTypeIsLowFrequency(TagType.em410X64), isTrue);
      expect(tagTypeIsLowFrequency(TagType.hidProx), isTrue);
      expect(tagTypeIsLowFrequency(TagType.mifare1K), isFalse);
      expect(tagTypeIsLowFrequency(TagType.ntag215), isFalse);
      expect(tagTypeIsLowFrequency(TagType.unknown), isFalse);
    });
  });

  group('extended CardSave model (location / photos / engagement)', () {
    test('new fields survive a JSON round-trip', () {
      final card = CardSave(
        uid: '01 02 03 04',
        name: 'case card',
        tag: TagType.mifare1K,
        location: CaptureLocation(
          latitude: 28.5383,
          longitude: -81.3792,
          accuracy: 4.5,
          timestamp: '2026-10-29T12:00:00Z',
        ),
        media: [
          CardMedia(filename: 'photos/1.jpg', caption: 'front', kind: 'photo'),
        ],
        engagement: Engagement(
          client: 'Acme Corp',
          scopeRef: 'SOW-2026-14',
          authorizedBy: 'J. Torres',
        ),
        capturedAt: '2026-10-29T12:00:00Z',
        capturedBy: 'jt',
      );

      final back = CardSave.fromJson(card.toJson());
      expect(back.location, isNotNull);
      expect(back.location!.latitude, closeTo(28.5383, 1e-9));
      expect(back.location!.longitude, closeTo(-81.3792, 1e-9));
      expect(back.location!.accuracy, closeTo(4.5, 1e-9));
      expect(back.media.length, equals(1));
      expect(back.media[0].filename, equals('photos/1.jpg'));
      expect(back.media[0].caption, equals('front'));
      expect(back.engagement, isNotNull);
      expect(back.engagement!.client, equals('Acme Corp'));
      expect(back.engagement!.scopeRef, equals('SOW-2026-14'));
      expect(back.capturedBy, equals('jt'));
    });

    test('legacy card JSON without new fields still loads', () {
      final legacy = CardSave(
        uid: '01 02 03 04',
        name: 'legacy',
        tag: TagType.mifare1K,
      );
      final back = CardSave.fromJson(legacy.toJson());
      expect(back.location, isNull);
      expect(back.media, isEmpty);
      expect(back.engagement, isNull);
    });
  });
}
