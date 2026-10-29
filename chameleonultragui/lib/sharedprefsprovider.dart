import 'dart:typed_data';
import 'dart:convert';
import 'package:chameleonultragui/helpers/colors.dart' as colors;
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class Dictionary {
  String id;
  String name;
  List<Uint8List> keys;
  Color color;
  int keyLength;
  String? folderId;

  factory Dictionary.fromJson(String json) {
    Map<String, dynamic> data = jsonDecode(json);
    final id = data['id'] as String;
    final name = data['name'] as String;
    final encodedKeys = data['keys'] as List<dynamic>;
    if (data['color'] == null) {
      data['color'] = colorToHex(Colors.deepOrange);
    }

    if (data['keyLength'] == null) {
      // legacy
      data['keyLength'] = 12;
    }

    final keyLength = data['keyLength'] as int;
    final color = hexToColor(data['color']);
    final folderId = data['folderId'] as String?;

    List<Uint8List> keys = [];
    for (var key in encodedKeys) {
      keys.add(Uint8List.fromList(List<int>.from(key)));
    }
    return Dictionary(
        id: id,
        name: name,
        keys: keys,
        color: color,
        keyLength: keyLength,
        folderId: folderId);
  }

  String toJson() {
    return jsonEncode({
      'id': id,
      'name': name,
      'color': colorToHex(color),
      'keys': keys.map((key) => key.toList()).toList(),
      'keyLength': keyLength,
      if (folderId != null) 'folderId': folderId,
    });
  }

  @override
  String toString() {
    String output = "";
    for (var key in keys) {
      output += "${bytesToHex(key).toUpperCase()}\n";
    }
    return output;
  }

  Uint8List toFile() {
    return const Utf8Encoder().convert(toString());
  }

  factory Dictionary.fromString(String input,
      {String name = '', Color color = Colors.deepOrange}) {
    List<Uint8List> keys = [];
    List<int> allowedKeySizes = [
      12, // 6 - Mifare Classic
      8, // 4 - Mifare Ultralight / T55XX
      32, // 16 - Mifare Ultralight C / AES / Mifare Plus
    ];
    int currentKeySize = 0;

    for (var key in input.split("\n")) {
      key = key.trim().replaceAll('#', ' ');

      if (key.contains(' ')) {
        key = key.split(' ')[0];
      }

      if (allowedKeySizes.contains(key.length) &&
          isValidHexString(key) &&
          (currentKeySize == 0 || currentKeySize == key.length)) {
        if (currentKeySize == 0) {
          currentKeySize = key.length;
        }

        keys.add(hexToBytes(key));
      }
    }

    return Dictionary(
        id: const Uuid().v4(),
        name: name,
        keys: keys,
        color: color,
        keyLength: currentKeySize);
  }

  Dictionary(
      {String? id,
      this.name = "",
      this.keys = const [],
      this.color = Colors.deepOrange,
      this.keyLength = 0,
      this.folderId})
      : id = id ?? const Uuid().v4();
}

class DictionaryFolder {
  String id;
  String name;
  Color color;
  String? parentId;

  DictionaryFolder({
    String? id,
    required this.name,
    this.color = Colors.deepOrange,
    this.parentId,
  }) : id = id ?? const Uuid().v4();

  factory DictionaryFolder.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    return DictionaryFolder(
      id: data['id'] as String,
      name: data['name'] as String,
      color: data['color'] == null
          ? Colors.deepOrange
          : hexToColor(data['color'] as String),
      parentId: data['parentId'] as String?,
    );
  }

  String toJson() => jsonEncode({
        'id': id,
        'name': name,
        'color': colorToHex(color),
        if (parentId != null) 'parentId': parentId,
      });
}

class DictionaryFolderBundle {
  final String rootFolderId;
  final List<DictionaryFolder> folders;
  final List<Dictionary> dictionaries;

