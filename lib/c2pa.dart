/// C2PA Flutter Plugin - Content Authenticity for Mobile Apps
///
/// This library provides a Flutter interface to the C2PA (Coalition for Content
/// Provenance and Authenticity) specification, enabling mobile applications to
/// read, create, and verify content credentials embedded in digital media.
///
/// ## Overview
///
/// C2PA is an open technical standard that enables content creators and publishers
/// to embed provenance information directly into media files. This helps establish
/// the origin and history of digital content.
///
/// ## Getting Started
///
/// Create an instance of [C2pa] to access all functionality:
///
/// ```dart
/// final c2pa = C2pa();
///
/// // Check library version
/// final version = await c2pa.getVersion();
/// print('C2PA version: $version');
/// ```
///
/// ## Reading Manifests
///
/// Read C2PA manifests from files or byte data:
///
/// ```dart
/// // Read from file
/// final json = await c2pa.readFile('/path/to/image.jpg');
///
/// // Read with parsed data
/// final manifest = await c2pa.readManifestFromFile('/path/to/image.jpg');
/// if (manifest != null) {
///   print('Active manifest: ${manifest.activeManifest}');
///   print('Validation: ${manifest.validationStatus}');
/// }
/// ```
///
/// ## Signing Content
///
/// Sign content with C2PA manifests using the Builder API:
///
/// ```dart
/// // Create a builder
/// final builder = await c2pa.createBuilder('{"title": "My Photo"}');
///
/// // Configure the manifest
/// builder.setIntent(ManifestIntent.create, DigitalSourceType.digitalCapture);
///
/// // Sign the content
/// final result = await builder.sign(
///   sourceData: imageBytes,
///   mimeType: 'image/jpeg',
///   signerInfo: SignerInfo(
///     algorithm: SigningAlgorithm.es256,
///     certificatePem: certificatePem,
///     privateKeyPem: privateKeyPem,
///   ),
/// );
///
/// // Use result.signedData
/// builder.dispose();
/// ```
///
/// ## Key Classes
///
/// - [C2pa] - Main entry point for all C2PA operations
/// - [ManifestBuilder] - Builder pattern for creating manifests
/// - [ManifestStoreInfo] - Parsed manifest data with validation info
/// - [SignerInfo] - Configuration for signing operations
/// - [SigningAlgorithm] - Supported cryptographic algorithms
///
/// ## See Also
///
/// - [C2PA Specification](https://c2pa.org/specifications/)
/// - [Content Authenticity Initiative](https://contentauthenticity.org/)
library;

import 'dart:convert';
import 'dart:typed_data';

import 'c2pa_platform_interface.dart';

// =============================================================================
// Enums
// =============================================================================

/// Signing algorithms supported by C2PA
enum SigningAlgorithm { es256, es384, es512, ps256, ps384, ps512, ed25519 }

/// Builder intent - specifies what kind of manifest to create
enum ManifestIntent {
  /// New digital creation with specified digital source type.
  /// The Manifest must not have a parent ingredient.
  /// A `c2pa.created` action will be added if not provided.
  create,

  /// Edit of a pre-existing parent asset.
  /// The Manifest must have a parent ingredient.
  /// A parent ingredient will be generated from the source stream if not otherwise provided.
  /// A `c2pa.opened` action will be tied to the parent ingredient.
  edit,

  /// Restricted version of Edit for non-editorial changes.
  /// There must be only one ingredient, as a parent.
  /// No changes can be made to the hashed content of the parent.
  update,
}

/// Digital source types as defined by C2PA/IPTC
enum DigitalSourceType {
  empty,
  trainedAlgorithmicData,
  digitalCapture,
  computationalCapture,
  negativeFilm,
  positiveFilm,
  print,
  humanEdits,
  compositeWithTrainedAlgorithmicMedia,
  algorithmicallyEnhanced,
  digitalCreation,
  dataDrivenMedia,
  trainedAlgorithmicMedia,
  algorithmicMedia,
  screenCapture,
  virtualRecording,
  composite,
  compositeCapture,
  compositeSynthetic,
}

