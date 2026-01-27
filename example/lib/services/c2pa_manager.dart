import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:c2pa_flutter/c2pa.dart';

enum SigningMode {
  defaultCerts,
  custom,
}

class C2paManager extends ChangeNotifier {
  static final C2paManager _instance = C2paManager._internal();
  factory C2paManager() => _instance;
  C2paManager._internal();

  final C2pa _c2pa = C2pa();

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  String? _lastError;
  String? get lastError => _lastError;

  SigningMode _signingMode = SigningMode.defaultCerts;
  SigningMode get signingMode => _signingMode;
  set signingMode(SigningMode mode) {
    _signingMode = mode;
    notifyListeners();
  }

  String? _customCertificate;
  String? _customPrivateKey;

  // Cached default credentials loaded from assets
  String? _defaultCertificate;
  String? _defaultPrivateKey;

  void setCustomCredentials(String certificate, String privateKey) {
    _customCertificate = certificate;
    _customPrivateKey = privateKey;
    notifyListeners();
  }

  bool get hasCustomCredentials =>
      _customCertificate != null && _customPrivateKey != null;

  Future<String?> getVersion() async {
    return await _c2pa.getVersion();
  }

  Future<String?> readManifest(String path) async {
    try {
      return await _c2pa.readFile(path);
    } catch (e) {
      _lastError = e.toString();
      return null;
    }
  }

  Future<String?> readManifestFromBytes(
      Uint8List data, String mimeType) async {
    try {
      return await _c2pa.readBytes(data, mimeType);
    } catch (e) {
      _lastError = e.toString();
      return null;
    }
  }

  /// Load default credentials from assets
  Future<void> _loadDefaultCredentials() async {
    if (_defaultCertificate != null && _defaultPrivateKey != null) {
      return;
    }

    try {
      _defaultCertificate =
          await rootBundle.loadString('assets/test_certs/test_es256_cert.pem');
      _defaultPrivateKey =
          await rootBundle.loadString('assets/test_certs/test_es256_key.pem');
    } catch (e) {
      debugPrint('Failed to load default credentials from assets: $e');
      _lastError = 'Failed to load signing credentials';
    }
  }

  Future<Uint8List?> signImage(Uint8List imageData, String mimeType) async {
    _isProcessing = true;
    _lastError = null;
    notifyListeners();

    ManifestBuilder? builder;
    try {
      final signerInfo = await _getSignerInfo();
      if (signerInfo == null) {
        _lastError = 'No signing credentials available';
        return null;
      }

      // Create the manifest JSON with title, claim_generator, and any assertions
      // These must be set at creation time as the native C2PA library doesn't
      // support modifying them after builder creation.
      final manifestJson = jsonEncode({
        'title': 'Signed Image',
        'claim_generator': 'C2PA Flutter Example/1.0.0',
      });

      builder = await _c2pa.createBuilder(manifestJson);

      // Set intent (supported by native builder API)
      builder.setIntent(ManifestIntent.create, DigitalSourceType.digitalCapture);

      // Add the created action (supported by native builder API)
      builder.addAction(ActionConfig(
        action: 'c2pa.created',
        digitalSourceType: DigitalSourceType.digitalCapture,
      ));

      // Sign the content
      final result = await builder.sign(
        sourceData: imageData,
        mimeType: mimeType,
        signerInfo: signerInfo,
      );

      return result.signedData;
    } catch (e) {
      _lastError = e.toString();
      return null;
    } finally {
      builder?.dispose();
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<SignerInfo?> _getSignerInfo() async {
    switch (_signingMode) {
      case SigningMode.defaultCerts:
        await _loadDefaultCredentials();
        if (_defaultCertificate == null || _defaultPrivateKey == null) {
          return null;
        }
        return SignerInfo(
          algorithm: SigningAlgorithm.es256,
          certificatePem: _defaultCertificate!,
          privateKeyPem: _defaultPrivateKey!,
        );
      case SigningMode.custom:
        if (_customCertificate == null || _customPrivateKey == null) {
          return null;
        }
        return SignerInfo(
          algorithm: SigningAlgorithm.es256,
          certificatePem: _customCertificate!,
          privateKeyPem: _customPrivateKey!,
        );
    }
  }
}
