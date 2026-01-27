import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:c2pa_flutter/c2pa.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signing modes available in the example app
enum SigningMode {
  /// Use bundled test certificates (PEM)
  defaultCerts('Default Certificates', 'Use included test certificates for development'),

  /// User-provided PEM certificate and key
  customPem('Custom PEM', 'Use your own certificate and private key'),

  /// Callback-based signing (demo)
  callback('Callback Signer', 'Demo callback-based signing with test certificates'),

  /// Platform keystore (Android Keystore / iOS Keychain)
  keystore('Keystore', 'Use platform keystore (Android Keystore / iOS Keychain)'),

  /// Hardware-backed signing (StrongBox / Secure Enclave)
  hardware('Hardware Security', 'Use hardware-backed signing (StrongBox / Secure Enclave)'),

  /// Remote signing service
  remote('Remote Signing', 'Use a remote signing service');

  final String title;
  final String description;

  const SigningMode(this.title, this.description);
}

class C2paManager extends ChangeNotifier {
  static final C2paManager _instance = C2paManager._internal();
  factory C2paManager() => _instance;
  C2paManager._internal() {
    _loadPreferences();
  }

  final C2pa _c2pa = C2pa();

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  String? _lastError;
  String? get lastError => _lastError;

  // Current signing mode
  SigningMode _signingMode = SigningMode.defaultCerts;
  SigningMode get signingMode => _signingMode;
  set signingMode(SigningMode mode) {
    _signingMode = mode;
    _savePreferences();
    notifyListeners();
  }

  // Cached default credentials loaded from assets
  String? _defaultCertificate;
  String? _defaultPrivateKey;

  // Custom PEM credentials
  String? _customCertificate;
  String? _customPrivateKey;

  // Keystore configuration
  String _keystoreKeyAlias = 'c2pa_signing_key';
  String? _keystoreCertificateChain;
  String get keystoreKeyAlias => _keystoreKeyAlias;
  String? get keystoreCertificateChain => _keystoreCertificateChain;
  bool get hasKeystoreConfig => _keystoreCertificateChain != null;

  // Hardware signer configuration
  String _hardwareKeyAlias = 'c2pa_hardware_key';
  String? _hardwareCertificateChain;
  bool _requireBiometric = false;
  String get hardwareKeyAlias => _hardwareKeyAlias;
  String? get hardwareCertificateChain => _hardwareCertificateChain;
  bool get requireBiometric => _requireBiometric;
  bool get hasHardwareConfig => _hardwareCertificateChain != null;

  // Remote signer configuration
  String? _remoteUrl;
  String? _bearerToken;
  String? get remoteUrl => _remoteUrl;
  String? get bearerToken => _bearerToken;
  bool get hasRemoteConfig => _remoteUrl != null && _remoteUrl!.isNotEmpty;

  // Hardware availability cache
  bool? _hardwareAvailable;

  /// Load preferences from storage
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final modeIndex = prefs.getInt('signingMode') ?? 0;
      if (modeIndex >= 0 && modeIndex < SigningMode.values.length) {
        _signingMode = SigningMode.values[modeIndex];
      }

      _customCertificate = prefs.getString('customCertificate');
      _customPrivateKey = prefs.getString('customPrivateKey');

      _keystoreKeyAlias = prefs.getString('keystoreKeyAlias') ?? 'c2pa_signing_key';
      _keystoreCertificateChain = prefs.getString('keystoreCertificateChain');

      _hardwareKeyAlias = prefs.getString('hardwareKeyAlias') ?? 'c2pa_hardware_key';
      _hardwareCertificateChain = prefs.getString('hardwareCertificateChain');
      _requireBiometric = prefs.getBool('requireBiometric') ?? false;