/// Validation status for manifest verification
enum ValidationStatus { valid, invalid, unknown }

/// Relationship type for ingredients
enum IngredientRelationship { parentOf, componentOf }

// =============================================================================
// Core Data Classes
// =============================================================================

/// Configuration for signing operations.
///
/// Provides the cryptographic credentials needed to sign C2PA manifests.
///
/// ## Example
///
/// ```dart
/// final signerInfo = SignerInfo(
///   algorithm: SigningAlgorithm.es256,
///   certificatePem: await File('cert.pem').readAsString(),
///   privateKeyPem: await File('key.pem').readAsString(),
///   tsaUrl: 'http://timestamp.digicert.com', // Optional
/// );
/// ```
///
/// ## Supported Algorithms
///
/// - ECDSA: [SigningAlgorithm.es256], [SigningAlgorithm.es384], [SigningAlgorithm.es512]
/// - RSA-PSS: [SigningAlgorithm.ps256], [SigningAlgorithm.ps384], [SigningAlgorithm.ps512]
/// - EdDSA: [SigningAlgorithm.ed25519]
class SignerInfo {
  /// The signing algorithm to use.
  final SigningAlgorithm algorithm;

  /// PEM-encoded X.509 certificate chain.
  final String certificatePem;

  /// PEM-encoded private key (must match the certificate's public key).
  final String privateKeyPem;

  /// Optional RFC 3161 Time Stamp Authority URL for trusted timestamps.
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

  factory SignerInfo.fromMap(Map<String, dynamic> map) {
    return SignerInfo(
      algorithm: SigningAlgorithm.values.firstWhere(
        (e) => e.name == map['algorithm'],
        orElse: () => SigningAlgorithm.es256,
      ),
      certificatePem: map['certificatePem'] as String,
      privateKeyPem: map['privateKeyPem'] as String,
      tsaUrl: map['tsaUrl'] as String?,
    );
  }
}

/// Result of a signing operation
class SignResult {
  final Uint8List signedData;
  final Uint8List? manifestBytes;

  SignResult({required this.signedData, this.manifestBytes});

  /// Size of the signed data in bytes
  int get signedDataSize => signedData.length;

  /// Size of the manifest bytes if available
  int? get manifestSize => manifestBytes?.length;
}

// =============================================================================
// Reader Data Classes
// =============================================================================

/// Options for reading manifests
class ReaderOptions {
  /// Whether to return detailed JSON including validation info
  final bool detailed;

  /// Directory to write resources (thumbnails, etc.)
  final String? dataDir;

  const ReaderOptions({this.detailed = false, this.dataDir});

  Map<String, dynamic> toMap() {
    return {'detailed': detailed, 'dataDir': dataDir};
  }
}

/// Signature information from a manifest
class SignatureInfo {
  /// The issuer of the certificate
  final String? issuer;

  /// When the manifest was signed
  final DateTime? signedAt;

  /// When the certificate expires
  final DateTime? expiresAt;

  /// The signing algorithm used
  final SigningAlgorithm? algorithm;

  /// The certificate serial number
  final String? serialNumber;

  SignatureInfo({
    this.issuer,
    this.signedAt,
    this.expiresAt,
    this.algorithm,
    this.serialNumber,
  });

  factory SignatureInfo.fromMap(Map<String, dynamic> map) {
    return SignatureInfo(
      issuer: map['issuer'] as String?,
      signedAt: map['signed_at'] != null
          ? DateTime.tryParse(map['signed_at'] as String)
          : null,
      expiresAt: map['expires_at'] != null
          ? DateTime.tryParse(map['expires_at'] as String)
          : null,
      algorithm: map['algorithm'] != null
          ? SigningAlgorithm.values.firstWhere(
              (e) =>
                  e.name.toLowerCase() ==
                  (map['algorithm'] as String).toLowerCase(),
              orElse: () => SigningAlgorithm.es256,
            )
          : null,
      serialNumber: map['serial_number'] as String?,
    );
  }
}

