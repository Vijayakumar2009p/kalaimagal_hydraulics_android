import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../theme.dart';
import 'common.dart';

/// Photos chosen on the phone, with one of them marked as the profile picture.
class PhotoSelection {
  final List<String> paths = [];

  /// Index in [paths] of the profile picture (the first photo by default).
  int profile = 0;

  static const int max = 5;

  bool get isEmpty => paths.isEmpty;
  bool get isFull => paths.length >= max;
  int? get profileIndex => paths.isEmpty ? null : profile.clamp(0, paths.length - 1);

  void add(String path) => paths.add(path);

  void removeAt(int i) {
    paths.removeAt(i);
    if (profile == i) {
      profile = 0;
    } else if (profile > i) {
      profile--;
    }
  }
}

/// Camera or gallery, chosen in a small sheet. Returns the picked file path.
Future<String?> pickPhoto(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Add customer photo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, color: VV.blue, size: 28),
            title: const Text('Take photo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            subtitle: const Text('Use the camera now'),
            onTap: () => Navigator.pop(c, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: VV.blue, size: 28),
            title: const Text('Choose from gallery', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            subtitle: const Text('Pick a photo already on this phone'),
            onTap: () => Navigator.pop(c, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null) return null;
  try {
    // Shrunk on the phone (about 300-500 KB) so the upload stays light.
    final photo = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 70);
    return photo?.path;
  } on PlatformException catch (e) {
    if (context.mounted) {
      final where = source == ImageSource.camera ? 'camera' : 'gallery';
      showMessage(context, 'Could not open $where: ${e.message ?? e.code}', error: true);
    }
    return null;
  }
}

/// Horizontal row of photos: tap one to make it the profile picture,
/// ✕ removes it. The last tile adds another photo (up to [PhotoSelection.max]).
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({
    super.key,
    required this.selection,
    required this.onChanged,
    this.enabled = true,
    this.chooseProfile = true,
  });

  final PhotoSelection selection;
  final VoidCallback onChanged;
  final bool enabled;

  /// Show the "Profile" star and let a tap pick the profile picture.
  final bool chooseProfile;

  static const double _w = 112;
  static const double _h = 112;

  Future<void> _add(BuildContext context) async {
    final path = await pickPhoto(context);
    if (path == null) return;
    selection.add(path);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (selection.isEmpty) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
        onPressed: enabled ? () => _add(context) : null,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Add photo'),
      );
    }
    final profile = chooseProfile ? selection.profileIndex : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _h,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: selection.paths.length + (selection.isFull ? 0 : 1),
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              if (i == selection.paths.length) return _addTile(context);
              return _photoTile(i, i == profile);
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          !chooseProfile
              ? '${selection.paths.length} of ${PhotoSelection.max} photos.'
              : selection.paths.length > 1
              ? 'Tap a photo to make it the profile picture. ${selection.paths.length} of ${PhotoSelection.max} photos.'
              : 'This photo will be the profile picture. You can add up to ${PhotoSelection.max}.',
          style: const TextStyle(fontSize: 12, color: VV.inkMuted),
        ),
      ],
    );
  }

  Widget _addTile(BuildContext context) => InkWell(
    onTap: enabled ? () => _add(context) : null,
    borderRadius: BorderRadius.circular(VV.radiusMd),
    child: Container(
      width: _w,
      height: _h,
      decoration: BoxDecoration(
        border: Border.all(color: VV.blue.withValues(alpha: 0.5), width: 1.5),
        borderRadius: BorderRadius.circular(VV.radiusMd),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo_outlined, color: VV.blue, size: 28),
          SizedBox(height: 6),
          Text(
            'Add more',
            style: TextStyle(color: VV.blue, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );

  Widget _photoTile(int i, bool isProfile) => SizedBox(
    width: _w,
    height: _h,
    child: Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: enabled && chooseProfile
                ? () {
                    selection.profile = i;
                    onChanged();
                  }
                : null,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(VV.radiusMd),
                border: Border.all(color: isProfile ? VV.gold : Colors.transparent, width: 3),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(VV.radiusMd - 2),
                child: Image.file(File(selection.paths[i]), fit: BoxFit.cover, cacheWidth: 300),
              ),
            ),
          ),
        ),
        if (isProfile)
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(color: VV.gold, borderRadius: BorderRadius.circular(6)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, size: 14, color: Colors.white),
                  SizedBox(width: 3),
                  Text(
                    'Profile',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          right: 4,
          top: 4,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled
                  ? () {
                      selection.removeAt(i);
                      onChanged();
                    }
                  : null,
              child: const Padding(
                padding: EdgeInsets.all(5),
                child: Icon(Icons.close, size: 18, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
