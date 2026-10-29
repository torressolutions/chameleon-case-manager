import 'dart:io';

import 'package:chameleonultragui/helpers/case_store.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

/// Walrus-style case section shown in the card view: capture location + photos
/// and record engagement/authorization metadata, all stored in the card's
/// on-disk case folder. Mutates a copy of [card] and reports it via [onChanged];
/// the parent is responsible for persisting (setCards + CaseStore.writeCardFiles).
class CaseDetailsSection extends StatefulWidget {
  final CardSave card;
  final void Function(CardSave updated) onChanged;

  const CaseDetailsSection({
    super.key,
    required this.card,
    required this.onChanged,
  });

  @override
  State<CaseDetailsSection> createState() => _CaseDetailsSectionState();
}

class _CaseDetailsSectionState extends State<CaseDetailsSection> {
  bool _busy = false;

  CardSave get _card => widget.card;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _captureLocation() async {
    setState(() => _busy = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack('Location services are disabled.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _snack('Location permission denied.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _card.location = CaptureLocation(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
        timestamp: pos.timestamp.toUtc().toIso8601String(),
      );
      widget.onChanged(_card);
      _snack('Location captured.');
    } catch (e) {
      _snack('Could not get location: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMap() async {
    final loc = _card.location;
    if (loc == null) return;
    final uri = Uri.parse(
        'https://www.openstreetmap.org/?mlat=${loc.latitude}&mlon=${loc.longitude}#map=18/${loc.latitude}/${loc.longitude}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _addPhoto(ImageSource source) async {
    setState(() => _busy = true);
    try {
      final picker = ImagePicker();
      final XFile? shot = await picker.pickImage(source: source, imageQuality: 85);
      if (shot == null) return;
      final rel = await CaseStore.addPhoto(_card.id, File(shot.path));
      _card.media.add(CardMedia(
        filename: rel,
        kind: 'photo',
        capturedAt: DateTime.now().toUtc().toIso8601String(),
      ));
      widget.onChanged(_card);
    } catch (e) {
      _snack('Could not add photo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto(CardMedia media) async {
    _card.media.remove(media);
    widget.onChanged(_card);
    setState(() {});
  }

  Future<void> _editEngagement() async {
    final eng = _card.engagement;
    final client = TextEditingController(text: eng?.client ?? '');
    final scope = TextEditingController(text: eng?.scopeRef ?? '');
    final auth = TextEditingController(text: eng?.authorizedBy ?? '');
    final notes = TextEditingController(text: eng?.notes ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Engagement'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: client,
                  decoration: const InputDecoration(labelText: 'Client')),
              TextField(
                  controller: scope,
                  decoration: const InputDecoration(
                      labelText: 'Scope / authorization ref')),
              TextField(
                  controller: auth,
                  decoration:
                      const InputDecoration(labelText: 'Authorized by')),
              TextField(
                  controller: notes,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );

    if (saved == true) {
      _card.engagement = Engagement(
        client: client.text,
        scopeRef: scope.text,
        authorizedBy: auth.text,
        notes: notes.text,
      );
      widget.onChanged(_card);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = _card.location;
    final eng = _card.engagement;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),

        // Engagement
        Row(
          children: [
            const Expanded(
                child: Text('Engagement',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            IconButton(
                tooltip: 'Edit engagement',
                onPressed: _busy ? null : _editEngagement,
                icon: const Icon(Icons.assignment_outlined)),
          ],
        ),
        if (eng != null && !eng.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text([
              if (eng.client?.isNotEmpty ?? false) 'Client: ${eng.client}',
              if (eng.scopeRef?.isNotEmpty ?? false) 'Scope: ${eng.scopeRef}',
              if (eng.authorizedBy?.isNotEmpty ?? false)
                'Authorized by: ${eng.authorizedBy}',
            ].join('\n')),
          )
        else
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 4),
            child: Text('Not set', style: TextStyle(color: Colors.grey)),
          ),

        // Location
        Row(
          children: [
            const Expanded(
                child: Text('Location',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            if (loc != null)
              IconButton(
                  tooltip: 'Open map',
                  onPressed: _openMap,
                  icon: const Icon(Icons.map_outlined)),
            IconButton(
                tooltip: 'Capture GPS',
                onPressed: _busy ? null : _captureLocation,
                icon: const Icon(Icons.my_location)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: loc != null
              ? Text(
                  '${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)}'
                  '${loc.accuracy != null ? '  (±${loc.accuracy!.toStringAsFixed(0)} m)' : ''}')
              : const Text('Not set', style: TextStyle(color: Colors.grey)),
        ),

        // Photos
        Row(
          children: [
            const Expanded(
                child: Text('Photos',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            IconButton(
                tooltip: 'Take photo',
                onPressed: _busy ? null : () => _addPhoto(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined)),
            IconButton(
                tooltip: 'Add from gallery',
                onPressed: _busy ? null : () => _addPhoto(ImageSource.gallery),
                icon: const Icon(Icons.add_photo_alternate_outlined)),
          ],
        ),
        if (_card.media.isEmpty)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text('No photos', style: TextStyle(color: Colors.grey)),
          )
        else
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _card.media.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final media = _card.media[i];
                return FutureBuilder<File?>(
                  future: CaseStore.photoFile(_card.id, media.filename),
                  builder: (context, snap) {
                    final file = snap.data;
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: file != null
                              ? Image.file(file,
                                  width: 92, height: 92, fit: BoxFit.cover)
                              : Container(
                                  width: 92,
                                  height: 92,
                                  color: Colors.black12,
                                  child: const Icon(Icons.broken_image)),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: GestureDetector(
                            onTap: () => _removePhoto(media),
                            child: Container(
                              decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.close,
                                  size: 18, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