/// Validation error from manifest verification
class ValidationError {
  /// Error code
  final String code;

  /// Human-readable error message
  final String message;

  /// The manifest label this error relates to (if applicable)
  final String? manifestLabel;

  ValidationError({
    required this.code,
    required this.message,
    this.manifestLabel,
  });

  factory ValidationError.fromMap(Map<String, dynamic> map) {
    return ValidationError(
      code: map['code'] as String? ?? 'unknown',
      message: map['message'] as String? ?? 'Unknown error',
      manifestLabel: map['manifest_label'] as String?,
    );
  }

  @override
  String toString() => 'ValidationError($code: $message)';
}

/// Information about an assertion in a manifest
class AssertionInfo {
  /// The assertion label (e.g., "c2pa.actions")
  final String label;

  /// The assertion data
  final Map<String, dynamic> data;

  /// Instance identifier if present
  final int? instance;

  AssertionInfo({required this.label, required this.data, this.instance});

  factory AssertionInfo.fromMap(Map<String, dynamic> map) {
    return AssertionInfo(
      label: map['label'] as String? ?? '',
      data: map['data'] as Map<String, dynamic>? ?? {},
      instance: map['instance'] as int?,
    );
  }
}

/// Information about an ingredient in a manifest
class IngredientInfo {
  /// Title of the ingredient
  final String? title;

  /// Format/MIME type
  final String? format;

  /// Instance ID
  final String? instanceId;

  /// Document ID
  final String? documentId;

  /// Relationship to parent manifest
  final IngredientRelationship relationship;

  /// Thumbnail URI if present
  final String? thumbnailUri;

  /// The ingredient's manifest if present
  final ManifestInfo? manifest;

  /// Validation status of the ingredient
  final ValidationStatus validationStatus;

  IngredientInfo({
    this.title,
    this.format,
    this.instanceId,
    this.documentId,
    required this.relationship,
    this.thumbnailUri,
    this.manifest,
    this.validationStatus = ValidationStatus.unknown,
  });

  factory IngredientInfo.fromMap(Map<String, dynamic> map) {
    final relationshipStr = map['relationship'] as String?;
    IngredientRelationship relationship;
    if (relationshipStr == 'parentOf') {
      relationship = IngredientRelationship.parentOf;
    } else {
      relationship = IngredientRelationship.componentOf;
    }

    return IngredientInfo(
      title: map['title'] as String?,
      format: map['format'] as String?,
      instanceId: map['instance_id'] as String?,
      documentId: map['document_id'] as String?,
      relationship: relationship,
      thumbnailUri: map['thumbnail']?['identifier'] as String?,
      manifest: map['manifest'] != null
          ? ManifestInfo.fromMap(map['manifest'] as Map<String, dynamic>)
          : null,
      validationStatus: _parseValidationStatus(map['validation_status']),
    );
  }

  static ValidationStatus _parseValidationStatus(dynamic status) {
    if (status == null) return ValidationStatus.unknown;
    if (status is String) {
      switch (status.toLowerCase()) {
        case 'valid':
          return ValidationStatus.valid;
        case 'invalid':
          return ValidationStatus.invalid;
        default:
          return ValidationStatus.unknown;
      }
    }
    return ValidationStatus.unknown;
  }
}

/// Information about a single manifest
class ManifestInfo {
  /// The manifest label (unique identifier)
  final String label;

  /// Title of the asset
  final String? title;

  /// Format/MIME type
  final String? format;

  /// Claim generator string
  final String? claimGenerator;

  /// Instance ID
  final String? instanceId;

  /// Signature information
  final SignatureInfo? signature;

