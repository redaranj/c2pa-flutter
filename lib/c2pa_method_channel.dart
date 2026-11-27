/*
This file is licensed to you under the Apache License, Version 2.0
(http://www.apache.org/licenses/LICENSE-2.0) or the MIT license
(http://opensource.org/licenses/MIT), at your option.

Unless required by applicable law or agreed to in writing, this software is
distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS OF
ANY KIND, either express or implied. See the LICENSE-MIT and LICENSE-APACHE
files for the specific language governing permissions and limitations under
each license.
*/

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'c2pa.dart';
import 'c2pa_platform_interface.dart';

/// Dart-side callbacks attached to one native context.
class _ContextCallbacks {
  final void Function(C2paProgress progress)? onProgress;
  final C2paHttpResolver? httpResolver;
  final List<String> signCallbackIds;

  _ContextCallbacks({
    required this.onProgress,
    required this.httpResolver,
    required this.signCallbackIds,
  });
}

/// A [MethodChannel] that reports every native failure as a
/// [C2paException] instead of a raw [PlatformException].
class C2paMethodChannel extends MethodChannel {
  const C2paMethodChannel(super.name);

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    try {
      return await super.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw C2paException.fromPlatformException(e);
    }
  }
}

/// Method channel implementation of [C2paPlatform]
class MethodChannelC2pa extends C2paPlatform {
  @visibleForTesting
  final MethodChannel methodChannel = const C2paMethodChannel(
    'org.guardianproject.c2pa',
  );

  final Map<String, Future<Uint8List> Function(Uint8List)> _signCallbacks = {};
  final Map<int, _ContextCallbacks> _contextCallbacks = {};
  int _nextCallbackId = 0;
  bool _handlerRegistered = false;

  void _ensureHandlerRegistered() {
    if (_handlerRegistered) return;
    _handlerRegistered = true;
    methodChannel.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    final args = call.arguments as Map<dynamic, dynamic>? ?? const {};
    switch (call.method) {
      case 'signCallback':
        final callbackId = args['callbackId'] as String;
        final callback = _signCallbacks[callbackId];
        if (callback == null) {
          throw PlatformException(
            code: 'CALLBACK_NOT_FOUND',
            message: 'Callback $callbackId not found',
          );
        }
        return callback(args['data'] as Uint8List);
      case 'contextProgress':
        final callbacks = _contextCallbacks[args['contextHandle'] as int?];
        callbacks?.onProgress?.call(C2paProgress.fromMap(args));
        return null;
      case 'httpResolve':
        final resolver =
            _contextCallbacks[args['contextHandle'] as int?]?.httpResolver;
        if (resolver is! CallbackHttpResolver) {
          throw PlatformException(
            code: 'RESOLVER_NOT_FOUND',
            message: 'No HTTP resolver for context ${args['contextHandle']}',
          );
        }
        final response = await resolver.resolve(C2paHttpRequest.fromMap(args));
        return response.toMap();
      default:
        throw MissingPluginException('Method ${call.method} not implemented');
    }
  }

  /// Serializes [signer] for the native side, registering a Dart callback
  /// for every [CallbackSigner] it contains and recording its id in [ids].
  Map<String, dynamic> _serializeSigner(C2paSigner signer, List<String> ids) {
    switch (signer) {
      case CallbackSigner():
        _ensureHandlerRegistered();
        final id = 'callback_${_nextCallbackId++}';
        _signCallbacks[id] = signer.signCallback;
        ids.add(id);
        return {...signer.toMap(), 'callbackId': id};
      case CawgIdentitySigner():
        return {
          ...signer.toMap(),
          'claimSigner': _serializeSigner(signer.claimSigner, ids),
          'identitySigner': _serializeSigner(signer.identitySigner, ids),
        };
      default:
        return signer.toMap();
    }
  }

  /// Runs [body] with [signer] serialized, releasing its callbacks afterwards.
  Future<T> _withSigner<T>(
    C2paSigner? signer,
    Future<T> Function(Map<String, dynamic>? signerMap) body,
  ) async {
    if (signer == null) return body(null);
    final ids = <String>[];
    final signerMap = _serializeSigner(signer, ids);
    try {
      return await body(signerMap);
    } finally {
      ids.forEach(_signCallbacks.remove);
    }
  }

