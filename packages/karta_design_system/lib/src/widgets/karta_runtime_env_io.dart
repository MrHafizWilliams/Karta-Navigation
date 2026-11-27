import 'dart:io' show Platform;

bool get isKartaHeadlessTest => Platform.environment.containsKey('FLUTTER_TEST');
bool get isKartaDesktopWithoutVideoPlugin =>
    Platform.isWindows || Platform.isLinux;
