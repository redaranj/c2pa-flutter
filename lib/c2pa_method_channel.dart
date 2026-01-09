import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'c2pa.dart';
import 'c2pa_platform_interface.dart';

/// Method channel implementation of [C2paPlatform]
class MethodChannelC2pa extends C2paPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('org.guardianproject.c2pa');

  // ===========================================================================
  // Version and Platform Info
  // ===========================================================================

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<String?> getVersion() async {
    final version = await methodChannel.invokeMethod<String>('getVersion');
    return version;
  }

  // ===========================================================================
  // Reader API - Basic
  // ===========================================================================

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

  // ===========================================================================
  // Reader API - Enhanced
  // ===========================================================================

  @override
  Future<String?> readFileDetailed(
    String path,
    bool detailed,
    String? dataDir,
  ) async {
    final result = await methodChannel.invokeMethod<String>(
      'readFileDetailed',
      {'path': path, 'detailed': detailed, 'dataDir': dataDir},
    );
    return result;
  }

  @override
  Future<String?> readBytesDetailed(
    Uint8List data,
    String mimeType,
    bool detailed,
  ) async {
    final result = await methodChannel.invokeMethod<String>(
      'readBytesDetailed',
      {'data': data, 'mimeType': mimeType, 'detailed': detailed},
    );
    return result;
  }

  @override
  Future<Uint8List?> extractResource(
    Uint8List data,
    String mimeType,
    String uri,
  ) async {
    final result = await methodChannel.invokeMethod<Uint8List>(
      'extractResource',
      {'data': data, 'mimeType': mimeType, 'uri': uri},
    );
    return result;
  }

  @override
  Future<String?> readIngredientFile(String path, String? dataDir) async {
    final result = await methodChannel.invokeMethod<String>(
      'readIngredientFile',
      {'path': path, 'dataDir': dataDir},
    );
    return result;
  }

  @override
  Future<List<String>> getSupportedReadMimeTypes() async {
    final result = await methodChannel.invokeMethod<List>(
      'getSupportedReadMimeTypes',
    );
    return result?.cast<String>() ?? [];
  }

  @override
  Future<List<String>> getSupportedSignMimeTypes() async {
    final result = await methodChannel.invokeMethod<List>(
      'getSupportedSignMimeTypes',
    );
    return result?.cast<String>() ?? [];
  }

  // ===========================================================================
  // Signer API - Basic
  // ===========================================================================

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
      throw PlatformException(
        code: 'ERROR',
        message: 'Sign operation returned null',
      );
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

  // ===========================================================================
  // Builder API
  // ===========================================================================

  @override
  Future<ManifestBuilder> createBuilder(String manifestJson) async {
    final handle = await methodChannel.invokeMethod<int>('createBuilder', {
      'manifestJson': manifestJson,
    });

    if (handle == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to create builder',
      );
    }

    return MethodChannelManifestBuilder(this, handle);
  }

  @override
  Future<ManifestBuilder> createBuilderFromArchive(
    Uint8List archiveData,
  ) async {
    final handle = await methodChannel.invokeMethod<int>(
      'createBuilderFromArchive',
      {'archiveData': archiveData},
    );

    if (handle == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to create builder from archive',
      );
    }

    return MethodChannelManifestBuilder(this, handle);
  }

  @override
  Future<void> builderSetIntent(
    int handle,
    ManifestIntent intent,
    DigitalSourceType? digitalSourceType,
  ) async {
    await methodChannel.invokeMethod<void>('builderSetIntent', {
      'handle': handle,
      'intent': intent.name,
      'digitalSourceType': digitalSourceType?.name,
    });
  }

  @override
  Future<void> builderSetNoEmbed(int handle) async {
    await methodChannel.invokeMethod<void>('builderSetNoEmbed', {
      'handle': handle,
    });
  }

  @override
  Future<void> builderSetRemoteUrl(int handle, String url) async {
    await methodChannel.invokeMethod<void>('builderSetRemoteUrl', {
      'handle': handle,
      'url': url,
    });
  }

  @override
  Future<void> builderAddResource(
    int handle,
    String uri,
    Uint8List data,
  ) async {
    await methodChannel.invokeMethod<void>('builderAddResource', {
      'handle': handle,
      'uri': uri,
      'data': data,
    });
  }

  @override
  Future<void> builderAddIngredient(
    int handle,
    Uint8List data,
    String mimeType,
    String? ingredientJson,
  ) async {
    await methodChannel.invokeMethod<void>('builderAddIngredient', {
      'handle': handle,
      'data': data,
      'mimeType': mimeType,
      'ingredientJson': ingredientJson,
    });
  }

  @override
  Future<void> builderAddAction(int handle, String actionJson) async {
    await methodChannel.invokeMethod<void>('builderAddAction', {
      'handle': handle,
      'actionJson': actionJson,
    });
  }

  @override
  Future<Uint8List> builderToArchive(int handle) async {
    final result = await methodChannel.invokeMethod<Uint8List>(
      'builderToArchive',
      {'handle': handle},
    );

    if (result == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to export builder to archive',
      );
    }

    return result;
  }

  @override
  Future<BuilderSignResult> builderSign(
    int handle,
    Uint8List sourceData,
    String mimeType,
    SignerInfo signerInfo,
  ) async {
    final result = await methodChannel.invokeMethod<Map>('builderSign', {
      'handle': handle,
      'sourceData': sourceData,
      'mimeType': mimeType,
      'signerInfo': signerInfo.toMap(),
    });

    if (result == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Builder sign operation returned null',
      );
    }

    return BuilderSignResult(
      signedData: result['signedData'] as Uint8List,
      manifestBytes: result['manifestBytes'] as Uint8List?,
      manifestSize: result['manifestSize'] as int? ?? 0,
    );
  }

  @override
  Future<void> builderSignFile(
    int handle,
    String sourcePath,
    String destPath,
    SignerInfo signerInfo,
  ) async {
    await methodChannel.invokeMethod<void>('builderSignFile', {
      'handle': handle,
      'sourcePath': sourcePath,
      'destPath': destPath,
      'signerInfo': signerInfo.toMap(),
    });
  }

  @override
  Future<void> builderDispose(int handle) async {
    await methodChannel.invokeMethod<void>('builderDispose', {
      'handle': handle,
    });
  }

  // ===========================================================================
  // Advanced Signing API
  // ===========================================================================

  @override
  Future<Uint8List> createHashedPlaceholder({
    required int builderHandle,
    required int reservedSize,
    required String mimeType,
  }) async {
    final result = await methodChannel.invokeMethod<Uint8List>(
      'createHashedPlaceholder',
      {
        'handle': builderHandle,
        'reservedSize': reservedSize,
        'mimeType': mimeType,
      },
    );

    if (result == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to create hashed placeholder',
      );
    }

    return result;
  }

  @override
  Future<Uint8List> signHashedEmbeddable({
    required int builderHandle,
    required SignerInfo signerInfo,
    required String dataHash,
    required String mimeType,
    Uint8List? assetData,
  }) async {
    final result = await methodChannel
        .invokeMethod<Uint8List>('signHashedEmbeddable', {
          'handle': builderHandle,
          'signerInfo': signerInfo.toMap(),
          'dataHash': dataHash,
          'mimeType': mimeType,
          'assetData': assetData,
        });

    if (result == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to sign hashed embeddable',
      );
    }

    return result;
  }

  @override
  Future<Uint8List> formatEmbeddable({
    required String mimeType,
    required Uint8List manifestBytes,
  }) async {
    final result = await methodChannel.invokeMethod<Uint8List>(
      'formatEmbeddable',
      {'mimeType': mimeType, 'manifestBytes': manifestBytes},
    );

    if (result == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to format embeddable',
      );
    }

    return result;
  }

  @override
  Future<int> getSignerReserveSize(SignerInfo signerInfo) async {
    final result = await methodChannel.invokeMethod<int>(
      'getSignerReserveSize',
      {'signerInfo': signerInfo.toMap()},
    );

    if (result == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to get signer reserve size',
      );
    }

    return result;
  }

  // ===========================================================================
  // Settings API
  // ===========================================================================

  @override
  Future<void> loadSettings(String settings, String format) async {
    await methodChannel.invokeMethod<void>('loadSettings', {
      'settings': settings,
      'format': format,
    });
  }
}

