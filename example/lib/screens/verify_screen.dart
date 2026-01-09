import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/c2pa_manager.dart';

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final C2paManager _manager = C2paManager();
  String? _manifestJson;
  bool _isLoading = false;
  String? _error;
  String? _imagePath;

  Future<void> _pickAndVerify() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      setState(() {
        _isLoading = true;
        _error = null;
        _manifestJson = null;
        _imagePath = image.path;
      });

      try {
        final manifest = await _manager.readManifest(image.path);
        setState(() {
          _manifestJson = manifest;
          _isLoading = false;
        });
      } catch (e) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _verifySavedImages() async {
    final directory = await getApplicationDocumentsDirectory();
    final files = directory.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.jpg') || f.path.endsWith('.jpeg'),
    ).toList();

    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No signed images found')),
        );
      }
      return;
    }

    final file = files.last;
    setState(() {
      _isLoading = true;
      _error = null;
      _manifestJson = null;
      _imagePath = file.path;
    });

    try {
      final manifest = await _manager.readManifest(file.path);
      setState(() {
        _manifestJson = manifest;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Image'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickAndVerify,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Pick Image'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _verifySavedImages,
                    icon: const Icon(Icons.history),
                    label: const Text('Last Signed'),
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_manifestJson != null)
            Expanded(
              child: _buildManifestView(),
            )
          else
            const Expanded(
              child: Center(
                child: Text('Select an image to verify its C2PA manifest'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildManifestView() {
    Map<String, dynamic>? manifest;
    try {
      manifest = jsonDecode(_manifestJson!);
    } catch (e) {
      return Center(child: Text('Error parsing manifest: $e'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_imagePath != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(_imagePath!),
              height: 200,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 16),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified, color: Colors.green),
                    const SizedBox(width: 8),
                    const Text(
                      'C2PA Manifest Found',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(),
                _buildInfoRow('Active Manifest', manifest?['active_manifest'] ?? 'N/A'),
                if (manifest?['manifests'] != null)
                  _buildInfoRow(
                    'Manifests Count',
                    (manifest!['manifests'] as Map).length.toString(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('Raw Manifest JSON'),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(manifest),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
