import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'c2pa.dart';
import 'c2pa_platform_interface.dart';

class MethodChannelC2pa extends C2paPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('org.guardianproject.c2pa');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<String?> getVersion() async {
    final version = await methodChannel.invokeMethod<String>('getVersion');
    return version;
  }

  @override
  Future<String?> readFile(String path) async {
    final result = await methodChannel.invokeMethod<String>('readFile', {
      'path': path,
    });
    return result;
  }

  @override
  Future<String?> readBytes(Uint8List data, String mimeType) async {
    final result = await methodChannel.invokeMethod<String>('readBytes', {
      'data': data,
      'mimeType': mimeType,
    });
    return result;
  }

  @override
  Future<SignResult> signBytes({
    required Uint8List sourceData,
    required String mimeType,
    required String manifestJson,
    required SignerInfo signerInfo,
  }) async {
    final result = await methodChannel.invokeMethod<Map>('signBytes', {
      'sourceData': sourceData,
      'mimeType': mimeType,
      'manifestJson': manifestJson,
      'signerInfo': signerInfo.toMap(),
    });
    
    if (result == null) {
      throw PlatformException(code: 'ERROR', message: 'Sign operation returned null');
    }
    
    return SignResult(
      signedData: result['signedData'] as Uint8List,
      manifestBytes: result['manifestBytes'] as Uint8List?,
    );
  }

  @override
  Future<void> signFile({
    required String sourcePath,
    required String destPath,
    required String manifestJson,
    required SignerInfo signerInfo,
  }) async {
    await methodChannel.invokeMethod<void>('signFile', {
      'sourcePath': sourcePath,
      'destPath': destPath,
      'manifestJson': manifestJson,
      'signerInfo': signerInfo.toMap(),
    });
  }
}
