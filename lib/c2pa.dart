import 'dart:typed_data';

import 'c2pa_platform_interface.dart';

enum SigningAlgorithm {
  es256,
  es384,
  es512,
  ps256,
  ps384,
  ps512,
  ed25519,
}

class SignerInfo {
  final SigningAlgorithm algorithm;
  final String certificatePem;
  final String privateKeyPem;
  final String? tsaUrl;

  SignerInfo({
    required this.algorithm,
    required this.certificatePem,
    required this.privateKeyPem,
    this.tsaUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'algorithm': algorithm.name,
      'certificatePem': certificatePem,
      'privateKeyPem': privateKeyPem,
      'tsaUrl': tsaUrl,
    };
  }
}

class SignResult {
  final Uint8List signedData;
  final Uint8List? manifestBytes;

  SignResult({required this.signedData, this.manifestBytes});
}

class C2pa {
  Future<String?> getPlatformVersion() {
    return C2paPlatform.instance.getPlatformVersion();
  }

  Future<String?> getVersion() {
    return C2paPlatform.instance.getVersion();
  }

  Future<String?> readFile(String path) {
    return C2paPlatform.instance.readFile(path);
  }

  Future<String?> readBytes(Uint8List data, String mimeType) {
    return C2paPlatform.instance.readBytes(data, mimeType);
  }

  Future<SignResult> signBytes({
    required Uint8List sourceData,
    required String mimeType,
    required String manifestJson,
    required SignerInfo signerInfo,
  }) {
    return C2paPlatform.instance.signBytes(
      sourceData: sourceData,
      mimeType: mimeType,
      manifestJson: manifestJson,
      signerInfo: signerInfo,
    );
  }

  Future<void> signFile({
    required String sourcePath,
    required String destPath,
    required String manifestJson,
    required SignerInfo signerInfo,
  }) {
    return C2paPlatform.instance.signFile(
      sourcePath: sourcePath,
      destPath: destPath,
      manifestJson: manifestJson,
      signerInfo: signerInfo,
    );
  }
}
