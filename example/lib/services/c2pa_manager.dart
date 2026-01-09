import 'package:flutter/foundation.dart';
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

  Future<String?> readManifestFromBytes(Uint8List data, String mimeType) async {
    try {
      return await _c2pa.readBytes(data, mimeType);
    } catch (e) {
      _lastError = e.toString();
      return null;
    }
  }

  Future<Uint8List?> signImage(Uint8List imageData, String mimeType) async {
    _isProcessing = true;
    _lastError = null;
    notifyListeners();

    try {
      final signerInfo = _getSignerInfo();
      if (signerInfo == null) {
        _lastError = 'No signing credentials available';
        return null;
      }

      final manifestJson = _buildManifestJson();
      
      final result = await _c2pa.signBytes(
        sourceData: imageData,
        mimeType: mimeType,
        manifestJson: manifestJson,
        signerInfo: signerInfo,
      );

      return result.signedData;
    } catch (e) {
      _lastError = e.toString();
      return null;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  SignerInfo? _getSignerInfo() {
    switch (_signingMode) {
      case SigningMode.defaultCerts:
        return SignerInfo(
          algorithm: SigningAlgorithm.es256,
          certificatePem: _defaultCertificate,
          privateKeyPem: _defaultPrivateKey,
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

  String _buildManifestJson() {
    return '{"claim_generator":"C2PA Flutter Example/1.0.0","title":"Signed Image","assertions":[{"label":"c2pa.actions","data":{"actions":[{"action":"c2pa.created","digitalSourceType":"http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture"}]}}]}';
  }

  static const String _defaultCertificate = '''-----BEGIN CERTIFICATE-----
MIICJjCCAcygAwIBAgIUY0l1hLGgFqaXxsDpVn2sdDTdiU4wCgYIKoZIzj0EAwIw
WTELMAkGA1UEBhMCVVMxEzARBgNVBAgMCkNhbGlmb3JuaWExEjAQBgNVBAcMCVNv
bWV3aGVyZTEOMAwGA1UECgwFQzJQQTExETAPBgNVBAMMCHRlc3QuY29tMB4XDTI0
MDEwMTAwMDAwMFoXDTI1MDEwMTAwMDAwMFowWTELMAkGA1UEBhMCVVMxEzARBgNV
BAgMCkNhbGlmb3JuaWExEjAQBgNVBAcMCVNvbWV3aGVyZTEOMAwGA1UECgwFQzJQ
QTExETAPBgNVBAMMCHRlc3QuY29tMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE
qKmZjmXK5MXN+B/U0XE2BhW3XBv3LL0tGJEwBgW0rUqIg0n0i0bKVk2O2G0hk8hO
P3G4ChEkMy8LH0Oe3/tFnqNjMGEwHQYDVR0OBBYEFMVzb4Gp7gLJD/gR9G+vL2Pf
zV0dMB8GA1UdIwQYMBaAFMVzb4Gp7gLJD/gR9G+vL2PfzV0dMA8GA1UdEwEB/wQF
MAMBAf8wDgYDVR0PAQH/BAQDAgGGMAoGCCqGSM49BAMCA0gAMEUCIQCqRN0W8MHh
5gLREQGhtrHjLm9cXzBBmWD/U1dDcpzUxQIgH8R0gNTPYSQnPV0G0YYDcGZhJ1Zk
upmIpfJaxuw/VzE=
-----END CERTIFICATE-----''';

  static const String _defaultPrivateKey = '''-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgevZzL1gdAFr88hb2
OF/2NxApJCzGCEDdfSp6VQO30hyhRANCAAT+PnBQOggMVBsGXjH/ZuO6fZK0zPJ3
X4MYPCbKp3L6L0Gj2Z3hJNzI0pPTEsVYrGlNvlMG7VL/rl3hT2VH51Bt
-----END PRIVATE KEY-----''';
}