  /// List of assertions
  final List<AssertionInfo> assertions;

  /// List of ingredients
  final List<IngredientInfo> ingredients;

  /// Thumbnail URI if present
  final String? thumbnailUri;

  ManifestInfo({
    required this.label,
    this.title,
    this.format,
    this.claimGenerator,
    this.instanceId,
    this.signature,
    this.assertions = const [],
    this.ingredients = const [],
    this.thumbnailUri,
  });

  factory ManifestInfo.fromMap(Map<String, dynamic> map) {
    return ManifestInfo(
      label: map['label'] as String? ?? '',
      title: map['title'] as String?,
      format: map['format'] as String?,
      claimGenerator: map['claim_generator'] as String?,
      instanceId: map['instance_id'] as String?,
      signature: map['signature_info'] != null
          ? SignatureInfo.fromMap(map['signature_info'] as Map<String, dynamic>)
          : null,
      assertions:
          (map['assertions'] as List<dynamic>?)
              ?.map((a) => AssertionInfo.fromMap(a as Map<String, dynamic>))
              .toList() ??
          [],
      ingredients:
          (map['ingredients'] as List<dynamic>?)
              ?.map((i) => IngredientInfo.fromMap(i as Map<String, dynamic>))
              .toList() ??
          [],
      thumbnailUri: map['thumbnail']?['identifier'] as String?,
    );
  }
}

/// Complete manifest store with all manifests and validation info
class ManifestStoreInfo {
  /// The active manifest label
  final String? activeManifest;

  /// Map of manifest labels to manifest info
  final Map<String, ManifestInfo> manifests;

  /// List of validation errors
  final List<ValidationError> validationErrors;

  /// Overall validation status
  final ValidationStatus validationStatus;

  ManifestStoreInfo({
    this.activeManifest,
    this.manifests = const {},
    this.validationErrors = const [],
    this.validationStatus = ValidationStatus.unknown,
  });

  /// Get the active manifest if present
  ManifestInfo? get active =>
      activeManifest != null ? manifests[activeManifest] : null;

  factory ManifestStoreInfo.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return ManifestStoreInfo.fromMap(map);
  }

  factory ManifestStoreInfo.fromMap(Map<String, dynamic> map) {
    final manifestsMap = <String, ManifestInfo>{};
    final manifestsData = map['manifests'] as Map<String, dynamic>?;
    if (manifestsData != null) {
      for (final entry in manifestsData.entries) {
        manifestsMap[entry.key] = ManifestInfo.fromMap(
          entry.value as Map<String, dynamic>,
        );
      }
    }

    return ManifestStoreInfo(
      activeManifest: map['active_manifest'] as String?,
      manifests: manifestsMap,
      validationErrors:
          (map['validation_status'] as List<dynamic>?)
              ?.map((e) => ValidationError.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      validationStatus: _determineValidationStatus(map),
    );
  }

  static ValidationStatus _determineValidationStatus(Map<String, dynamic> map) {
    final errors = map['validation_status'] as List<dynamic>?;
    if (errors == null) return ValidationStatus.unknown;
    if (errors.isEmpty) return ValidationStatus.valid;
    return ValidationStatus.invalid;
  }
}

// =============================================================================
// Builder Data Classes
// =============================================================================

/// Reference to a resource (thumbnail, icon, etc.)
class ResourceRef {
  /// URI identifier for the resource
  final String uri;

  /// Resource data
  final Uint8List data;

  /// Optional MIME type
  final String? mimeType;

  ResourceRef({required this.uri, required this.data, this.mimeType});

  Map<String, dynamic> toMap() {
    return {'uri': uri, 'data': data, 'mimeType': mimeType};
  }
}

/// Configuration for adding an ingredient
class IngredientConfig {
  /// Title of the ingredient
  final String? title;

  /// Relationship to the manifest
  final IngredientRelationship relationship;

