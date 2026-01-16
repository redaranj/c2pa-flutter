import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:c2pa_flutter/c2pa.dart';
import 'package:c2pa_flutter/c2pa_platform_interface.dart';
import 'package:c2pa_flutter/c2pa_method_channel.dart';

import 'mocks/mock_c2pa_platform.dart';

void main() {
  late MockC2paPlatform mockPlatform;
  late C2pa c2pa;

  setUp(() {
    mockPlatform = MockC2paPlatform();
    C2paPlatform.instance = mockPlatform;
    c2pa = C2pa();
  });

  tearDown(() {
    mockPlatform.reset();
  });

  group('Platform verification', () {
    test('MethodChannelC2pa is the default instance', () {
      // Reset to get actual default
      final initialPlatform = MethodChannelC2pa();
      expect(initialPlatform, isInstanceOf<MethodChannelC2pa>());
    });
  });

  group('Version API', () {
    test('getPlatformVersion returns mock version', () async {
      mockPlatform.platformVersion = 'Test Platform 2.0';
      expect(await c2pa.getPlatformVersion(), 'Test Platform 2.0');
      expect(mockPlatform.methodCalls.last.method, 'getPlatformVersion');
    });

    test('getVersion returns C2PA library version', () async {
      mockPlatform.c2paVersion = '2.0.0-test';
      expect(await c2pa.getVersion(), '2.0.0-test');
      expect(mockPlatform.methodCalls.last.method, 'getVersion');
    });

    test('getVersion handles errors', () async {
      mockPlatform.simulateError = true;
      mockPlatform.errorMessage = 'Version error';
      expect(() => c2pa.getVersion(), throwsException);
    });
  });

  group('Reader API - Basic', () {
    test('readFile reads manifest from path', () async {
      final result = await c2pa.readFile('/path/to/image.jpg');
      expect(result, isNotNull);
      expect(result, contains('active_manifest'));
      expect(mockPlatform.methodCalls.last.method, 'readFile');
      expect(
        mockPlatform.methodCalls.last.arguments!['path'],
        '/path/to/image.jpg',
      );
    });

    test('readBytes reads manifest from bytes', () async {
      final data = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      final result = await c2pa.readBytes(data, 'image/jpeg');
      expect(result, isNotNull);
      expect(mockPlatform.methodCalls.last.method, 'readBytes');
      expect(
        mockPlatform.methodCalls.last.arguments!['mimeType'],
        'image/jpeg',
      );
    });

    test('readFile returns custom manifest JSON', () async {
      mockPlatform.mockManifestJson = '{"custom": "manifest"}';
      final result = await c2pa.readFile('/test.jpg');
      expect(result, '{"custom": "manifest"}');
    });
  });

  group('Reader API - Enhanced', () {
    test('readManifestFromFile returns ManifestStoreInfo', () async {
      final result = await c2pa.readManifestFromFile('/path/to/image.jpg');
      expect(result, isNotNull);
      expect(result!.activeManifest, isNotNull);
      expect(result.manifests, isNotEmpty);
    });

    test('readManifestFromFile with options', () async {
      final result = await c2pa.readManifestFromFile(
        '/path/to/image.jpg',
        options: const ReaderOptions(detailed: true, dataDir: '/tmp/data'),
      );
      expect(result, isNotNull);
      expect(mockPlatform.methodCalls.last.arguments!['detailed'], true);
      expect(mockPlatform.methodCalls.last.arguments!['dataDir'], '/tmp/data');
    });

    test('readManifestFromBytes returns ManifestStoreInfo', () async {
      final data = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      final result = await c2pa.readManifestFromBytes(data, 'image/jpeg');
      expect(result, isNotNull);
      expect(result!.activeManifest, isNotNull);
    });

    test('extractResource returns resource data', () async {
      final sourceData = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      mockPlatform.mockResourceData = Uint8List.fromList([1, 2, 3, 4]);

      final result = await c2pa.extractResource(
        sourceData,
        'image/jpeg',
        'c2pa:thumbnail',
      );
      expect(result, equals(Uint8List.fromList([1, 2, 3, 4])));
    });

    test('readIngredientFromFile returns ingredient JSON', () async {
      final result = await c2pa.readIngredientFromFile(
        '/path/to/ingredient.jpg',
      );
      expect(result, isNotNull);
      expect(result, contains('title'));
    });

    test('getSupportedReadMimeTypes returns list', () async {
      final result = await c2pa.getSupportedReadMimeTypes();
      expect(result, contains('image/jpeg'));
      expect(result, contains('image/png'));
    });

    test('getSupportedSignMimeTypes returns list', () async {
      final result = await c2pa.getSupportedSignMimeTypes();
      expect(result, contains('image/jpeg'));
    });
  });

  group('Signer API', () {
    late SignerInfo signerInfo;
    late Uint8List testData;

    setUp(() {
      signerInfo = SignerInfo(
        algorithm: SigningAlgorithm.es256,
        certificatePem:
            '-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----',
        privateKeyPem:
            '-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----',
      );
      testData = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
    });

    test('signBytes returns SignResult', () async {
      final result = await c2pa.signBytes(
        sourceData: testData,
        mimeType: 'image/jpeg',
        manifestJson: '{"title": "Test"}',
        signerInfo: signerInfo,
      );

      expect(result.signedData, isNotNull);
      expect(result.signedDataSize, greaterThan(0));
      expect(mockPlatform.methodCalls.last.method, 'signBytes');
    });

    test('signBytes with TSA URL', () async {
      final signerWithTsa = SignerInfo(
        algorithm: SigningAlgorithm.es256,
        certificatePem:
            '-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----',
        privateKeyPem:
            '-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----',
        tsaUrl: 'https://timestamp.example.com',
      );

      final result = await c2pa.signBytes(
        sourceData: testData,
        mimeType: 'image/jpeg',
        manifestJson: '{"title": "Test"}',
        signerInfo: signerWithTsa,
      );

      expect(result.signedData, isNotNull);
    });

    test('signFile signs file', () async {
      await c2pa.signFile(
        sourcePath: '/input.jpg',
        destPath: '/output.jpg',
        manifestJson: '{"title": "Test"}',
        signerInfo: signerInfo,
      );

      expect(mockPlatform.methodCalls.last.method, 'signFile');
      expect(
        mockPlatform.methodCalls.last.arguments!['sourcePath'],
        '/input.jpg',
      );
      expect(
        mockPlatform.methodCalls.last.arguments!['destPath'],
        '/output.jpg',
      );
    });

    test('all signing algorithms are supported', () async {
      for (final algorithm in SigningAlgorithm.values) {
        final info = SignerInfo(
          algorithm: algorithm,
          certificatePem:
              '-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----',
          privateKeyPem:
              '-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----',
        );

        final result = await c2pa.signBytes(
          sourceData: testData,
          mimeType: 'image/jpeg',
          manifestJson: '{"title": "Test ${algorithm.name}"}',
          signerInfo: info,
        );

        expect(
          result.signedData,
          isNotNull,
          reason: 'Failed for ${algorithm.name}',
        );
      }
    });
  });

  group('Builder API', () {
    late SignerInfo signerInfo;
    late Uint8List testData;

    setUp(() {
      signerInfo = SignerInfo(
        algorithm: SigningAlgorithm.es256,
        certificatePem:
            '-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----',
        privateKeyPem:
            '-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----',
      );
      testData = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
    });

    test('createBuilder creates builder', () async {
      final builder = await c2pa.createBuilder('{"title": "Test"}');
      expect(builder, isNotNull);
      expect(builder.handle, greaterThan(0));
      expect(mockPlatform.methodCalls.last.method, 'createBuilder');
    });

    test('createBuilderFromArchive creates builder', () async {
      final archiveData = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]);
      final builder = await c2pa.createBuilderFromArchive(archiveData);
      expect(builder, isNotNull);
      expect(mockPlatform.methodCalls.last.method, 'createBuilderFromArchive');
    });

    test('builder setIntent works', () async {
      final builder = await c2pa.createBuilder('{}');
      builder.setIntent(
        ManifestIntent.create,
        DigitalSourceType.digitalCapture,
      );

      final mockBuilder = mockPlatform.builders[builder.handle] as MockBuilder;
      expect(mockBuilder.intent, ManifestIntent.create);
      expect(mockBuilder.digitalSourceType, DigitalSourceType.digitalCapture);
    });

    test('builder setNoEmbed works', () async {
      final builder = await c2pa.createBuilder('{}');
      builder.setNoEmbed();

      final mockBuilder = mockPlatform.builders[builder.handle] as MockBuilder;
      expect(mockBuilder.noEmbed, true);
    });

    test('builder setRemoteUrl works', () async {
      final builder = await c2pa.createBuilder('{}');
      builder.setRemoteUrl('https://example.com/manifest');

      final mockBuilder = mockPlatform.builders[builder.handle] as MockBuilder;
      expect(mockBuilder.remoteUrl, 'https://example.com/manifest');
    });

    test('builder addResource works', () async {
      final builder = await c2pa.createBuilder('{}');
      final thumbnail = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);

      await builder.addResource(
        ResourceRef(
          uri: 'c2pa:thumbnail.jpg',
          data: thumbnail,
          mimeType: 'image/jpeg',
        ),
      );

      expect(
        mockPlatform.builders[builder.handle]!.resources['c2pa:thumbnail.jpg'],
        equals(thumbnail),
      );
    });

    test('builder addIngredient works', () async {
      final builder = await c2pa.createBuilder('{}');
      final ingredientData = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);

      await builder.addIngredient(
        data: ingredientData,
        mimeType: 'image/jpeg',
        config: IngredientConfig(
          title: 'Test Ingredient',
          relationship: IngredientRelationship.parentOf,
        ),
      );

      expect(mockPlatform.builders[builder.handle]!.ingredients, hasLength(1));
    });

    test('builder addAction works', () async {
      final builder = await c2pa.createBuilder('{}');

      builder.addAction(
        ActionConfig(
          action: 'c2pa.created',
          softwareAgent: 'TestApp/1.0',
          digitalSourceType: DigitalSourceType.digitalCapture,
        ),
      );

      final mockBuilder = mockPlatform.builders[builder.handle] as MockBuilder;
      expect(mockBuilder.actions, hasLength(1));
    });

    test('builder addAssertion works', () async {
      final builder = await c2pa.createBuilder('{}');

      builder.addAssertion('custom.assertion', {'key': 'value'});

      final mockBuilder = mockPlatform.builders[builder.handle] as MockBuilder;
      expect(mockBuilder.assertions, hasLength(1));
      expect(mockBuilder.assertions.first.label, 'custom.assertion');
    });

    test('builder toArchive returns archive', () async {
      final builder = await c2pa.createBuilder('{}');
      final archive = await builder.toArchive();

      expect(archive.data, isNotNull);
      expect(archive.data.length, greaterThan(0));
    });

    test('builder sign returns result', () async {
      final builder = await c2pa.createBuilder('{}');

      final result = await builder.sign(
        sourceData: testData,
        mimeType: 'image/jpeg',
        signerInfo: signerInfo,
      );

      expect(result.signedData, isNotNull);
      expect(result.manifestSize, greaterThanOrEqualTo(0));
    });

    test('builder signFile works', () async {
      final builder = await c2pa.createBuilder('{}');

      await builder.signFile(
        sourcePath: '/input.jpg',
        destPath: '/output.jpg',
        signerInfo: signerInfo,
      );

      expect(
        mockPlatform.methodCalls.any((c) => c.method == 'builderSignFile'),
        true,
      );
    });

    test('builder dispose works', () async {
      final builder = await c2pa.createBuilder('{}');
      final handle = builder.handle;

      builder.dispose();

      expect(mockPlatform.builders.containsKey(handle), false);
    });

    test('disposed builder throws error', () async {
      final builder = await c2pa.createBuilder('{}');
      builder.dispose();

      expect(() => builder.setTitle('Test'), throwsStateError);
    });
  });

  group('Advanced Signing API', () {
    late SignerInfo signerInfo;
    late ManifestBuilder builder;

    setUp(() async {
      signerInfo = SignerInfo(
        algorithm: SigningAlgorithm.es256,
        certificatePem:
            '-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----',
        privateKeyPem:
            '-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----',
      );
      builder = await c2pa.createBuilder('{}');
    });

    test('createHashedPlaceholder returns data', () async {
      final placeholder = await c2pa.createHashedPlaceholder(
        builder: builder,
        reservedSize: 5000,
        mimeType: 'image/jpeg',
      );

      expect(placeholder, isNotNull);
      expect(placeholder.length, 5000);
    });

    test('signHashedEmbeddable returns manifest', () async {
      final manifest = await c2pa.signHashedEmbeddable(
        builder: builder,
        signerInfo: signerInfo,
        dataHash: 'abc123hash',
        mimeType: 'image/jpeg',
      );

      expect(manifest, isNotNull);
      expect(manifest.length, greaterThan(0));
    });

    test('formatEmbeddable returns formatted data', () async {
      final manifestBytes = Uint8List.fromList([0xC2, 0xAA, 0x00, 0x01]);
      final formatted = await c2pa.formatEmbeddable(
        mimeType: 'image/jpeg',
        manifestBytes: manifestBytes,
      );

      expect(formatted, equals(manifestBytes));
    });

    test('getSignerReserveSize returns size', () async {
      mockPlatform.mockReserveSize = 12345;
      final size = await c2pa.getSignerReserveSize(signerInfo);

      expect(size, 12345);
    });
  });

  group('Settings API', () {
    test('loadSettings loads JSON settings', () async {
      await c2pa.loadSettings('{"setting": "value"}');

      expect(mockPlatform.methodCalls.last.method, 'loadSettings');
      expect(mockPlatform.methodCalls.last.arguments!['format'], 'json');
    });

    test('loadSettings loads TOML settings', () async {
      await c2pa.loadSettings('[settings]\nkey = "value"', format: 'toml');

      expect(mockPlatform.methodCalls.last.arguments!['format'], 'toml');
    });
  });

  group('Error handling', () {
    test('error is propagated from platform', () async {
      mockPlatform.simulateError = true;
      mockPlatform.errorMessage = 'Test error';

      expect(() => c2pa.getPlatformVersion(), throwsException);
    });

    test('readFile handles error', () async {
      mockPlatform.simulateError = true;
      mockPlatform.errorMessage = 'File not found';

      expect(() => c2pa.readFile('/nonexistent.jpg'), throwsException);
    });

    test('signBytes handles error', () async {
      mockPlatform.simulateError = true;
      mockPlatform.errorMessage = 'Signing failed';

      final signerInfo = SignerInfo(
        algorithm: SigningAlgorithm.es256,
        certificatePem: 'cert',
        privateKeyPem: 'key',
      );

      expect(
        () => c2pa.signBytes(
          sourceData: Uint8List(1),
          mimeType: 'image/jpeg',
          manifestJson: '{}',
          signerInfo: signerInfo,
        ),
        throwsException,
      );
    });
  });

  group('Data classes', () {
    group('SignerInfo', () {
      test('toMap serializes correctly', () {
        final info = SignerInfo(
          algorithm: SigningAlgorithm.ps256,
          certificatePem: 'cert_pem',
          privateKeyPem: 'key_pem',
          tsaUrl: 'https://tsa.example.com',
        );

        final map = info.toMap();
        expect(map['algorithm'], 'ps256');
        expect(map['certificatePem'], 'cert_pem');
        expect(map['privateKeyPem'], 'key_pem');
        expect(map['tsaUrl'], 'https://tsa.example.com');
      });

      test('fromMap deserializes correctly', () {
        final map = {
          'algorithm': 'ed25519',
          'certificatePem': 'cert',
          'privateKeyPem': 'key',
          'tsaUrl': null,
        };

        final info = SignerInfo.fromMap(map);
        expect(info.algorithm, SigningAlgorithm.ed25519);
        expect(info.certificatePem, 'cert');
        expect(info.tsaUrl, isNull);
      });
    });

    group('ReaderOptions', () {
      test('default values', () {
        const options = ReaderOptions();
        expect(options.detailed, false);
        expect(options.dataDir, isNull);
      });

      test('toMap serializes correctly', () {
        const options = ReaderOptions(detailed: true, dataDir: '/data');
        final map = options.toMap();
        expect(map['detailed'], true);
        expect(map['dataDir'], '/data');
      });
    });

    group('ActionConfig', () {
      test('toJson serializes correctly', () {
        final action = ActionConfig(
          action: 'c2pa.edited',
          when: DateTime(2024, 1, 15),
          softwareAgent: 'TestApp/1.0',
          digitalSourceType: DigitalSourceType.humanEdits,
        );

        final json = action.toJson();
        expect(json, contains('c2pa.edited'));
        expect(json, contains('TestApp/1.0'));
        expect(json, contains('humanEdits'));
      });
    });

    group('IngredientConfig', () {
      test('toJson serializes relationship correctly', () {
        final config = IngredientConfig(
          title: 'Test Ingredient',
          relationship: IngredientRelationship.parentOf,
        );

        final json = config.toJson();
        expect(json, contains('parentOf'));
        expect(json, contains('Test Ingredient'));
      });
    });

    group('ManifestStoreInfo', () {
      test('fromJson parses correctly', () {
        const json = '''
      {
        "active_manifest": "urn:uuid:test",
        "manifests": {
          "urn:uuid:test": {
            "label": "urn:uuid:test",
            "title": "Test Image",
            "format": "image/jpeg",
            "claim_generator": "test/1.0",
            "assertions": [],
            "ingredients": []
          }
        },
        "validation_status": []
      }
      ''';

        final info = ManifestStoreInfo.fromJson(json);
        expect(info.activeManifest, 'urn:uuid:test');
        expect(info.manifests.length, 1);
        expect(info.active?.title, 'Test Image');
        expect(info.validationStatus, ValidationStatus.valid);
      });

      test('validation errors are parsed', () {
        const json = '''
      {
        "active_manifest": null,
        "manifests": {},
        "validation_status": [
          {"code": "ERR001", "message": "Invalid signature"}
        ]
      }
      ''';

        final info = ManifestStoreInfo.fromJson(json);
        expect(info.validationErrors, hasLength(1));
        expect(info.validationErrors.first.code, 'ERR001');
        expect(info.validationStatus, ValidationStatus.invalid);
      });
    });
  });
}
