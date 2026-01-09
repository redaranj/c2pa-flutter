import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'c2pa.dart';
import 'c2pa_method_channel.dart';

abstract class C2paPlatform extends PlatformInterface {
  C2paPlatform() : super(token: _token);

  static final Object _token = Object();

  static C2paPlatform _instance = MethodChannelC2pa();

  static C2paPlatform get instance => _instance;

  static set instance(C2paPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  Future<String?> getVersion() {
    throw UnimplementedError('getVersion() has not been implemented.');
  }

  Future<String?> readFile(String path) {
    throw UnimplementedError('readFile() has not been implemented.');
  }

  Future<String?> readBytes(Uint8List data, String mimeType) {
    throw UnimplementedError('readBytes() has not been implemented.');
  }

  Future<SignResult> signBytes({
    required Uint8List sourceData,
    required String mimeType,
    required String manifestJson,
    required SignerInfo signerInfo,
  }) {
    throw UnimplementedError('signBytes() has not been implemented.');
  }

  Future<void> signFile({
    required String sourcePath,
    required String destPath,
    required String manifestJson,
    required SignerInfo signerInfo,
  }) {
    throw UnimplementedError('signFile() has not been implemented.');
  }
}