  /// Optional thumbnail
  final ResourceRef? thumbnail;

  /// Additional JSON data for the ingredient
  final Map<String, dynamic>? additionalData;

  IngredientConfig({
    this.title,
    this.relationship = IngredientRelationship.componentOf,
    this.thumbnail,
    this.additionalData,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'relationship': relationship == IngredientRelationship.parentOf
          ? 'parentOf'
          : 'componentOf',
    };
    if (title != null) map['title'] = title;
    if (additionalData != null) map.addAll(additionalData!);
    return map;
  }

  String toJson() => jsonEncode(toMap());
}

/// Configuration for adding an action
class ActionConfig {
  /// The action identifier (e.g., "c2pa.created", "c2pa.edited")
  final String action;

  /// When the action occurred
  final DateTime? when;

  /// Software agent that performed the action
  final String? softwareAgent;

  /// Digital source type
  final DigitalSourceType? digitalSourceType;

  /// Additional parameters
  final Map<String, dynamic>? parameters;

  ActionConfig({
    required this.action,
    this.when,
    this.softwareAgent,
    this.digitalSourceType,
    this.parameters,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{'action': action};
    if (when != null) map['when'] = when!.toIso8601String();
    if (softwareAgent != null) map['softwareAgent'] = softwareAgent;
    if (digitalSourceType != null) {
      map['digitalSourceType'] = _digitalSourceTypeToUrl(digitalSourceType!);
    }
    if (parameters != null) map['parameters'] = parameters;
    return map;
  }

  String toJson() => jsonEncode(toMap());

  static String _digitalSourceTypeToUrl(DigitalSourceType type) {
    const baseUrl = 'http://cv.iptc.org/newscodes/digitalsourcetype/';
    switch (type) {
      case DigitalSourceType.empty:
        return 'http://c2pa.org/digitalsourcetype/empty';
      case DigitalSourceType.trainedAlgorithmicData:
        return '${baseUrl}trainedAlgorithmicData';
      case DigitalSourceType.digitalCapture:
        return '${baseUrl}digitalCapture';
      case DigitalSourceType.computationalCapture:
        return '${baseUrl}computationalCapture';
      case DigitalSourceType.negativeFilm:
        return '${baseUrl}negativeFilm';
      case DigitalSourceType.positiveFilm:
        return '${baseUrl}positiveFilm';
      case DigitalSourceType.print:
        return '${baseUrl}print';
      case DigitalSourceType.humanEdits:
        return '${baseUrl}humanEdits';
      case DigitalSourceType.compositeWithTrainedAlgorithmicMedia:
        return '${baseUrl}compositeWithTrainedAlgorithmicMedia';
      case DigitalSourceType.algorithmicallyEnhanced:
        return '${baseUrl}algorithmicallyEnhanced';
      case DigitalSourceType.digitalCreation:
        return '${baseUrl}digitalCreation';
      case DigitalSourceType.dataDrivenMedia:
        return '${baseUrl}dataDrivenMedia';
      case DigitalSourceType.trainedAlgorithmicMedia:
        return '${baseUrl}trainedAlgorithmicMedia';
      case DigitalSourceType.algorithmicMedia:
        return '${baseUrl}algorithmicMedia';
      case DigitalSourceType.screenCapture:
        return '${baseUrl}screenCapture';
      case DigitalSourceType.virtualRecording:
        return '${baseUrl}virtualRecording';
      case DigitalSourceType.composite:
        return '${baseUrl}composite';
      case DigitalSourceType.compositeCapture:
        return '${baseUrl}compositeCapture';
      case DigitalSourceType.compositeSynthetic:
        return '${baseUrl}compositeSynthetic';
    }
  }
}

/// Options for building manifests
class BuilderOptions {
  /// The intent for this manifest
  final ManifestIntent? intent;

  /// Digital source type (required for create intent)
  final DigitalSourceType? digitalSourceType;

