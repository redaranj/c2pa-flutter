import 'package:flutter/material.dart';
import '../services/c2pa_manager.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final C2paManager _manager = C2paManager();
  final _certController = TextEditingController();
  final _keyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _manager.addListener(_onManagerUpdate);
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerUpdate);
    _certController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  void _onManagerUpdate() {
    setState(() {});
  }

  void _saveCustomCredentials() {
    if (_certController.text.isNotEmpty && _keyController.text.isNotEmpty) {
      _manager.setCustomCredentials(_certController.text, _keyController.text);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Custom credentials saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Signing Mode',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildModeCard(
            SigningMode.defaultCerts,
            'Default Certificates',
            'Use included test certificates for development',
            Icons.verified,
          ),
          const SizedBox(height: 8),
          _buildModeCard(
            SigningMode.custom,
            'Custom Certificates',
            'Use your own certificate and private key',
            Icons.key,
          ),
          if (_manager.signingMode == SigningMode.custom) ...[
            const SizedBox(height: 24),
            const Text(
              'Custom Credentials',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _certController,
              decoration: const InputDecoration(
                labelText: 'Certificate (PEM)',
                border: OutlineInputBorder(),
              ),
              maxLines: 5,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _keyController,
              decoration: const InputDecoration(
                labelText: 'Private Key (PEM)',
                border: OutlineInputBorder(),
              ),
              maxLines: 5,
              obscureText: true,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saveCustomCredentials,
              child: const Text('Save Credentials'),
            ),
          ],
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
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

  Widget _buildModeCard(
    SigningMode mode,
    String title,
    String description,
    IconData icon,
  ) {
    final isSelected = _manager.signingMode == mode;
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
        onTap: () {
          _manager.signingMode = mode;
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                size: 40,
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
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