  Future<T> _invoke<T>(String method, [Map<String, dynamic>? arguments]) async {
    final result = await methodChannel.invokeMethod<T>(method, arguments);
    if (result == null) {
      throw C2paPlatformException('ERROR', '$method returned null');
    }
    return result;
  }

  // ===========================================================================
  // Version and Platform Info
  // ===========================================================================

  @override
  Future<String?> getPlatformVersion() =>
      methodChannel.invokeMethod<String>('getPlatformVersion');

  @override
  Future<String?> getVersion() =>
      methodChannel.invokeMethod<String>('getVersion');

  // ===========================================================================
  // Reader
  // ===========================================================================

  @override
  Future<String> readFile(String path) =>
      _invoke<String>('readFile', {'path': path});

  @override
  Future<String> readBytes(Uint8List data, String mimeType) =>
      _invoke<String>('readBytes', {'data': data, 'mimeType': mimeType});

  @override
  Future<String> readFileDetailed(
    String path,
    bool detailed, {
    int? contextHandle,
  }) => _invoke<String>('readFileDetailed', {
    'path': path,
    'detailed': detailed,
    'contextHandle': contextHandle,
  });

  @override
  Future<String> readBytesDetailed(
    Uint8List data,
    String mimeType,
    bool detailed, {
    int? contextHandle,
  }) => _invoke<String>('readBytesDetailed', {
    'data': data,
    'mimeType': mimeType,
    'detailed': detailed,
    'contextHandle': contextHandle,
  });

  @override
  Future<String> readCrJson({
    String? path,
    Uint8List? data,
    String? mimeType,
    int? contextHandle,
  }) {
    if ((path == null) == (data == null)) {
      throw ArgumentError('Provide exactly one of path or data');
    }
    return _invoke<String>('readCrJson', {
      'path': path,
      'data': data,
      'mimeType': mimeType,
      'contextHandle': contextHandle,
    });
  }

  @override
  Future<String> readWithManifest({
    String? path,
    Uint8List? data,
    String? mimeType,
    required Uint8List manifestData,
    bool detailed = false,
    int? contextHandle,
  }) {
    if ((path == null) == (data == null)) {
      throw ArgumentError('Provide exactly one of path or data');
    }
    return _invoke<String>('readWithManifest', {
      'path': path,
      'data': data,
      'mimeType': mimeType,
      'manifestData': manifestData,
      'detailed': detailed,
      'contextHandle': contextHandle,
    });
  }

  @override
  Future<String> readFragment({
    required String initPath,
    required String fragmentPath,
    String? mimeType,
    bool detailed = false,
    int? contextHandle,
  }) => _invoke<String>('readFragment', {
    'initPath': initPath,
    'fragmentPath': fragmentPath,
    'mimeType': mimeType,
    'detailed': detailed,
    'contextHandle': contextHandle,
  });

  @override
  Future<Uint8List> extractResource(
    Uint8List data,
    String mimeType,
    String uri, {
    int? contextHandle,
  }) => _invoke<Uint8List>('extractResource', {
    'data': data,
    'mimeType': mimeType,
    'uri': uri,
    'contextHandle': contextHandle,
  });

  @override
  Future<String?> getRemoteUrl(String path, {String? mimeType}) =>
      methodChannel.invokeMethod<String>('getRemoteUrl', {
        'path': path,
        'mimeType': mimeType,
      });

  @override
  Future<bool> isManifestEmbedded(String path, {String? mimeType}) async {
    final result = await methodChannel.invokeMethod<bool>(
      'isManifestEmbedded',
      {'path': path, 'mimeType': mimeType},
    );
    return result ?? false;
  }

  @override
  Future<List<String>> getSupportedReadMimeTypes() async {
    final result = await methodChannel.invokeMethod<List<dynamic>>(
      'getSupportedReadMimeTypes',
    );
    return result?.cast<String>() ?? [];
  }