  /// Whether to embed the manifest in the asset
  final bool embed;

  /// Remote URL for cloud-based manifests
  final String? remoteUrl;

  const BuilderOptions({
    this.intent,
    this.digitalSourceType,
    this.embed = true,
    this.remoteUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'intent': intent?.name,
      'digitalSourceType': digitalSourceType?.name,
      'embed': embed,
      'remoteUrl': remoteUrl,
    };
  }
}

/// Result from builder sign operations
class BuilderSignResult {
  /// The signed asset data
  final Uint8List signedData;

  /// The manifest bytes (if available)
  final Uint8List? manifestBytes;

  /// Size of the C2PA manifest data
  final int manifestSize;

  BuilderSignResult({
    required this.signedData,
    this.manifestBytes,
    required this.manifestSize,
  });
}

/// Archive data from a builder (for serialization)
class BuilderArchive {
  /// The archive data
  final Uint8List data;

  BuilderArchive({required this.data});
}

// =============================================================================
// ManifestBuilder - Abstract interface for building manifests
// =============================================================================

/// Builder for constructing C2PA manifests.
///
/// Use [C2pa.createBuilder] to create a new builder instance. The builder
/// follows a fluent API pattern where you configure the manifest and then
/// sign it.
///
/// ## Basic Usage
///
/// The manifest JSON passed to [C2pa.createBuilder] should contain the title,
/// claim_generator, and any assertions. These cannot be modified after builder
/// creation as the native C2PA libraries don't support dynamic modification.
///
/// ```dart
/// final manifestJson = jsonEncode({
///   'title': 'My Photo',
///   'claim_generator': 'MyApp/1.0',
///   'assertions': [
///     {
///       'label': 'c2pa.actions',
///       'data': {
///         'actions': [
///           {'action': 'c2pa.created', 'digitalSourceType': '...'}
///         ]
///       }
///     }
///   ]
/// });
///
/// final builder = await c2pa.createBuilder(manifestJson);
///
/// // Set the intent (required)
/// builder.setIntent(ManifestIntent.create, DigitalSourceType.digitalCapture);
///
/// // Sign and get result
/// final result = await builder.sign(
///   sourceData: imageBytes,
///   mimeType: 'image/jpeg',
///   signerInfo: signerInfo,
/// );
///
/// // Always dispose when done
/// builder.dispose();
/// ```
///
/// ## Adding Ingredients
///
/// For edit operations, add parent or component ingredients:
///
/// ```dart
/// builder.setIntent(ManifestIntent.edit);
/// await builder.addIngredient(
///   data: parentImageBytes,
///   mimeType: 'image/jpeg',
///   config: IngredientConfig(relationship: IngredientRelationship.parentOf),
/// );
/// ```
///
/// ## Important
///
/// Always call [dispose] when finished to release native resources.
abstract class ManifestBuilder {
  /// The unique handle for this builder (for internal use)
  int get handle;

  /// Set the builder intent
  void setIntent(ManifestIntent intent, [DigitalSourceType? digitalSourceType]);

  /// Disable embedding the manifest in the asset
  void setNoEmbed();

  /// Set a remote URL for cloud-based manifests
  void setRemoteUrl(String url);

  /// Add a resource (thumbnail, icon, etc.)
  Future<void> addResource(ResourceRef resource);

  /// Add an ingredient from data
  Future<void> addIngredient({
    required Uint8List data,
    required String mimeType,
    IngredientConfig? config,
  });

  /// Add an action to the manifest
  void addAction(ActionConfig action);

  /// Export the builder to an archive for later use
  Future<BuilderArchive> toArchive();

  /// Sign the manifest and embed it in the source data
  Future<BuilderSignResult> sign({
    required Uint8List sourceData,
    required String mimeType,
    required SignerInfo signerInfo,
  });