  DictionaryFolderBundle({
    required this.rootFolderId,
    required this.folders,
    required this.dictionaries,
  });

  factory DictionaryFolderBundle.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    if (data['format'] != 'chameleon-ultra-gui-dictionary-folder' ||
        data['version'] != 1) {
      throw const FormatException('Unsupported dictionary folder file');
    }
    return DictionaryFolderBundle(
      rootFolderId: data['rootFolderId'] as String,
      folders: (data['folders'] as List<dynamic>)
          .map((item) => DictionaryFolder.fromJson(jsonEncode(item)))
          .toList(),
      dictionaries: (data['dictionaries'] as List<dynamic>)
          .map((item) => Dictionary.fromJson(jsonEncode(item)))
          .toList(),
    );
  }

  String toJson() => jsonEncode({
        'format': 'chameleon-ultra-gui-dictionary-folder',
        'version': 1,
        'rootFolderId': rootFolderId,
        'folders':
            folders.map((folder) => jsonDecode(folder.toJson())).toList(),
        'dictionaries': dictionaries
            .map((dictionary) => jsonDecode(dictionary.toJson()))
            .toList(),
      });
}

/// Where a card was captured (Walrus-style geotag). All fields optional so a
/// card saved without a fix still round-trips.
class CaptureLocation {
  final double latitude;
  final double longitude;
  final double? accuracy; // metres
  final String? timestamp; // ISO-8601 UTC

  CaptureLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.timestamp,
  });

  factory CaptureLocation.import(Map<String, dynamic> data) => CaptureLocation(
        latitude: (data['latitude'] as num).toDouble(),
        longitude: (data['longitude'] as num).toDouble(),
        accuracy: (data['accuracy'] as num?)?.toDouble(),
        timestamp: data['timestamp'] as String?,
      );

  Map<String, dynamic> export() => {
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
        if (timestamp != null) 'timestamp': timestamp,
      };

  /// A geo: URI an external map app can open.
  String get geoUri => 'geo:$latitude,$longitude';
}

/// A photo (or other media) captured with a card. Bytes live in the on-disk
/// case folder; only this reference is stored in SharedPreferences.
class CardMedia {
  final String filename; // relative to the card's case folder, e.g. photos/1.jpg
  final String? caption;
  final String kind; // 'photo' for now
  final String? capturedAt; // ISO-8601 UTC

  CardMedia({
    required this.filename,
    this.caption,
    this.kind = 'photo',
    this.capturedAt,
  });

  factory CardMedia.import(Map<String, dynamic> data) => CardMedia(
        filename: data['filename'] as String,
        caption: data['caption'] as String?,
        kind: (data['kind'] as String?) ?? 'photo',
        capturedAt: data['capturedAt'] as String?,
      );

  Map<String, dynamic> export() => {
        'filename': filename,
        if (caption != null) 'caption': caption,
        'kind': kind,
        if (capturedAt != null) 'capturedAt': capturedAt,
      };
}

/// Engagement/authorization metadata so every captured card is tied to the
/// scope it was collected under — traceability for the report and the tester.
class Engagement {
  final String? client;
  final String? scopeRef; // SOW / engagement reference
  final String? authorizedBy;
  final String? notes;

  Engagement({this.client, this.scopeRef, this.authorizedBy, this.notes});

  bool get isEmpty =>
      (client == null || client!.isEmpty) &&
      (scopeRef == null || scopeRef!.isEmpty) &&
      (authorizedBy == null || authorizedBy!.isEmpty) &&
      (notes == null || notes!.isEmpty);

  factory Engagement.import(Map<String, dynamic> data) => Engagement(
        client: data['client'] as String?,
        scopeRef: data['scopeRef'] as String?,
        authorizedBy: data['authorizedBy'] as String?,
        notes: data['notes'] as String?,
      );