  @override
  Future<List<String>> getSupportedSignMimeTypes() async {
    final result = await methodChannel.invokeMethod<List<dynamic>>(
      'getSupportedSignMimeTypes',
    );
    return result?.cast<String>() ?? [];
  }

  // ===========================================================================
  // One-shot signing
  // ===========================================================================

  @override
  Future<SignResult> signBytes({
    required Uint8List sourceData,
    required String mimeType,
    required String manifestJson,
    required C2paSigner signer,
  }) => _withSigner(signer, (signerMap) async {
    final result = await _invoke<Map<dynamic, dynamic>>('signBytes', {
      'sourceData': sourceData,
      'mimeType': mimeType,
      'manifestJson': manifestJson,
      'signer': signerMap,
    });
    return SignResult(
      signedData: result['signedData'] as Uint8List,
      manifestBytes: result['manifestBytes'] as Uint8List?,
    );
  });

  @override
  Future<void> signFile({
    required String sourcePath,
    required String destPath,
    required String manifestJson,
    required C2paSigner signer,
  }) => _withSigner(signer, (signerMap) async {
    await methodChannel.invokeMethod<void>('signFile', {
      'sourcePath': sourcePath,
      'destPath': destPath,
      'manifestJson': manifestJson,
      'signer': signerMap,
    });
  });

  @override
  Future<int> getSignerReserveSize(C2paSigner signer) => _withSigner(
    signer,
    (signerMap) => _invoke<int>('getSignerReserveSize', {'signer': signerMap}),
  );

  @override
  Future<Uint8List> composeManifest({
    required Uint8List manifestBytes,
    required String mimeType,
  }) => _invoke<Uint8List>('composeManifest', {
    'manifestBytes': manifestBytes,
    'mimeType': mimeType,
  });

  // ===========================================================================
  // Builder
  // ===========================================================================

  @override
  Future<ManifestBuilder> createBuilder(
    String manifestJson, {
    int? contextHandle,
  }) async {
    final handle = await _invoke<int>('createBuilder', {
      'manifestJson': manifestJson,
      'contextHandle': contextHandle,
    });
    return MethodChannelManifestBuilder(this, handle);
  }

  @override
  Future<ManifestBuilder> createBuilderFromArchive(
    Uint8List archiveData, {
    int? contextHandle,
  }) async {
    final handle = await _invoke<int>('createBuilderFromArchive', {
      'archiveData': archiveData,
      'contextHandle': contextHandle,
    });
    return MethodChannelManifestBuilder(this, handle);
  }

  @override
  Future<ManifestBuilder> createBuilderWithContext(
    int contextHandle,
    String manifestJson,
  ) async {
    final handle = await _invoke<int>('createBuilderWithContext', {
      'contextHandle': contextHandle,
      'manifestJson': manifestJson,
    });
    return MethodChannelManifestBuilder(this, handle);
  }

  @override
  Future<ManifestBuilder> createBuilderWithSettings(
    String manifestJson,
    int settingsHandle,
  ) async {
    final handle = await _invoke<int>('createBuilderWithSettings', {
      'manifestJson': manifestJson,
      'settingsHandle': settingsHandle,
    });
    return MethodChannelManifestBuilder(this, handle);
  }

  @override
  Future<void> builderSetIntent(
    int handle,
    ManifestIntent intent,
    DigitalSourceType? digitalSourceType,
  ) => methodChannel.invokeMethod<void>('builderSetIntent', {
    'handle': handle,
    'intent': intent.name,
    'digitalSourceType': digitalSourceType?.name,
  });

  @override
  Future<void> builderSetNoEmbed(int handle) =>
      methodChannel.invokeMethod<void>('builderSetNoEmbed', {'handle': handle});

  @override
  Future<void> builderSetRemoteUrl(int handle, String url) =>
      methodChannel.invokeMethod<void>('builderSetRemoteUrl', {
        'handle': handle,
        'url': url,
      });

  @override
  Future<void> builderSetBasePath(int handle, String path) =>
      methodChannel.invokeMethod<void>('builderSetBasePath', {
        'handle': handle,
        'path': path,
      });

