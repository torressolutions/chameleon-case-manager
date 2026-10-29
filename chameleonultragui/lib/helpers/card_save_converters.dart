import 'dart:convert';
import 'dart:typed_data';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

CardSave pm3JsonToCardSave(String json) {
  Map<String, dynamic> data = jsonDecode(json);

  final String id = const Uuid().v4();
  final String uid = data['Card']['UID'] as String;
  String sakString = data['Card']['SAK'] as String;
  final int sak = hexToBytes(sakString)[0];
  String atqaString = data['Card']['ATQA'] as String;
  final List<int> atqa = [
    int.parse(atqaString.substring(2), radix: 16),
    int.parse(atqaString.substring(0, 2), radix: 16)
  ];
  final List<int> ats = [];
  final String name = uid;
  const Color color = Colors.deepOrange;
  final TagType tag;
  List<Uint8List> tagData = [];

  List<String> blocks = [];
  Map<String, dynamic> blockData = data['blocks'] as Map<String, dynamic>;
  for (int i = 0; blockData.containsKey(i.toString()); i++) {
    blocks.add(blockData[i.toString()] as String);
  }

  //Check if a block has more than 16 Bytes, Ultralight, return as unknown
  if (blocks[0].length > 32) {
    tag = TagType.unknown;
  } else {
    tag = mfClassicGetChameleonTagType(
        mfClassicGetCardTypeByBlockCount(blocks.length));
  }

  for (var block in blocks) {
    tagData.add(hexToBytes(block));
  }

  return CardSave(
      id: id,
      uid: uid,
      sak: sak,
      name: name,
      tag: tag,
      data: tagData,
      color: color,
      ats: Uint8List.fromList(ats),
      atqa: Uint8List.fromList(atqa));
}

CardSave flipperNfcToCardSave(String data) {
  final String id = const Uuid().v4();
  final String uid =
      RegExp(r'UID:\s+([\dA-Fa-f ]+)').firstMatch(data)!.group(1)!;
  final int sak = hexToBytes(
      RegExp(r'SAK:\s+([\dA-Fa-f ]+)').firstMatch(data)!.group(1)!)[0];
  String atqaString =
      RegExp(r'ATQA:\s+([\dA-Fa-f ]+)').firstMatch(data)!.group(1)!;
  final List<int> atqa = [
    int.parse(atqaString.substring(0, 2), radix: 16),
    int.parse(atqaString.substring(2), radix: 16)
  ];
  final List<int> ats = [];
  final String name = uid;
  const Color color = Colors.deepOrange;
  final TagType tag;
  List<Uint8List> tagData = [];
  List<String> blocks = [];
  for (var block in data.split("\n")) {
    if (block.startsWith("Block")) {
      blocks.add(block.split(":")[1].trim().replaceAll('?', '0'));
    }
  }

  //Check if a block has more than 16 Bytes, Ultralight, return as unknown
  if (blocks[0].replaceAll(' ', '').length > 32) {
    tag = TagType.unknown;
  } else {
    tag = mfClassicGetChameleonTagType(
        mfClassicGetCardTypeByBlockCount(blocks.length));
  }

  for (var block in blocks) {
    tagData.add(hexToBytes(block));
  }

  return CardSave(
      id: id,
      uid: uid,
      sak: sak,
      name: name,
      tag: tag,
      data: tagData,
      color: color,
      ats: Uint8List.fromList(ats),
      atqa: Uint8List.fromList(atqa));
}

CardSave mctToCardSave(String data) {
  final String id = const Uuid().v4();
  final String uid = data.split("\n")[1].substring(0, 8);
  final int sak = hexToBytes(data.split("\n")[1].substring(10, 12))[0];
  String atqaString = data.split("\n")[1].substring(12, 16);
  final List<int> atqa = [
    int.parse(atqaString.substring(2), radix: 16),
    int.parse(atqaString.substring(0, 2), radix: 16)
  ];
  final List<int> ats = [];
  final String name = uid;
  const Color color = Colors.deepOrange;
  final TagType tag;
  List<Uint8List> tagData = [];
  List<String> blocks = [];
  for (var block in data.split("\n")) {
    if (!block.startsWith("+Sector")) {
      blocks.add(block.trim());
    }
  }

  //Check if a block has more than 16 Bytes, Ultralight, return as unknown
  if (blocks[0].replaceAll(' ', '').length > 32) {
    tag = TagType.unknown;
  } else {
    tag = mfClassicGetChameleonTagType(
        mfClassicGetCardTypeByBlockCount(blocks.length));
  }

  for (var block in blocks) {
    tagData.add(hexToBytes(block));
  }

  return CardSave(
      id: id,
      uid: uid,
      sak: sak,
      name: name,
      tag: tag,
      data: tagData,
      color: color,
      ats: Uint8List.fromList(ats),
      atqa: Uint8List.fromList(atqa));
}

CardSave flipperRfidToCardSave(String data) {
  final String id = const Uuid().v4();
  final String type = RegExp(r'Key type:\s+(.*)').firstMatch(data)!.group(1)!;
  const Color color = Colors.deepOrange;

  final TagType tag;
  String uid = RegExp(r'Data:\s+([\dA-Fa-f ]+)').firstMatch(data)!.group(1)!;

  switch (type) {
    case 'EM4100':
      tag = TagType.em410X64;
      break;
    case 'EM4100/32':
      tag = TagType.em410X32;
      break;
    case 'EM4100/16':
      tag = TagType.em410X16;
      break;
    case 'H10301':
      tag = TagType.hidProx;
      uid = HIDCard(
              hidType: 1,
              facilityCode: hexToBytes(uid)[0],
              uid: Uint8List.fromList(
                  [0, 0, 0, ...hexToBytes(uid).sublist(1, 3)]),
              issueLevel: 0,
              oem: 0)
          .toString();
      break;
    default:
      tag = TagType.unknown;
  }

  return CardSave(id: id, uid: uid, name: uid, tag: tag, color: color);
}