/// Method channel implementation of [ManifestBuilder]
class MethodChannelManifestBuilder implements ManifestBuilder {
  final MethodChannelC2pa _platform;
  final int _handle;
  bool _disposed = false;

  // Pending operations that need to be sent to native
  final List<Map<String, dynamic>> _pendingOperations = [];

  MethodChannelManifestBuilder(this._platform, this._handle);

  @override
  int get handle => _handle;

  void _checkDisposed() {
    if (_disposed) {
      throw StateError('ManifestBuilder has been disposed');
    }
  }

  @override
  void setIntent(
    ManifestIntent intent, [
    DigitalSourceType? digitalSourceType,
  ]) {
    _checkDisposed();
    _pendingOperations.add({
      'type': 'setIntent',
      'intent': intent,
      'digitalSourceType': digitalSourceType,
    });
  }

  @override
  void setTitle(String title) {
    _checkDisposed();
    _pendingOperations.add({'type': 'setTitle', 'title': title});
  }

  @override
  void setClaimGenerator(String generator) {
    _checkDisposed();
    _pendingOperations.add({
      'type': 'setClaimGenerator',
      'generator': generator,
    });
  }

  @override
  void setNoEmbed() {
    _checkDisposed();
    _pendingOperations.add({'type': 'setNoEmbed'});
  }