  @override
  Future<void> builderAddResource(int handle, String uri, Uint8List data) =>
      methodChannel.invokeMethod<void>('builderAddResource', {
        'handle': handle,
        'uri': uri,
        'data': data,
      });

  @override
  Future<void> builderAddIngredient(
    int handle,
    Uint8List data,
    String mimeType,
    String? ingredientJson,
  ) => methodChannel.invokeMethod<void>('builderAddIngredient', {
    'handle': handle,
    'data': data,
    'mimeType': mimeType,
    'ingredientJson': ingredientJson,
  });

  @override
  Future<void> builderAddIngredientFromFile(
    int handle,
    String path,
    String? mimeType,
    String? ingredientJson,
  ) => methodChannel.invokeMethod<void>('builderAddIngredientFromFile', {
    'handle': handle,
    'path': path,
    'mimeType': mimeType,
    'ingredientJson': ingredientJson,
  });

  @override
  Future<void> builderAddIngredientFromArchive(int handle, Uint8List archive) =>
      methodChannel.invokeMethod<void>('builderAddIngredientFromArchive', {
        'handle': handle,
        'archiveData': archive,
      });

  @override
  Future<Uint8List> builderWriteIngredientArchive(
    int handle,
    String ingredientId,
  ) => _invoke<Uint8List>('builderWriteIngredientArchive', {
    'handle': handle,
    'ingredientId': ingredientId,
  });

  @override
  Future<void> builderAddAction(int handle, String actionJson) =>
      methodChannel.invokeMethod<void>('builderAddAction', {
        'handle': handle,
        'actionJson': actionJson,
      });

  @override
  Future<Uint8List> builderToArchive(int handle) =>
      _invoke<Uint8List>('builderToArchive', {'handle': handle});

  @override
  Future<BuilderSignResult> builderSign(
    int handle,
    Uint8List sourceData,
    String mimeType,
    C2paSigner? signer,
  ) => _withSigner(signer, (signerMap) async {
    final result = await _invoke<Map<dynamic, dynamic>>('builderSign', {
      'handle': handle,
      'sourceData': sourceData,
      'mimeType': mimeType,
      'signer': signerMap,
    });
    return BuilderSignResult(
      signedData: result['signedData'] as Uint8List,
      manifestBytes: result['manifestBytes'] as Uint8List?,
      manifestSize: (result['manifestSize'] as num?)?.toInt() ?? 0,
    );
  });

  @override
  Future<BuilderFileSignResult> builderSignFile(
    int handle,
    String sourcePath,
    String destPath,
    C2paSigner? signer, {
    String? mimeType,
  }) => _withSigner(signer, (signerMap) async {
    final result = await _invoke<Map<dynamic, dynamic>>('builderSignFile', {
      'handle': handle,
      'sourcePath': sourcePath,
      'destPath': destPath,
      'mimeType': mimeType,
      'signer': signerMap,
    });
    return BuilderFileSignResult(
      manifestBytes: result['manifestBytes'] as Uint8List?,
      manifestSize: (result['manifestSize'] as num?)?.toInt() ?? 0,
    );
  });

  @override
  Future<bool> builderNeedsPlaceholder(int handle, String mimeType) =>
      _invoke<bool>('builderNeedsPlaceholder', {
        'handle': handle,
        'mimeType': mimeType,
      });

  @override
  Future<Uint8List> builderPlaceholder(int handle, String mimeType) =>
      _invoke<Uint8List>('builderPlaceholder', {
        'handle': handle,
        'mimeType': mimeType,
      });

  @override
  Future<void> builderSetDataHashExclusions(
    int handle,
    List<DataHashExclusion> exclusions,
  ) => methodChannel.invokeMethod<void>('builderSetDataHashExclusions', {
    'handle': handle,
    'exclusions': exclusions.map((e) => e.toList()).toList(),
  });

  @override
  Future<void> builderUpdateHashFromBytes(
    int handle,
    String mimeType,
    Uint8List data,
  ) => methodChannel.invokeMethod<void>('builderUpdateHashFromBytes', {
    'handle': handle,
    'mimeType': mimeType,
    'data': data,
  });