  Map<String, dynamic> export() => {
        if (client != null && client!.isNotEmpty) 'client': client,
        if (scopeRef != null && scopeRef!.isNotEmpty) 'scopeRef': scopeRef,
        if (authorizedBy != null && authorizedBy!.isNotEmpty)
          'authorizedBy': authorizedBy,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };
}

class CardSave {
  String id;
  String uid;
  int sak;
  Uint8List atqa;
  Uint8List ats;
  String name;
  TagType tag;
  List<Uint8List> data;
  CardSaveExtra extraData;
  Color color;
  String? folderId;
  // Case-manager additions (all optional; upstream bundles load unchanged).
  CaptureLocation? location;
  List<CardMedia> media;
  Engagement? engagement;
  String? capturedAt; // ISO-8601 UTC
  String? capturedBy;

  factory CardSave.fromJson(String json) {
    Map<String, dynamic> data = jsonDecode(json);
    final id = data['id'] as String;
    final uid = data['uid'] as String;
    final sak = data['sak'] as int;
    final atqa = List<int>.from(data['atqa'] as List<dynamic>);
    final ats = List<int>.from((data['ats'] ?? []) as List<dynamic>);
    final name = data['name'] as String;
    final tag = getTagTypeByValue(data['tag']);
    final extraData = CardSaveExtra.import(data['extra'] ?? {});
    final color =
        data['color'] == null ? Colors.deepOrange : hexToColor(data['color']);
    final folderId = data['folderId'] as String?;
    List<Uint8List> tagData = (data['data'] as List<dynamic>)
        .map((e) => Uint8List.fromList(List<int>.from(e)))
        .toList();

    final location = data['location'] != null
        ? CaptureLocation.import(data['location'] as Map<String, dynamic>)
        : null;
    final media = (data['media'] as List<dynamic>? ?? [])
        .map((e) => CardMedia.import(e as Map<String, dynamic>))
        .toList();
    final engagement = data['engagement'] != null
        ? Engagement.import(data['engagement'] as Map<String, dynamic>)
        : null;

    return CardSave(
        id: id,
        uid: uid,
        sak: sak,
        name: name,
        tag: tag,
        data: tagData,
        color: color,
        folderId: folderId,
        extraData: extraData,
        ats: Uint8List.fromList(ats),
        atqa: Uint8List.fromList(atqa),
        location: location,
        media: media,
        engagement: engagement,
        capturedAt: data['capturedAt'] as String?,
        capturedBy: data['capturedBy'] as String?);
  }

  String toJson() {
    return jsonEncode({
      'id': id,
      'uid': uid,
      'sak': sak,
      'atqa': atqa.toList(),
      'ats': ats.toList(),
      'name': name,
      'tag': tag.value,
      'color': colorToHex(color),
      'data': data.map((data) => data.toList()).toList(),
      'extra': extraData.export(),
      if (folderId != null) 'folderId': folderId,
      if (location != null) 'location': location!.export(),
      if (media.isNotEmpty)
        'media': media.map((m) => m.export()).toList(),
      if (engagement != null && !engagement!.isEmpty)
        'engagement': engagement!.export(),
      if (capturedAt != null) 'capturedAt': capturedAt,
      if (capturedBy != null) 'capturedBy': capturedBy,
    });
  }

  CardSave({
    String? id,
    required this.uid,
    required this.name,
    required this.tag,
    int? sak,
    Uint8List? atqa,
    Uint8List? ats,
    CardSaveExtra? extraData,
    this.color = Colors.deepOrange,
    this.folderId,
    this.data = const [],
    this.location,
    List<CardMedia>? media,
    this.engagement,
    this.capturedAt,
    this.capturedBy,
  })  : id = id ?? const Uuid().v4(),
        sak = sak ?? 0,
        atqa = atqa ?? Uint8List(0),
        ats = ats ?? Uint8List(0),
        media = media ?? [],
        extraData = extraData ?? CardSaveExtra();
}

class CardFolder {
  String id;
  String name;
  Color color;
  String? parentId;

