import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'c2pa.dart';
import 'c2pa_method_channel.dart';

abstract class C2paPlatform extends PlatformInterface {
  C2paPlatform() : super(token: _token);

  static final Object _token = Object();

  static C2paPlatform _instance = MethodChannelC2pa();

  static C2paPlatform get instance => _instance;

  static set instance(C2paPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // ===========================================================================
  // Version and Platform Info
  // ===========================================================================

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  Future<String?> getVersion() {
    throw UnimplementedError('getVersion() has not been implemented.');
  }

  // ===========================================================================
  // Reader API - Basic
  // ===========================================================================

  Future<String?> readFile(String path) {
    throw UnimplementedError('readFile() has not been implemented.');
  }

  Future<String?> readBytes(Uint8List data, String mimeType) {
    throw UnimplementedError('readBytes() has not been implemented.');
  }

  // ===========================================================================
  // Reader API - Enhanced
  // ===========================================================================

  Future<String?> readFileDetailed(
    String path,
    bool detailed,
    String? dataDir,
  ) {
    throw UnimplementedError('readFileDetailed() has not been implemented.');
  }

  Future<String?> readBytesDetailed(
    Uint8List data,
    String mimeType,
    bool detailed,
  ) {
    throw UnimplementedError('readBytesDetailed() has not been implemented.');
  }

  Future<Uint8List?> extractResource(
    Uint8List data,
    String mimeType,
    String uri,
  ) {
    throw UnimplementedError('extractResource() has not been implemented.');
  }

  Future<String?> readIngredientFile(String path, String? dataDir) {
    throw UnimplementedError('readIngredientFile() has not been implemented.');
  }

  Future<List<String>> getSupportedReadMimeTypes() {
    throw UnimplementedError(
      'getSupportedReadMimeTypes() has not been implemented.',
    );
  }

  Future<List<String>> getSupportedSignMimeTypes() {
    throw UnimplementedError(
      'getSupportedSignMimeTypes() has not been implemented.',
    );
  }

  // ===========================================================================
  // Signer API - Basic
  // ===========================================================================

  Future<SignResult> signBytes({
    required Uint8List sourceData,
    required String mimeType,
    required String manifestJson,
    required SignerInfo signerInfo,
  }) {
    throw UnimplementedError('signBytes() has not been implemented.');
  }

  Future<void> signFile({
    required String sourcePath,
    required String destPath,
    required String manifestJson,
    required SignerInfo signerInfo,
  }) {
    throw UnimplementedError('signFile() has not been implemented.');
  }

  // ===========================================================================
  // Builder API
  // ===========================================================================

  Future<ManifestBuilder> createBuilder(String manifestJson) {
    throw UnimplementedError('createBuilder() has not been implemented.');
  }

  Future<ManifestBuilder> createBuilderFromArchive(Uint8List archiveData) {
    throw UnimplementedError(
      'createBuilderFromArchive() has not been implemented.',
    );
  }

  Future<void> builderSetIntent(
    int handle,
    ManifestIntent intent,
    DigitalSourceType? digitalSourceType,
  ) {
    throw UnimplementedError('builderSetIntent() has not been implemented.');
  }

  Future<void> builderSetNoEmbed(int handle) {
    throw UnimplementedError('builderSetNoEmbed() has not been implemented.');
  }

  Future<void> builderSetRemoteUrl(int handle, String url) {
    throw UnimplementedError('builderSetRemoteUrl() has not been implemented.');
  }

  Future<void> builderAddResource(int handle, String uri, Uint8List data) {
    throw UnimplementedError('builderAddResource() has not been implemented.');
  }

  Future<void> builderAddIngredient(
    int handle,
    Uint8List data,
    String mimeType,
    String? ingredientJson,
  ) {
    throw UnimplementedError(
      'builderAddIngredient() has not been implemented.',
    );
  }

  Future<void> builderAddAction(int handle, String actionJson) {
    throw UnimplementedError('builderAddAction() has not been implemented.');
  }

  Future<Uint8List> builderToArchive(int handle) {
    throw UnimplementedError('builderToArchive() has not been implemented.');
  }

  Future<BuilderSignResult> builderSign(
    int handle,
    Uint8List sourceData,
    String mimeType,
    SignerInfo signerInfo,
  ) {
    throw UnimplementedError('builderSign() has not been implemented.');
  }

  Future<void> builderSignFile(
    int handle,
    String sourcePath,
    String destPath,
    SignerInfo signerInfo,
  ) {
    throw UnimplementedError('builderSignFile() has not been implemented.');
  }

  Future<void> builderDispose(int handle) {
    throw UnimplementedError('builderDispose() has not been implemented.');
  }

  // ===========================================================================
  // Advanced Signing API
  // ===========================================================================

  Future<Uint8List> createHashedPlaceholder({
    required int builderHandle,
    required int reservedSize,
    required String mimeType,
  }) {
    throw UnimplementedError(
      'createHashedPlaceholder() has not been implemented.',
    );
  }

  Future<Uint8List> signHashedEmbeddable({
    required int builderHandle,
    required SignerInfo signerInfo,
    required String dataHash,
    required String mimeType,
    Uint8List? assetData,
  }) {
    throw UnimplementedError(
      'signHashedEmbeddable() has not been implemented.',
    );
  }

  Future<Uint8List> formatEmbeddable({
    required String mimeType,
    required Uint8List manifestBytes,
  }) {
    throw UnimplementedError('formatEmbeddable() has not been implemented.');
  }

  Future<int> getSignerReserveSize(SignerInfo signerInfo) {
    throw UnimplementedError(
      'getSignerReserveSize() has not been implemented.',
    );
  }

  // ===========================================================================
  // Settings API
  // ===========================================================================

  Future<void> loadSettings(String settings, String format) {
    throw UnimplementedError('loadSettings() has not been implemented.');
  }
}