  @override
  Future<void> builderUpdateHashFromFile(
    int handle,
    String path, {
    String? mimeType,
  }) => methodChannel.invokeMethod<void>('builderUpdateHashFromFile', {
    'handle': handle,
    'path': path,
    'mimeType': mimeType,
  });

  @override
  Future<Uint8List> builderSignEmbeddable(int handle, String mimeType) =>
      _invoke<Uint8List>('builderSignEmbeddable', {
        'handle': handle,
        'mimeType': mimeType,
      });

  @override
  Future<C2paHashType> builderHashType(int handle, String mimeType) async {
    final name = await _invoke<String>('builderHashType', {
      'handle': handle,
      'mimeType': mimeType,
    });
    return C2paHashType.fromName(name);
  }

  @override
  Future<void> builderSetFixedSizeMerkle(int handle, int fixedSizeKb) =>
      methodChannel.invokeMethod<void>('builderSetFixedSizeMerkle', {
        'handle': handle,
        'fixedSizeKb': fixedSizeKb,
      });

  @override
  Future<void> builderHashMdatBytes(
    int handle, {
    required int mdatId,
    required Uint8List data,
    bool largeSize = false,
  }) => methodChannel.invokeMethod<void>('builderHashMdatBytes', {
    'handle': handle,
    'mdatId': mdatId,
    'data': data,
    'largeSize': largeSize,
  });

  @override
  Future<void> builderDispose(int handle) =>
      methodChannel.invokeMethod<void>('builderDispose', {'handle': handle});

  // ===========================================================================
  // Key Management
  // ===========================================================================

  @override
  Future<bool> isHardwareSigningAvailable() async {
    final result = await methodChannel.invokeMethod<bool>(
      'isHardwareSigningAvailable',
    );
    return result ?? false;
  }

  @override
  Future<void> createKey({
    required String keyAlias,
    required SigningAlgorithm algorithm,
    required bool useHardware,
  }) => methodChannel.invokeMethod<void>('createKey', {
    'keyAlias': keyAlias,
    'algorithm': algorithm.name,
    'useHardware': useHardware,
  });

  @override
  Future<bool> deleteKey(String keyAlias) async {
    final result = await methodChannel.invokeMethod<bool>('deleteKey', {
      'keyAlias': keyAlias,
    });
    return result ?? false;
  }

  @override
  Future<bool> keyExists(String keyAlias) async {
    final result = await methodChannel.invokeMethod<bool>('keyExists', {
      'keyAlias': keyAlias,
    });
    return result ?? false;
  }

  @override
  Future<String> exportPublicKey(String keyAlias) =>
      _invoke<String>('exportPublicKey', {'keyAlias': keyAlias});

  @override
  Future<void> importKey({
    required String keyAlias,
    required String privateKeyPem,
    required String certificateChainPem,
  }) => methodChannel.invokeMethod<void>('importKey', {
    'keyAlias': keyAlias,
    'privateKeyPem': privateKeyPem,
    'certificateChainPem': certificateChainPem,
  });

  @override
  Future<String> createCSR({
    required String keyAlias,
    required String commonName,
    String? organization,
    String? organizationalUnit,
    String? country,
    String? state,
    String? locality,
  }) => _invoke<String>('createCSR', {
    'keyAlias': keyAlias,
    'commonName': commonName,
    'organization': organization,
    'organizationalUnit': organizationalUnit,
    'country': country,
    'state': state,
    'locality': locality,
  });