  /// Dispose of native resources
  void dispose();
}

// =============================================================================
// C2PA Main Class
// =============================================================================

/// Main entry point for C2PA operations.
///
/// This class provides all functionality for reading and creating C2PA
/// content credentials (manifests) in Flutter applications.
///
/// ## Usage
///
/// Create a single instance and reuse it throughout your application:
///
/// ```dart
/// final c2pa = C2pa();
/// ```
///
/// ## Reading Manifests
///
/// Use [readFile] or [readBytes] for raw JSON, or [readManifestFromFile]
/// and [readManifestFromBytes] for parsed [ManifestStoreInfo] objects:
///
/// ```dart
/// final store = await c2pa.readManifestFromFile('/path/to/image.jpg');
/// if (store != null && store.validationStatus == ValidationStatus.valid) {
///   print('Valid manifest from: ${store.active?.claimGenerator}');
/// }
/// ```
///
/// ## Creating Manifests
///
/// Use [createBuilder] to construct manifests with the builder pattern:
///
/// ```dart
/// final builder = await c2pa.createBuilder('{"title": "My Image"}');
/// builder.setIntent(ManifestIntent.create, DigitalSourceType.digitalCapture);
/// final result = await builder.sign(...);
/// builder.dispose();
/// ```
///
/// ## See Also
///
/// - [ManifestBuilder] for manifest creation
/// - [ManifestStoreInfo] for reading manifest data
/// - [SignerInfo] for signing configuration
class C2pa {
  // ---------------------------------------------------------------------------
  // Version and Platform Info
  // ---------------------------------------------------------------------------

  /// Get the platform version (iOS/Android version)
  Future<String?> getPlatformVersion() {
    return C2paPlatform.instance.getPlatformVersion();
  }

  /// Get the C2PA library version
  Future<String?> getVersion() {
    return C2paPlatform.instance.getVersion();
  }

  // ---------------------------------------------------------------------------
  // Reader API - Basic
  // ---------------------------------------------------------------------------

  /// Read C2PA manifest from a file path
  ///
  /// Returns the manifest JSON string, or null if no manifest found.
  Future<String?> readFile(String path) {
    return C2paPlatform.instance.readFile(path);
  }

  /// Read C2PA manifest from byte data
  ///
  /// Returns the manifest JSON string, or null if no manifest found.
  Future<String?> readBytes(Uint8List data, String mimeType) {
    return C2paPlatform.instance.readBytes(data, mimeType);
  }

  // ---------------------------------------------------------------------------
  // Reader API - Enhanced
  // ---------------------------------------------------------------------------

  /// Read manifest from a file with detailed information
  ///
  /// Returns a [ManifestStoreInfo] with parsed manifest data and validation info.
  Future<ManifestStoreInfo?> readManifestFromFile(
    String path, {
    ReaderOptions options = const ReaderOptions(),
  }) async {
    final json = await C2paPlatform.instance.readFileDetailed(
      path,
      options.detailed,
      options.dataDir,
    );
    if (json == null) return null;
    return ManifestStoreInfo.fromJson(json);
  }

  /// Read manifest from bytes with detailed information
  ///
  /// Returns a [ManifestStoreInfo] with parsed manifest data and validation info.
  Future<ManifestStoreInfo?> readManifestFromBytes(
    Uint8List data,
    String mimeType, {
    ReaderOptions options = const ReaderOptions(),
  }) async {
    final json = await C2paPlatform.instance.readBytesDetailed(
      data,
      mimeType,
      options.detailed,
    );
    if (json == null) return null;
    return ManifestStoreInfo.fromJson(json);
  }

  /// Extract a resource (thumbnail, etc.) from manifest data
  ///
  /// The [uri] should match an identifier from the manifest JSON.
  Future<Uint8List?> extractResource(
    Uint8List data,
    String mimeType,
    String uri,
  ) {
    return C2paPlatform.instance.extractResource(data, mimeType, uri);
  }