  CardFolder({
    String? id,
    required this.name,
    this.color = Colors.deepOrange,
    this.parentId,
  }) : id = id ?? const Uuid().v4();

  factory CardFolder.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    return CardFolder(
      id: data['id'] as String,
      name: data['name'] as String,
      color: data['color'] == null
          ? Colors.deepOrange
          : hexToColor(data['color'] as String),
      parentId: data['parentId'] as String?,
    );
  }

  String toJson() => jsonEncode({
        'id': id,
        'name': name,
        'color': colorToHex(color),
        if (parentId != null) 'parentId': parentId,
      });
}

/// Versioned Chameleon Ultra GUI folder interchange format.
class CardFolderBundle {
  final String rootFolderId;
  final List<CardFolder> folders;
  final List<CardSave> cards;

  CardFolderBundle({
    required this.rootFolderId,
    required this.folders,
    required this.cards,
  });

  factory CardFolderBundle.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    if (data['format'] != 'chameleon-ultra-gui-folder' ||
        data['version'] != 1) {
      throw const FormatException('Unsupported folder file');
    }
    return CardFolderBundle(
      rootFolderId: data['rootFolderId'] as String,
      folders: (data['folders'] as List<dynamic>)
          .map((item) => CardFolder.fromJson(jsonEncode(item)))
          .toList(),
      cards: (data['cards'] as List<dynamic>)
          .map((item) => CardSave.fromJson(jsonEncode(item)))
          .toList(),
    );
  }

  String toJson() => jsonEncode({
        'format': 'chameleon-ultra-gui-folder',
        'version': 1,
        'rootFolderId': rootFolderId,
        'folders':
            folders.map((folder) => jsonDecode(folder.toJson())).toList(),
        'cards': cards.map((card) => jsonDecode(card.toJson())).toList(),
      });
}

class CardSaveExtra {
  Uint8List ultralightSignature;
  Uint8List ultralightVersion;
  List<int> ultralightCounters;

  factory CardSaveExtra.import(Map<String, dynamic> data) {
    List<int> readBytes(Map<String, dynamic> data, String key) {
      return List<int>.from(
          data[key] != null ? data[key] as List<dynamic> : []);
    }

    final ultralightSignature = readBytes(data, 'ultralightSignature');
    final ultralightVersion = readBytes(data, 'ultralightVersion');
    final ultralightCounters = data['ultralightCounters'] != null
        ? List<int>.from(data['ultralightCounters'] as List<dynamic>)
        : <int>[];

    return CardSaveExtra(
        ultralightSignature: Uint8List.fromList(ultralightSignature),
        ultralightVersion: Uint8List.fromList(ultralightVersion),
        ultralightCounters: ultralightCounters);
  }

  Map<String, dynamic> export() {
    Map<String, dynamic> json = {};

    if (ultralightSignature.isNotEmpty) {
      json['ultralightSignature'] = ultralightSignature;
    }

    if (ultralightVersion.isNotEmpty) {
      json['ultralightVersion'] = ultralightVersion;
    }

    if (ultralightCounters.isNotEmpty) {
      json['ultralightCounters'] = ultralightCounters;
    }

    return json;
  }

  CardSaveExtra(
      {Uint8List? ultralightSignature,
      Uint8List? ultralightVersion,
      List<int>? ultralightCounters})
      : ultralightSignature = ultralightSignature ?? Uint8List(0),
        ultralightVersion = ultralightVersion ?? Uint8List(0),
        ultralightCounters = ultralightCounters ?? <int>[];
}

class SharedPreferencesProvider extends ChangeNotifier {
  SharedPreferencesProvider._privateConstructor();

  static final SharedPreferencesProvider _instance =
      SharedPreferencesProvider._privateConstructor();

  factory SharedPreferencesProvider() {
    return _instance;
  }

  late SharedPreferences _sharedPreferences;

  Future<void> load() async {
    _sharedPreferences = await SharedPreferences.getInstance();
  }