// ---------------------------------------------------------------------------
// Export: CardSave -> interchange formats (for Flipper Zero and sharing).
// These round-trip with the importers above and target the current Flipper
// file formats (Version 4 .nfc, uppercase space-separated hex, ATQA MSB-first).
// ---------------------------------------------------------------------------

/// LF (125 kHz) cards use TagType values below 1000; HF (13.56 MHz) are >= 1000.
bool tagTypeIsLowFrequency(TagType tag) => tag.value > 0 && tag.value < 1000;

/// Flipper "Mifare Classic type" string, or null if [tag] is not a classic.
String? flipperMifareClassicType(TagType tag) {
  switch (tag) {
    case TagType.mifareMini:
      return 'Mini';
    case TagType.mifare1K:
      return '1K';
    case TagType.mifare2K:
      return '2K';
    case TagType.mifare4K:
      return '4K';
    default:
      return null;
  }
}

/// Flipper "NTAG/Ultralight type" string, or null if [tag] is not one.
String? flipperUltralightType(TagType tag) {
  switch (tag) {
    case TagType.ultralight:
      return 'Mifare Ultralight';
    case TagType.ultralight11:
      return 'Mifare Ultralight 11';
    case TagType.ultralight21:
      return 'Mifare Ultralight 21';
    case TagType.ntag213:
      return 'NTAG213';
    case TagType.ntag215:
      return 'NTAG215';
    case TagType.ntag216:
      return 'NTAG216';
    default:
      return null;
  }
}

/// True if this card can be written to a Flipper `.nfc` file.
bool canExportFlipperNfc(TagType tag) =>
    flipperMifareClassicType(tag) != null ||
    flipperUltralightType(tag) != null;

/// True if this card can be written to a Flipper `.rfid` file.
bool canExportFlipperRfid(TagType tag) =>
    tag == TagType.em410X ||
    tag == TagType.em410X64 ||
    tag == TagType.em410X32 ||
    tag == TagType.em410X16;

/// Serialise a HF card (Mifare Classic / Ultralight / NTAG) to a Flipper
/// `.nfc` file. Throws [UnsupportedError] for types Flipper cannot represent.
String cardSaveToFlipperNfc(CardSave card) {
  final String uid = bytesToHexSpace(hexToBytes(card.uid));
  final String atqa = bytesToHexSpace(
      card.atqa.isNotEmpty ? card.atqa : Uint8List.fromList([0, 0]));
  final String sak = card.sak.toRadixString(16).padLeft(2, '0').toUpperCase();

  final String? mfType = flipperMifareClassicType(card.tag);
  final String? ulType = flipperUltralightType(card.tag);

  final StringBuffer buf = StringBuffer();
  buf.writeln('Filetype: Flipper NFC device');
  buf.writeln('Version: 4');

  if (mfType != null) {
    buf.writeln('Device type: Mifare Classic');
    buf.writeln('UID: $uid');
    buf.writeln('ATQA: $atqa');
    buf.writeln('SAK: $sak');
    buf.writeln('Mifare Classic type: $mfType');
    buf.writeln('Data format version: 2');
    for (int i = 0; i < card.data.length; i++) {
      buf.writeln('Block $i: ${bytesToHexSpace(card.data[i])}');
    }
  } else if (ulType != null) {
    buf.writeln('Device type: NTAG/Ultralight');
    buf.writeln('UID: $uid');
    buf.writeln('ATQA: $atqa');
    buf.writeln('SAK: $sak');
    buf.writeln('Data format version: 2');
    buf.writeln('NTAG/Ultralight type: $ulType');
    if (card.extraData.ultralightSignature.isNotEmpty) {
      buf.writeln(
          'Signature: ${bytesToHexSpace(card.extraData.ultralightSignature)}');
    }
    if (card.extraData.ultralightVersion.isNotEmpty) {
      buf.writeln(
          'Mifare version: ${bytesToHexSpace(card.extraData.ultralightVersion)}');
    }
    buf.writeln('Pages total: ${card.data.length}');
    buf.writeln('Pages read: ${card.data.length}');
    for (int i = 0; i < card.data.length; i++) {
      buf.writeln('Page $i: ${bytesToHexSpace(card.data[i])}');
    }
    buf.writeln('Failed authentication attempts: 0');
  } else {
    throw UnsupportedError(
        'Flipper .nfc export does not support ${card.tag.name} yet '
        '(supported: Mifare Classic, Ultralight, NTAG213/215/216).');
  }
  return buf.toString();
}

/// Serialise a LF (125 kHz) EM4100-family card to a Flipper `.rfid` file.
/// Throws [UnsupportedError] for LF types not yet mapped.
String cardSaveToFlipperRfid(CardSave card) {
  final String keyType;
  switch (card.tag) {
    case TagType.em410X:
    case TagType.em410X64:
      keyType = 'EM4100';
      break;
    case TagType.em410X32:
      keyType = 'EM4100/32';
      break;
    case TagType.em410X16:
      keyType = 'EM4100/16';
      break;
    default:
      throw UnsupportedError(
          'Flipper .rfid export currently supports EM4100-family LF cards; '
          '${card.tag.name} is not supported yet.');
  }

  final String data = bytesToHexSpace(hexToBytes(card.uid));
  final StringBuffer buf = StringBuffer();
  buf.writeln('Filetype: Flipper RFID key');
  buf.writeln('Version: 1');
  buf.writeln('Key type: $keyType');
  buf.writeln('Data: $data');
  return buf.toString();
}