  /// Read ingredient information from a file
  ///
  /// Returns JSON string with ingredient data.
  Future<String?> readIngredientFromFile(String path, {String? dataDir}) {
    return C2paPlatform.instance.readIngredientFile(path, dataDir);
  }

  /// Get supported MIME types for reading
  Future<List<String>> getSupportedReadMimeTypes() {
    return C2paPlatform.instance.getSupportedReadMimeTypes();
  }

  /// Get supported MIME types for signing
  Future<List<String>> getSupportedSignMimeTypes() {
    return C2paPlatform.instance.getSupportedSignMimeTypes();
  }

  // ---------------------------------------------------------------------------
  // Signer API - Basic
  // ---------------------------------------------------------------------------

  /// Sign image bytes with a C2PA manifest
  ///
  /// Returns a [SignResult] with the signed data and optional manifest bytes.
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

  /// Sign a file with a C2PA manifest
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

  // ---------------------------------------------------------------------------
  // Builder API
  // ---------------------------------------------------------------------------

  /// Create a new manifest builder from a JSON manifest definition
  Future<ManifestBuilder> createBuilder(String manifestJson) {
    return C2paPlatform.instance.createBuilder(manifestJson);
  }

  /// Create a manifest builder from a previously saved archive
  Future<ManifestBuilder> createBuilderFromArchive(Uint8List archiveData) {
    return C2paPlatform.instance.createBuilderFromArchive(archiveData);
  }

  // ---------------------------------------------------------------------------
  // Advanced Signing API
  // ---------------------------------------------------------------------------

  /// Create a hashed placeholder for later signing
  ///
  /// This is used for advanced signing workflows where the asset
  /// needs to be prepared before the actual signing occurs.
  Future<Uint8List> createHashedPlaceholder({
    required ManifestBuilder builder,
    required int reservedSize,
    required String mimeType,
  }) {
    return C2paPlatform.instance.createHashedPlaceholder(
      builderHandle: builder.handle,
      reservedSize: reservedSize,
      mimeType: mimeType,
    );
  }

  /// Sign a data-hashed embeddable manifest
  ///
  /// This is used after createHashedPlaceholder for advanced signing workflows.
  Future<Uint8List> signHashedEmbeddable({
    required ManifestBuilder builder,
    required SignerInfo signerInfo,
    required String dataHash,
    required String mimeType,
    Uint8List? assetData,
  }) {
    return C2paPlatform.instance.signHashedEmbeddable(
      builderHandle: builder.handle,
      signerInfo: signerInfo,
      dataHash: dataHash,
      mimeType: mimeType,
      assetData: assetData,
    );
  }

  /// Convert raw manifest bytes to an embeddable format
  ///
  /// A raw manifest (application/c2pa format) cannot be embedded directly.
  /// This converts it to an embeddable format for the specified MIME type.
  ///
  /// **Android note**: This method returns the input unchanged on Android as
  /// the native library does not support this operation. The manifest bytes
  /// from [signHashedEmbeddable] are already in the correct format on Android.
  Future<Uint8List> formatEmbeddable({
    required String mimeType,
    required Uint8List manifestBytes,
  }) {
    return C2paPlatform.instance.formatEmbeddable(
      mimeType: mimeType,
      manifestBytes: manifestBytes,
    );
  }

  /// Get the reserve size needed for a signer
  ///
  /// This is useful for pre-allocating space in assets for the signature.
  Future<int> getSignerReserveSize(SignerInfo signerInfo) {
    return C2paPlatform.instance.getSignerReserveSize(signerInfo);
  }

  // ---------------------------------------------------------------------------
  // Settings API
  // ---------------------------------------------------------------------------

  /// Load C2PA settings from a configuration string
  ///
  /// The [format] should be "json" or "toml".
  Future<void> loadSettings(String settings, {String format = 'json'}) {
    return C2paPlatform.instance.loadSettings(settings, format);
  }
}