  ThemeMode getTheme() {
    final themeValue = _sharedPreferences.getInt('app_theme') ?? 0;
    return ThemeMode.values[themeValue];
  }

  void setTheme(ThemeMode theme) {
    _sharedPreferences.setInt('app_theme', theme.index);
  }

  bool getSideBarAutoExpansion() {
    return _sharedPreferences.getBool('sidebar_auto_expanded') ?? true;
  }

  bool getSideBarExpanded() {
    return _sharedPreferences.getBool('sidebar_expanded') ?? false;
  }

  int getSideBarExpandedIndex() {
    return _sharedPreferences.getInt('sidebar_expanded_index') ?? 1;
  }

  void setSideBarAutoExpansion(bool autoExpanded) {
    _sharedPreferences.setBool('sidebar_auto_expanded', autoExpanded);
  }

  void setSideBarExpanded(bool expanded) {
    _sharedPreferences.setBool('sidebar_expanded', expanded);
  }

  void setSideBarExpandedIndex(int index) {
    _sharedPreferences.setInt('sidebar_expanded_index', index);
  }

  int getThemeColorIndex() {
    return _sharedPreferences.getInt('app_theme_color') ?? 0;
  }

  MaterialColor getThemeColor() {
    return colors.getThemeColor(getThemeColorIndex());
  }

  Color getThemeComplementaryColor() {
    final themeMode = _sharedPreferences.getInt('app_theme') ?? 2;
    return colors.getThemeComplementary(themeMode, getThemeColorIndex());
  }

  void setThemeColor(int color) {
    _sharedPreferences.setInt('app_theme_color', color);
  }

  bool isDebugMode() {
    return _sharedPreferences.getBool('debug') ?? false;
  }

  void setDebugMode(bool value) {
    _sharedPreferences.setBool('debug', value);
  }

  bool isEmulatedChameleon() {
    return _sharedPreferences.getBool('emulate_device') ?? false;
  }

  void setEmulatedChameleon(bool value) {
    _sharedPreferences.setBool('emulate_device', value);
  }

  List<Dictionary> getDictionaries({int keyLength = 0}) {
    List<Dictionary> output = [];
    final data = _sharedPreferences.getStringList('dictionaries') ?? [];
    for (var dictionary in data) {
      Dictionary dict = Dictionary.fromJson(dictionary);
      if (keyLength == 0 || dict.keyLength == keyLength) {
        output.add(dict);
      }
    }
    return output;
  }

  void setDictionaries(List<Dictionary> dictionaries) {
    List<String> output = [];
    for (var dictionary in dictionaries) {
      if (dictionary.id != "") {
        // system empty dictionary, never save it
        output.add(dictionary.toJson());
      }
    }
    _sharedPreferences.setStringList('dictionaries', output);
  }

  List<DictionaryFolder> getDictionaryFolders() {
    final data = _sharedPreferences.getStringList('dictionary_folders') ?? [];
    return data.map(DictionaryFolder.fromJson).toList();
  }

  void setDictionaryFolders(List<DictionaryFolder> folders) {
    _sharedPreferences.setStringList(
      'dictionary_folders',
      folders.map((folder) => folder.toJson()).toList(),
    );
  }

  List<CardSave> getCards() {
    List<CardSave> output = [];
    final data = _sharedPreferences.getStringList('cards') ?? [];
    for (var tag in data) {
      output.add(CardSave.fromJson(tag));
    }
    return output;
  }

  void setCards(List<CardSave> cards) {
    List<String> output = [];
    for (var card in cards) {
      output.add(card.toJson());
    }
    _sharedPreferences.setStringList('cards', output);
  }

  List<CardFolder> getCardFolders() {
    final data = _sharedPreferences.getStringList('card_folders') ?? [];
    return data.map(CardFolder.fromJson).toList();
  }

