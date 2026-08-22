import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Fakes the path_provider plugin channel for `flutter test`, which has no
/// real platform to answer it. Points every path at [directory] so tests can
/// read/write through a real (temp) filesystem without touching the device.
class FakePathProviderPlatform extends PathProviderPlatform {
  FakePathProviderPlatform(this.directory);

  final String directory;

  @override
  Future<String?> getApplicationSupportPath() async => directory;

  @override
  Future<String?> getApplicationDocumentsPath() async => directory;

  @override
  Future<String?> getTemporaryPath() async => directory;
}
