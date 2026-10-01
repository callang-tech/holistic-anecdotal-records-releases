import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum PersonalizedImage {
  background(
      'Home Background', 'background.png', 'assets/images/home_background.jpg'),
  header(
      'Report Header', 'report_header.png', 'assets/images/SchoolHeader.PNG'),
  footer(
      'Report Footer', 'report_footer.png', 'assets/images/SchoolFooter.PNG');

  const PersonalizedImage(this.label, this.fileName, this.defaultAsset);
  final String label;
  final String fileName;
  final String defaultAsset;

  int? get requiredHeight => switch (this) {
        header => 317,
        footer => 154,
        background => null,
      };

  String get controlLabel => switch (this) {
        header => 'Header',
        footer => 'Footer',
        background => 'Background',
      };
}

/// Owns only imported images; packaged assets remain the fallback.
class ImagePersonalizationService extends ChangeNotifier {
  ImagePersonalizationService({Directory? directoryOverride})
      : _directoryOverride = directoryOverride;

  static final instance = ImagePersonalizationService();
  final Directory? _directoryOverride;

  Future<Directory> customizationDirectory() async {
    if (_directoryOverride != null) return _directoryOverride;
    final documents = await getApplicationDocumentsDirectory();
    return Directory(
        p.join(documents.path, 'HolisticAnecdotalRecords', 'customization'));
  }

  Future<File> managedFile(PersonalizedImage kind) async {
    final path = p.join((await customizationDirectory()).path, kind.fileName);
    final jpeg = File(p.setExtension(path, '.jpg'));
    if (kind.requiredHeight != null && await jpeg.exists()) return jpeg;
    return File(path);
  }

  Future<Uint8List?> customBytes(PersonalizedImage kind) async {
    try {
      final file = await managedFile(kind);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (!_isPng(bytes) && !_isJpeg(bytes)) return null;
      final image = await _decode(bytes);
      try {
        _validateDimensions(kind, image);
      } finally {
        image.dispose();
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> imageBytes(PersonalizedImage kind) async =>
      await customBytes(kind) ??
      (await rootBundle.load(kind.defaultAsset)).buffer.asUint8List();

  Future<bool> hasCustomization(PersonalizedImage kind) async =>
      (await customBytes(kind)) != null;

  Future<bool> hasManagedCopy(PersonalizedImage kind) async =>
      await (await managedFile(kind)).exists();

  Future<void> importFile(PersonalizedImage kind, String sourcePath) async {
    final extension = p.extension(sourcePath).toLowerCase();
    if (!{'.png', '.jpg', '.jpeg'}.contains(extension)) {
      throw const FormatException('Choose a PNG or JPEG image.');
    }
    await importBytes(kind, await File(sourcePath).readAsBytes());
  }

  Future<void> importBytes(PersonalizedImage kind, Uint8List bytes) async {
    if (!_isPng(bytes) && !_isJpeg(bytes)) {
      throw const FormatException('Choose a PNG or JPEG image.');
    }
    // Validate before creating directories or writing any bytes.
    final image = await _decode(bytes);
    late final Uint8List savedBytes;
    try {
      _validateDimensions(kind, image);
      if (kind.requiredHeight != null) {
        savedBytes = bytes;
      } else {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) {
          throw const FormatException('Could not read this image.');
        }
        savedBytes = png.buffer.asUint8List();
      }
    } finally {
      image.dispose();
    }
    final directory = await customizationDirectory();
    await directory.create(recursive: true);
    final previous = await managedFile(kind);
    final destination = File(p.join(
        directory.path,
        kind.requiredHeight != null && _isJpeg(bytes)
            ? p.setExtension(kind.fileName, '.jpg')
            : kind.fileName));
    final temporary = File('${destination.path}.tmp');
    try {
      await temporary.writeAsBytes(savedBytes, flush: true);
      await temporary.rename(destination.path);
      if (previous.path != destination.path && await previous.exists()) {
        await previous.delete();
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    notifyListeners();
  }

  Future<void> restoreDefault(PersonalizedImage kind) async {
    final file = await managedFile(kind);
    if (await file.exists()) await file.delete();
    if (kind.requiredHeight != null) {
      final png =
          File(p.join((await customizationDirectory()).path, kind.fileName));
      if (await png.exists()) await png.delete();
    }
    notifyListeners();
  }

  void _validateDimensions(PersonalizedImage kind, ui.Image image) {
    final height = kind.requiredHeight;
    if (height != null && (image.width != 1270 || image.height != height)) {
      throw FormatException(
          '${kind.label} requires exactly 1270 x $height pixels. '
          'Selected image is ${image.width} x ${image.height} pixels.');
    }
  }

  Future<ui.Image> _decode(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      throw const FormatException(
          'The selected image is unreadable or unsupported.');
    }
  }

  bool _isPng(Uint8List bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a;

  bool _isJpeg(Uint8List bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff;
}