  @override
  void setRemoteUrl(String url) {
    _checkDisposed();
    _pendingOperations.add({'type': 'setRemoteUrl', 'url': url});
  }

  @override
  Future<void> addResource(ResourceRef resource) async {
    _checkDisposed();
    await _platform.builderAddResource(_handle, resource.uri, resource.data);
  }

  @override
  Future<void> addIngredient({
    required Uint8List data,
    required String mimeType,
    IngredientConfig? config,
  }) async {
    _checkDisposed();
    await _platform.builderAddIngredient(
      _handle,
      data,
      mimeType,
      config?.toJson(),
    );
  }

  @override
  Future<void> addIngredientFromFile({
    required String path,
    IngredientConfig? config,
  }) async {
    _checkDisposed();
    await _platform.methodChannel.invokeMethod<void>(
      'builderAddIngredientFromFile',
      {'handle': _handle, 'path': path, 'ingredientJson': config?.toJson()},
    );
  }

  @override
  void addAction(ActionConfig action) {
    _checkDisposed();
    _pendingOperations.add({
      'type': 'addAction',
      'actionJson': action.toJson(),
    });
  }

  @override
  void addAssertion(String label, Map<String, dynamic> data) {
    _checkDisposed();
    _pendingOperations.add({
      'type': 'addAssertion',
      'label': label,
      'data': jsonEncode(data),
    });
  }

  /// Apply all pending operations before signing
  Future<void> _applyPendingOperations() async {
    for (final op in _pendingOperations) {
      switch (op['type']) {
        case 'setIntent':
          await _platform.builderSetIntent(
            _handle,
            op['intent'] as ManifestIntent,
            op['digitalSourceType'] as DigitalSourceType?,
          );
          break;
        case 'setNoEmbed':
          await _platform.builderSetNoEmbed(_handle);
          break;
        case 'setRemoteUrl':
          await _platform.builderSetRemoteUrl(_handle, op['url'] as String);
          break;
        case 'addAction':
          await _platform.builderAddAction(_handle, op['actionJson'] as String);
          break;
        case 'addAssertion':
          // Assertions are added via the manifest JSON definition
          // This would need native support for dynamic assertion addition
          break;
      }
    }
    _pendingOperations.clear();
  }

  @override
  Future<BuilderArchive> toArchive() async {
    _checkDisposed();
    await _applyPendingOperations();
    final data = await _platform.builderToArchive(_handle);
    return BuilderArchive(data: data);
  }

  @override
  Future<BuilderSignResult> sign({
    required Uint8List sourceData,
    required String mimeType,
    required SignerInfo signerInfo,
  }) async {
    _checkDisposed();
    await _applyPendingOperations();
    return _platform.builderSign(_handle, sourceData, mimeType, signerInfo);
  }

  @override
  Future<void> signFile({
    required String sourcePath,
    required String destPath,
    required SignerInfo signerInfo,
  }) async {
    _checkDisposed();
    await _applyPendingOperations();
    await _platform.builderSignFile(_handle, sourcePath, destPath, signerInfo);
  }

  @override
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      _platform.builderDispose(_handle);
    }
  }
}