      _remoteUrl = prefs.getString('remoteUrl');
      _bearerToken = prefs.getString('bearerToken');

      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load preferences: $e');
    }
  }

  /// Save preferences to storage
  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setInt('signingMode', _signingMode.index);

      if (_customCertificate != null) {
        await prefs.setString('customCertificate', _customCertificate!);
      }
      if (_customPrivateKey != null) {
        await prefs.setString('customPrivateKey', _customPrivateKey!);
      }

      await prefs.setString('keystoreKeyAlias', _keystoreKeyAlias);
      if (_keystoreCertificateChain != null) {
        await prefs.setString('keystoreCertificateChain', _keystoreCertificateChain!);
      }

      await prefs.setString('hardwareKeyAlias', _hardwareKeyAlias);
      if (_hardwareCertificateChain != null) {
        await prefs.setString('hardwareCertificateChain', _hardwareCertificateChain!);
      }
      await prefs.setBool('requireBiometric', _requireBiometric);

      if (_remoteUrl != null) {
        await prefs.setString('remoteUrl', _remoteUrl!);
      }
      if (_bearerToken != null) {
        await prefs.setString('bearerToken', _bearerToken!);
      }
    } catch (e) {
      debugPrint('Failed to save preferences: $e');
    }
  }

  void setCustomCredentials(String certificate, String privateKey) {
    _customCertificate = certificate;
    _customPrivateKey = privateKey;
    _savePreferences();
    notifyListeners();
  }

  bool get hasCustomCredentials =>
      _customCertificate != null && _customPrivateKey != null;

  void setKeystoreConfig({
    required String keyAlias,
    required String certificateChainPem,
  }) {
    _keystoreKeyAlias = keyAlias;
    _keystoreCertificateChain = certificateChainPem;
    _savePreferences();
    notifyListeners();
  }

  void setHardwareConfig({
    required String keyAlias,
    required String certificateChainPem,
    bool requireBiometric = false,
  }) {
    _hardwareKeyAlias = keyAlias;
    _hardwareCertificateChain = certificateChainPem;
    _requireBiometric = requireBiometric;
    _savePreferences();
    notifyListeners();
  }

  void setRemoteConfig({
    required String url,
    String? bearerToken,
  }) {
    _remoteUrl = url;
    _bearerToken = bearerToken;
    _savePreferences();
    notifyListeners();
  }

  void clearRemoteConfig() {
    _remoteUrl = null;
    _bearerToken = null;
    _savePreferences();
    notifyListeners();
  }

  /// Check if the current signing mode is ready to sign
  bool get isConfigured {
    switch (_signingMode) {
      case SigningMode.defaultCerts:
        return true; // Always ready
      case SigningMode.customPem:
        return hasCustomCredentials;
      case SigningMode.callback:
        return true; // Uses default certs for demo
      case SigningMode.keystore:
        return hasKeystoreConfig;
      case SigningMode.hardware:
        return hasHardwareConfig;
      case SigningMode.remote:
        return hasRemoteConfig;
    }
  }

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

  /// Check if hardware signing is available on this device
  Future<bool> isHardwareSigningAvailable() async {
    if (_hardwareAvailable != null) {
      return _hardwareAvailable!;
    }
    try {
      _hardwareAvailable = await _c2pa.isHardwareSigningAvailable();
      return _hardwareAvailable!;
    } catch (e) {
      debugPrint('Failed to check hardware signing availability: $e');
      _hardwareAvailable = false;
      return false;
    }
  }

  /// Create a hardware-backed key
  Future<bool> createHardwareKey(String keyAlias) async {
    try {
      await _c2pa.createKey(
        keyAlias: keyAlias,
        useHardware: true,
      );
      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  /// Create a software keystore key
  Future<bool> createKeystoreKey(String keyAlias) async {
    try {
      await _c2pa.createKey(
        keyAlias: keyAlias,
        useHardware: false,
      );
      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  /// Check if a key exists
  Future<bool> keyExists(String keyAlias) async {
    try {
      return await _c2pa.keyExists(keyAlias);
    } catch (e) {
      debugPrint('Failed to check key existence: $e');
      return false;
    }
  }

  /// Export public key for a given alias
  Future<String?> exportPublicKey(String keyAlias) async {
    try {
      return await _c2pa.exportPublicKey(keyAlias);
    } catch (e) {
      _lastError = e.toString();
      return null;
    }
  }

  /// Delete a key
  Future<bool> deleteKey(String keyAlias) async {
    try {
      await _c2pa.deleteKey(keyAlias);
      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
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
      final signer = await _getSigner();
      if (signer == null) {
        _lastError = 'No signing credentials available. Please configure in Settings.';
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
        signer: signer,
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

  Future<C2paSigner?> _getSigner() async {
    switch (_signingMode) {
      case SigningMode.defaultCerts:
        await _loadDefaultCredentials();
        if (_defaultCertificate == null || _defaultPrivateKey == null) {
          return null;
        }
        return PemSigner(
          algorithm: SigningAlgorithm.es256,
          certificatePem: _defaultCertificate!,
          privateKeyPem: _defaultPrivateKey!,
        );

      case SigningMode.customPem:
        if (_customCertificate == null || _customPrivateKey == null) {
          return null;
        }
        return PemSigner(
          algorithm: SigningAlgorithm.es256,
          certificatePem: _customCertificate!,
          privateKeyPem: _customPrivateKey!,
        );

      case SigningMode.callback:
        // Demo callback signer using default credentials
        await _loadDefaultCredentials();
        if (_defaultCertificate == null || _defaultPrivateKey == null) {
          return null;
        }
        // For demo purposes, we create a CallbackSigner that uses the default
        // certificate chain but performs signing via a callback.
        // In a real app, this would be used for custom HSM integration, etc.
        return CallbackSigner(
          algorithm: SigningAlgorithm.es256,
          certificateChainPem: _defaultCertificate!,
          signCallback: _demoSignCallback,
        );

      case SigningMode.keystore:
        if (_keystoreCertificateChain == null) {
          return null;
        }
        return KeystoreSigner(
          algorithm: SigningAlgorithm.es256,
          keyAlias: _keystoreKeyAlias,
          certificateChainPem: _keystoreCertificateChain!,
        );

      case SigningMode.hardware:
        if (_hardwareCertificateChain == null) {
          return null;
        }
        return HardwareSigner(
          keyAlias: _hardwareKeyAlias,
          certificateChainPem: _hardwareCertificateChain!,
          requireUserAuthentication: _requireBiometric,
        );

      case SigningMode.remote:
        if (_remoteUrl == null || _remoteUrl!.isEmpty) {
          return null;
        }
        return RemoteSigner(
          configurationUrl: _remoteUrl!,
          bearerToken: _bearerToken,
        );
    }
  }

  /// Demo sign callback - in a real app this would integrate with HSM or other
  /// custom signing infrastructure
  Future<Uint8List> _demoSignCallback(Uint8List data) async {
    // This is a placeholder - in a real implementation, you would:
    // 1. Send the data hash to your HSM/signing service
    // 2. Receive the signature back
    // 3. Return the signature bytes
    //
    // For demo purposes, we just return empty bytes which will cause
    // the signing to fail (demonstrating the callback mechanism)
    debugPrint('CallbackSigner: Received ${data.length} bytes to sign');

    // In a real app, you would implement actual signing here.
    // This demo will fail since we're not providing a valid signature.
    throw UnimplementedError(
      'Callback signing is a demo feature. '
      'In production, implement actual HSM/custom signing logic here.'
    );
  }
}