  void setCardFolders(List<CardFolder> folders) {
    _sharedPreferences.setStringList(
      'card_folders',
      folders.map((folder) => folder.toJson()).toList(),
    );
  }

  void setLocale(Locale loc) {
    for (var locale in AppLocalizations.supportedLocales) {
      if (locale.toLanguageTag().toLowerCase() ==
          loc.toLanguageTag().toLowerCase()) {
        _sharedPreferences.setString('locale', loc.toLanguageTag());
        notifyListeners();
        return;
      }
    }
  }

  String getLocaleString() {
    return _sharedPreferences.getString("locale") ?? "en";
  }

  Locale getLocale() {
    final localeId = getLocaleString();
    Locale locale;
    if (localeId.contains("-")) {
      final [lcode, ccode] = localeId.toString().split("-");
      locale = Locale(lcode, ccode);
    } else {
      locale = Locale(localeId);
    }
    if (!AppLocalizations.supportedLocales.contains(locale)) {
      return const Locale('en');
    } else {
      return locale;
    }
  }

  void clearLocale() {
    _sharedPreferences.setString('locale', "en");
    notifyListeners();
  }

  bool isDebugLogging() {
    return _sharedPreferences.getBool('debug_logging') ?? false;
  }

  void setDebugLogging(bool value) {
    _sharedPreferences.setBool('debug_logging', value);
  }

  void addLogLine(String value) {
    List<String> rows =
        _sharedPreferences.getStringList('debug_logging_value') ?? [];
    rows.add(value);

    if (rows.length > 5000) {
      rows.removeAt(0);
    }

    _sharedPreferences.setStringList('debug_logging_value', rows);
  }

  void clearLogLines() {
    _sharedPreferences.setStringList('debug_logging_value', []);
  }

  List<String> getLogLines() {
    return _sharedPreferences.getStringList('debug_logging_value') ?? [];
  }

  String dumpSettingsToJson() {
    Map<String, dynamic> settingsMap = {};

    for (var key in _sharedPreferences.getKeys()) {
      if (key == "debug_logging_value") {
        continue;
      }
      var value = _sharedPreferences.get(key) as dynamic;
      if (value == null) {
        continue;
      }
      if (value is List) {
        // this hack is needed in order to output proper json with objects instead of objects-in-strings
        value = value.map((e) => jsonDecode(e)).toList();
      }
      settingsMap[key] = value;
    }

    return jsonEncode(settingsMap);
  }

  void restoreSettingsFromJson(String jsonSettings) {
    Map<String, dynamic> settingsMap = jsonDecode(jsonSettings);

    for (var key in settingsMap.keys) {
      dynamic value = settingsMap[key];

      if (value == null) {
        continue;
      }
      switch (value) {
        case String s:
          _sharedPreferences.setString(key, s);
          break;
        case int i:
          _sharedPreferences.setInt(key, i);
          break;
        case double d:
          _sharedPreferences.setDouble(key, d);
          break;
        case bool b:
          _sharedPreferences.setBool(key, b);
          break;
        case List l:
          // this is the reverse of the hack above :)
          _sharedPreferences.setStringList(
              key, l.map((e) => jsonEncode(e)).toList());
          break;
        default:
          break;
      }
    }
  }

  bool getConfirmDelete() {
    return _sharedPreferences.getBool('confirm_delete') ?? true;
  }

  void setConfirmDelete(bool value) {
    _sharedPreferences.setBool('confirm_delete', value);
  }

  bool getAutoScanEnabled() {
    return _sharedPreferences.getBool('auto_scan_enabled') ?? true;
  }

  void setAutoScanEnabled(bool value) {
    _sharedPreferences.setBool('auto_scan_enabled', value);
  }

  bool getAutoConnectFirstFoundDevice() {
    return _sharedPreferences.getBool('auto_connect_first_found') ?? false;
  }

  void setAutoConnectFirstFoundDevice(bool value) {
    _sharedPreferences.setBool('auto_connect_first_found', value);
  }
}