  @override
  Future<Map<String, dynamic>> enrollHardwareKey({
    required String keyAlias,
    required String signingServerUrl,
    String? bearerToken,
    String? commonName,
    String? organization,
    bool useStrongBox = false,
  }) async {
    final result = await _invoke<Map<dynamic, dynamic>>('enrollHardwareKey', {
      'keyAlias': keyAlias,
      'signingServerUrl': signingServerUrl,
      'bearerToken': bearerToken,
      'commonName': commonName,
      'organization': organization,
      'useStrongBox': useStrongBox,
    });
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<String> createSelfSignedCertificateChain({
    required String keyAlias,
    Map<String, dynamic>? config,
  }) => _invoke<String>('createSelfSignedCertificateChain', {
    'keyAlias': keyAlias,
    'config': config,
  });

  // ===========================================================================
  // Settings
  // ===========================================================================

  @override
  Future<void> loadSettings(String settings, String format) =>
      methodChannel.invokeMethod<void>('loadSettings', {
        'settings': settings,
        'format': format,
      });

  @override
  Future<int> createSettings() => _invoke<int>('createSettings');

  @override
  Future<void> settingsUpdateFromString(
    int handle,
    String settings,
    String format,
  ) => methodChannel.invokeMethod<void>('settingsUpdateFromString', {
    'handle': handle,
    'settings': settings,
    'format': format,
  });

  @override
  Future<void> settingsSetValue(int handle, String path, Object value) =>
      methodChannel.invokeMethod<void>('settingsSetValue', {
        'handle': handle,
        'path': path,
        'value': jsonEncode(value),
      });

  @override
  Future<void> settingsDispose(int handle) =>
      methodChannel.invokeMethod<void>('settingsDispose', {'handle': handle});

  // ===========================================================================
  // Contexts
  // ===========================================================================

  @override
  Future<int> createContext({
    int? settingsHandle,
    C2paSigner? signer,
    void Function(C2paProgress progress)? onProgress,
    C2paHttpResolver? httpResolver,
  }) async {
    final ids = <String>[];
    final signerMap = signer == null ? null : _serializeSigner(signer, ids);
    if (onProgress != null || httpResolver is CallbackHttpResolver) {
      _ensureHandlerRegistered();
    }
    try {
      final handle = await _invoke<int>('createContext', {
        'settingsHandle': settingsHandle,
        'signer': signerMap,
        'progress': onProgress != null,
        'httpResolver': httpResolver?.mode,
      });
      _contextCallbacks[handle] = _ContextCallbacks(
        onProgress: onProgress,
        httpResolver: httpResolver,
        signCallbackIds: ids,
      );
      return handle;
    } catch (_) {
      ids.forEach(_signCallbacks.remove);
      rethrow;
    }
  }

  @override
  Future<void> contextCancel(int handle) =>
      methodChannel.invokeMethod<void>('contextCancel', {'handle': handle});

  @override
  Future<void> contextDispose(int handle) async {
    try {
      await methodChannel.invokeMethod<void>('contextDispose', {
        'handle': handle,
      });
    } finally {
      final callbacks = _contextCallbacks.remove(handle);
      callbacks?.signCallbackIds.forEach(_signCallbacks.remove);
    }
  }
}

/// Releases the native builder of a [MethodChannelManifestBuilder] that was
/// garbage collected without [MethodChannelManifestBuilder.dispose].
final Finalizer<int> _builderFinalizer = Finalizer<int>(
  (handle) => unawaited(
    C2paPlatform.instance.builderDispose(handle).catchError((Object _) {}),
  ),
);

/// Method channel implementation of [ManifestBuilder].
///
/// Calls run one after another in the order they were made, whether or not
/// the caller awaits each one, so a [sign] issued straight after an
/// un-awaited [addIngredient] still sees the ingredient.
class MethodChannelManifestBuilder implements ManifestBuilder {
  final MethodChannelC2pa _platform;
  final int _handle;
  bool _disposed = false;
  Future<void> _tail = Future<void>.value();

  MethodChannelManifestBuilder(this._platform, this._handle) {
    _builderFinalizer.attach(this, _handle, detach: this);
  }

  @override
  int get handle {
    _checkDisposed();
    return _handle;
  }

  void _checkDisposed() {
    if (_disposed) {
      throw StateError('ManifestBuilder has been disposed');
    }
  }

