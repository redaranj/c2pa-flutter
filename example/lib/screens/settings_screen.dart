import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../services/c2pa_manager.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final C2paManager _manager = C2paManager();

  // Custom PEM controllers
  final _certController = TextEditingController();
  final _keyController = TextEditingController();

  // Keystore controllers
  final _keystoreAliasController = TextEditingController();
  final _keystoreCertController = TextEditingController();

  // Hardware controllers
  final _hardwareAliasController = TextEditingController();
  final _hardwareCertController = TextEditingController();

  // Remote controllers
  final _remoteUrlController = TextEditingController();
  final _bearerTokenController = TextEditingController();

  bool _isCheckingHardware = false;
  bool? _hardwareAvailable;

  @override
  void initState() {
    super.initState();
    _manager.addListener(_onManagerUpdate);
    _loadControllerValues();
    _checkHardwareAvailability();
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerUpdate);
    _certController.dispose();
    _keyController.dispose();
    _keystoreAliasController.dispose();
    _keystoreCertController.dispose();
    _hardwareAliasController.dispose();
    _hardwareCertController.dispose();
    _remoteUrlController.dispose();
    _bearerTokenController.dispose();
    super.dispose();
  }

  void _onManagerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  void _loadControllerValues() {
    _keystoreAliasController.text = _manager.keystoreKeyAlias;
    _keystoreCertController.text = _manager.keystoreCertificateChain ?? '';
    _hardwareAliasController.text = _manager.hardwareKeyAlias;
    _hardwareCertController.text = _manager.hardwareCertificateChain ?? '';
    _remoteUrlController.text = _manager.remoteUrl ?? '';
    _bearerTokenController.text = _manager.bearerToken ?? '';
  }

  Future<void> _checkHardwareAvailability() async {
    setState(() => _isCheckingHardware = true);
    try {
      final available = await _manager.isHardwareSigningAvailable();
      if (mounted) {
        setState(() {
          _hardwareAvailable = available;
          _isCheckingHardware = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hardwareAvailable = false;
          _isCheckingHardware = false;
        });
      }
    }
  }

  Future<void> _loadTestCertsForCustomPem() async {
    try {
      final cert = await rootBundle.loadString('assets/test_certs/test_es256_cert.pem');
      final key = await rootBundle.loadString('assets/test_certs/test_es256_key.pem');
      setState(() {
        _certController.text = cert;
        _keyController.text = key;
      });
      _showSnackBar('Test certificates loaded');
    } catch (e) {
      _showSnackBar('Failed to load test certificates: $e');
    }
  }

  void _saveCustomCredentials() {
    if (_certController.text.isNotEmpty && _keyController.text.isNotEmpty) {
      _manager.setCustomCredentials(_certController.text, _keyController.text);
      _showSnackBar('Custom credentials saved');
    } else {
      _showSnackBar('Please provide both certificate and private key');
    }
  }

  void _saveKeystoreConfig() {
    if (_keystoreAliasController.text.isNotEmpty &&
        _keystoreCertController.text.isNotEmpty) {
      _manager.setKeystoreConfig(
        keyAlias: _keystoreAliasController.text,
        certificateChainPem: _keystoreCertController.text,
      );
      _showSnackBar('Keystore configuration saved');
    } else {
      _showSnackBar('Please provide key alias and certificate chain');
    }
  }

  void _saveHardwareConfig() {
    if (_hardwareAliasController.text.isNotEmpty &&
        _hardwareCertController.text.isNotEmpty) {
      _manager.setHardwareConfig(
        keyAlias: _hardwareAliasController.text,
        certificateChainPem: _hardwareCertController.text,
        requireBiometric: _manager.requireBiometric,
      );
      _showSnackBar('Hardware configuration saved');
    } else {
      _showSnackBar('Please provide key alias and certificate chain');
    }
  }

  void _saveRemoteConfig() {
    if (_remoteUrlController.text.isNotEmpty) {
      _manager.setRemoteConfig(
        url: _remoteUrlController.text,
        bearerToken: _bearerTokenController.text.isNotEmpty
            ? _bearerTokenController.text
            : null,
      );
      _showSnackBar('Remote signing configuration saved');
    } else {
      _showSnackBar('Please provide the remote service URL');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  IconData _getIconForMode(SigningMode mode) {
    switch (mode) {
      case SigningMode.defaultCerts:
        return Icons.verified;
      case SigningMode.customPem:
        return Icons.key;
      case SigningMode.callback:
        return Icons.code;
      case SigningMode.keystore:
        return Icons.storage;
      case SigningMode.hardware:
        return Icons.security;
      case SigningMode.remote:
        return Icons.cloud;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signing Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status Card
          _buildStatusCard(),
          const SizedBox(height: 24),

          // Signing Mode Selection
          const Text(
            'Signing Mode',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Select how you want to sign your content',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // Mode Cards
          ...SigningMode.values.map((mode) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildModeCard(mode),
              )),

          const SizedBox(height: 24),

          // Mode-specific configuration
          _buildModeConfiguration(),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),

          // Version info
          FutureBuilder<String?>(
            future: _manager.getVersion(),
            builder: (context, snapshot) {
              return Text(
                'C2PA Library Version: ${snapshot.data ?? "Loading..."}',
                style: TextStyle(color: Colors.grey[600]),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final isConfigured = _manager.isConfigured;
    final mode = _manager.signingMode;

    return Card(
      color: isConfigured
          ? Colors.green.shade50
          : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isConfigured ? Icons.check_circle : Icons.warning,
              color: isConfigured ? Colors.green : Colors.orange,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isConfigured ? 'Ready to Sign' : 'Configuration Required',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isConfigured ? Colors.green.shade800 : Colors.orange.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isConfigured
                        ? 'Using: ${mode.title}'
                        : 'Please configure ${mode.title} settings below',
                    style: TextStyle(
                      color: isConfigured ? Colors.green.shade700 : Colors.orange.shade700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard(SigningMode mode) {
    final isSelected = _manager.signingMode == mode;
    final isHardwareMode = mode == SigningMode.hardware;
    final isHardwareUnavailable = isHardwareMode && _hardwareAvailable == false;

    return Card(
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: isHardwareUnavailable
            ? null
            : () {
                _manager.signingMode = mode;
              },
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: isHardwareUnavailable ? 0.5 : 1.0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  _getIconForMode(mode),
                  size: 32,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mode.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isHardwareUnavailable
                            ? 'Not available on this device'
                            : mode.description,
                        style: TextStyle(
                          color: isHardwareUnavailable
                              ? Colors.red.shade400
                              : Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                if (isHardwareMode && _isCheckingHardware)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeConfiguration() {
    switch (_manager.signingMode) {
      case SigningMode.defaultCerts:
        return _buildDefaultCertsConfig();
      case SigningMode.customPem:
        return _buildCustomPemConfig();
      case SigningMode.callback:
        return _buildCallbackConfig();
      case SigningMode.keystore:
        return _buildKeystoreConfig();
      case SigningMode.hardware:
        return _buildHardwareConfig();
      case SigningMode.remote:
        return _buildRemoteConfig();
    }
  }

  Widget _buildDefaultCertsConfig() {
    return _buildConfigSection(
      title: 'Default Certificates',
      icon: Icons.info_outline,
      children: [
        const Text(
          'Using bundled test certificates for development purposes. '
          'These certificates are self-signed and should only be used for testing.',
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.amber.shade700),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'For production use, switch to a trusted certificate provider.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCustomPemConfig() {
    return _buildConfigSection(
      title: 'Custom PEM Configuration',
      icon: Icons.key,
      children: [
        TextField(
          controller: _certController,
          decoration: const InputDecoration(
            labelText: 'Certificate (PEM)',
            hintText: '-----BEGIN CERTIFICATE-----',
            border: OutlineInputBorder(),
          ),
          maxLines: 5,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _keyController,
          decoration: const InputDecoration(
            labelText: 'Private Key (PEM)',
            hintText: '-----BEGIN PRIVATE KEY-----',
            border: OutlineInputBorder(),
          ),
          maxLines: 5,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _loadTestCertsForCustomPem,
                icon: const Icon(Icons.download),
                label: const Text('Load Test Certs'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveCustomCredentials,
                icon: const Icon(Icons.save),
                label: const Text('Save'),
              ),
            ),
          ],
        ),
        if (_manager.hasCustomCredentials) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade600, size: 16),
              const SizedBox(width: 8),
              Text(
                'Credentials configured',
                style: TextStyle(color: Colors.green.shade600, fontSize: 12),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildCallbackConfig() {
    return _buildConfigSection(
      title: 'Callback Signer',
      icon: Icons.code,
      children: [
        const Text(
          'The callback signer demonstrates custom signing logic using a Dart callback. '
          'This example uses pointycastle to perform ECDSA signing with the test certificates.',
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade700),
                  const SizedBox(width: 12),
                  const Text(
                    'Ready to Sign',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Uses bundled test certificates with custom Dart-based ECDSA signing. '
                'In production, replace the callback with your HSM or signing service integration.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeystoreConfig() {
    return _buildConfigSection(
      title: 'Keystore Configuration',
      icon: Icons.storage,
      children: [
        const Text(
          'Use a key stored in the platform keystore (Android Keystore / iOS Keychain). '
          'The key must already exist and you must provide the certificate chain.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _keystoreAliasController,
          decoration: const InputDecoration(
            labelText: 'Key Alias',
            hintText: 'e.g., c2pa_signing_key',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _keystoreCertController,
          decoration: const InputDecoration(
            labelText: 'Certificate Chain (PEM)',
            hintText: '-----BEGIN CERTIFICATE-----',
            border: OutlineInputBorder(),
          ),
          maxLines: 5,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveKeystoreConfig,
                icon: const Icon(Icons.save),
                label: const Text('Save Configuration'),
              ),
            ),
          ],
        ),
        if (_manager.hasKeystoreConfig) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade600, size: 16),
              const SizedBox(width: 8),
              Text(
                'Keystore configured: ${_manager.keystoreKeyAlias}',
                style: TextStyle(color: Colors.green.shade600, fontSize: 12),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildHardwareConfig() {
    return _buildConfigSection(
      title: 'Hardware Security Configuration',
      icon: Icons.security,
      children: [
        if (_hardwareAvailable == false) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Hardware security (StrongBox / Secure Enclave) is not available on this device.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          const Text(
            'Use hardware-backed signing with StrongBox (Android) or Secure Enclave (iOS). '
            'Only ES256 algorithm is supported.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _hardwareAliasController,
            decoration: const InputDecoration(
              labelText: 'Key Alias',
              hintText: 'e.g., c2pa_hardware_key',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _hardwareCertController,
            decoration: const InputDecoration(
              labelText: 'Certificate Chain (PEM)',
              hintText: '-----BEGIN CERTIFICATE-----',
              border: OutlineInputBorder(),
            ),
            maxLines: 5,
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Require Biometric Authentication'),
            subtitle: const Text('Prompt for Face ID / fingerprint before signing'),
            value: _manager.requireBiometric,
            onChanged: (value) {
              _manager.setHardwareConfig(
                keyAlias: _hardwareAliasController.text.isNotEmpty
                    ? _hardwareAliasController.text
                    : _manager.hardwareKeyAlias,
                certificateChainPem: _hardwareCertController.text.isNotEmpty
                    ? _hardwareCertController.text
                    : _manager.hardwareCertificateChain ?? '',
                requireBiometric: value,
              );
            },
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saveHardwareConfig,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Configuration'),
                ),
              ),
            ],
          ),
          if (_manager.hasHardwareConfig) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade600, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Hardware configured: ${_manager.hardwareKeyAlias}',
                  style: TextStyle(color: Colors.green.shade600, fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildRemoteConfig() {
    return _buildConfigSection(
      title: 'Remote Signing Configuration',
      icon: Icons.cloud,
      children: [
        const Text(
          'Connect to a remote signing service that implements the C2PA Web Service Signer protocol.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _remoteUrlController,
          decoration: const InputDecoration(
            labelText: 'Configuration URL',
            hintText: 'https://signing-service.example.com/config',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.link),
          ),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _bearerTokenController,
          decoration: const InputDecoration(
            labelText: 'Bearer Token (Optional)',
            hintText: 'Enter authentication token',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.vpn_key),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveRemoteConfig,
                icon: const Icon(Icons.save),
                label: const Text('Save Configuration'),
              ),
            ),
            const SizedBox(width: 8),
            if (_manager.hasRemoteConfig)
              IconButton(
                onPressed: () {
                  _manager.clearRemoteConfig();
                  _remoteUrlController.clear();
                  _bearerTokenController.clear();
                  _showSnackBar('Remote configuration cleared');
                },
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Clear configuration',
              ),
          ],
        ),
        if (_manager.hasRemoteConfig) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade600, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Remote service: ${_manager.remoteUrl}',
                  style: TextStyle(color: Colors.green.shade600, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Remote Signing Protocol',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 8),
              const Text(
                'The signing service should implement:\n'
                '  - GET /config - Returns signer configuration\n'
                '  - POST /sign - Signs the provided data\n'
                '  - GET /certificate - Returns certificate chain',
                style: TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConfigSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}
