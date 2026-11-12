import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/customer.dart';
import '../widgets/common.dart';
import '../widgets/photo_strip.dart';

/// Adds photos to an existing customer. They go to the contact's chatter
/// (log note) in Odoo, and the chosen one becomes the profile picture.
class AddPhotosScreen extends StatefulWidget {
  const AddPhotosScreen({super.key, required this.customer});
  final Customer customer;

  @override
  State<AddPhotosScreen> createState() => _AddPhotosScreenState();
}

class _AddPhotosScreenState extends State<AddPhotosScreen> {
  final _photos = PhotoSelection();
  bool _setProfile = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Open the camera/gallery choice straight away.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final path = await pickPhoto(context);
      if (path != null && mounted) setState(() => _photos.add(path));
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final app = AppScope.read(context);
    try {
      final ref = await app.addPhotos(
        widget.customer,
        List.of(_photos.paths),
        _setProfile ? _photos.profileIndex : null,
      );
      if (!mounted) return;
      final waiting = app.pendingByRef(ref);
      showMessage(
        context,
        waiting == null
            ? 'Photos saved in Odoo.'
            : waiting.blocked
            ? 'Odoo refused the photos: ${waiting.lastError}'
            : 'Photos saved on this phone. They will sync when online.',
        error: waiting?.blocked ?? false,
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showMessage(context, 'Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context).resolve(widget.customer);
    return Scaffold(
      appBar: AppBar(title: const Text('Add photos')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                children: [
                  Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('Photos are added to the customer\'s notes in Odoo.', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 20),
                  PhotoStrip(
                    selection: _photos,
                    enabled: !_busy,
                    chooseProfile: _setProfile,
                    onChanged: () => setState(() {}),
                  ),
                  if (!_photos.isEmpty) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _setProfile,
                      onChanged: _busy ? null : (v) => setState(() => _setProfile = v),
                      title: const Text('Use as profile picture', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        _setProfile
                            ? 'Tap a photo to choose. The starred photo replaces the customer\'s picture in Odoo.'
                            : 'Turn on to replace the customer\'s picture in Odoo.',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(64, 52)),
                  onPressed: _busy || _photos.isEmpty ? null : _save,
                  icon: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Icon(Icons.check),
                  label: const Text('Save photos', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