  /// Runs [body] after every earlier call on this builder has finished.
  Future<T> _run<T>(Future<T> Function() body) {
    _checkDisposed();
    final result = _tail.then((_) => body());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<void> setIntent(
    ManifestIntent intent, [
    DigitalSourceType? digitalSourceType,
  ]) => _run(
    () => _platform.builderSetIntent(_handle, intent, digitalSourceType),
  );

  @override
  Future<void> setNoEmbed() => _run(() => _platform.builderSetNoEmbed(_handle));

  @override
  Future<void> setRemoteUrl(String url) =>
      _run(() => _platform.builderSetRemoteUrl(_handle, url));

  @override
  Future<void> addAction(ActionConfig action) {
    final json = action.toJson();
    return _run(() => _platform.builderAddAction(_handle, json));
  }

  @override
  Future<void> setBasePath(String path) =>
      _run(() => _platform.builderSetBasePath(_handle, path));

  @override
  Future<void> addResource(BuilderResource resource) => _run(
    () => _platform.builderAddResource(_handle, resource.uri, resource.data),
  );

  @override
  Future<void> addIngredient({
    required Uint8List data,
    required String mimeType,
    IngredientConfig? config,
  }) => _run(
    () => _platform.builderAddIngredient(
      _handle,
      data,
      mimeType,
      config?.toJson(),
    ),
  );

  @override
  Future<void> addIngredientFromFile({
    required String path,
    String? mimeType,
    IngredientConfig? config,
  }) => _run(
    () => _platform.builderAddIngredientFromFile(
      _handle,
      path,
      mimeType,
      config?.toJson(),
    ),
  );

  @override
  Future<void> addIngredientFromArchive(Uint8List archive) =>
      _run(() => _platform.builderAddIngredientFromArchive(_handle, archive));

  @override
  Future<Uint8List> writeIngredientArchive(String ingredientId) => _run(
    () => _platform.builderWriteIngredientArchive(_handle, ingredientId),
  );

  @override
  Future<BuilderArchive> toArchive() => _run(() async {
    return BuilderArchive(data: await _platform.builderToArchive(_handle));
  });

  @override
  Future<BuilderSignResult> sign({
    required Uint8List sourceData,
    required String mimeType,
    C2paSigner? signer,
  }) =>
      _run(() => _platform.builderSign(_handle, sourceData, mimeType, signer));

  @override
  Future<BuilderFileSignResult> signFile({
    required String sourcePath,
    required String destPath,
    C2paSigner? signer,
    String? mimeType,
  }) => _run(
    () => _platform.builderSignFile(
      _handle,
      sourcePath,
      destPath,
      signer,
      mimeType: mimeType,
    ),
  );

  @override
  Future<bool> needsPlaceholder(String mimeType) =>
      _run(() => _platform.builderNeedsPlaceholder(_handle, mimeType));

  @override
  Future<Uint8List> placeholder(String mimeType) =>
      _run(() => _platform.builderPlaceholder(_handle, mimeType));

  @override
  Future<void> setDataHashExclusions(List<DataHashExclusion> exclusions) =>
      _run(() => _platform.builderSetDataHashExclusions(_handle, exclusions));

  @override
  Future<void> updateHashFromBytes(String mimeType, Uint8List data) =>
      _run(() => _platform.builderUpdateHashFromBytes(_handle, mimeType, data));

  @override
  Future<void> updateHashFromFile(String path, {String? mimeType}) => _run(
    () =>
        _platform.builderUpdateHashFromFile(_handle, path, mimeType: mimeType),
  );

  @override
  Future<Uint8List> signEmbeddable(String mimeType) =>
      _run(() => _platform.builderSignEmbeddable(_handle, mimeType));

  @override
  Future<C2paHashType> hashType(String mimeType) =>
      _run(() => _platform.builderHashType(_handle, mimeType));

  @override
  Future<void> setFixedSizeMerkle(int fixedSizeKb) =>
      _run(() => _platform.builderSetFixedSizeMerkle(_handle, fixedSizeKb));

  @override
  Future<void> hashMdatBytes({
    required int mdatId,
    required Uint8List data,
    bool largeSize = false,
  }) => _run(
    () => _platform.builderHashMdatBytes(
      _handle,
      mdatId: mdatId,
      data: data,
      largeSize: largeSize,
    ),
  );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _builderFinalizer.detach(this);
    await _tail;
    await _platform.builderDispose(_handle);
  }
}
