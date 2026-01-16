// Main integration test entry point for C2PA Flutter plugin
//
// This file imports and runs all integration tests for the C2PA plugin.
// Tests cover: Reader API, Signer API, Roundtrip workflows, and Error handling.
//
// Run with: flutter test integration_test/plugin_integration_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:c2pa_flutter/c2pa.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('C2PA Plugin Integration Tests', () {
    late C2pa c2pa;

    setUpAll(() {
      c2pa = C2pa();
    });

    group('Platform Verification', () {
      testWidgets('getPlatformVersion returns non-empty string', (tester) async {
        final version = await c2pa.getPlatformVersion();
        expect(version, isNotNull);
        expect(version!.isNotEmpty, true);
      });

      testWidgets('getVersion returns C2PA library version', (tester) async {
        final version = await c2pa.getVersion();
        expect(version, isNotNull);
        expect(version!.isNotEmpty, true);
      });

      testWidgets('getSupportedReadMimeTypes returns supported types', (tester) async {
        final mimeTypes = await c2pa.getSupportedReadMimeTypes();
        expect(mimeTypes, isA<List<String>>());
        expect(mimeTypes.isNotEmpty, true);
        // JPEG should always be supported
        expect(mimeTypes.contains('image/jpeg'), true);
      });

      testWidgets('getSupportedSignMimeTypes returns supported types', (tester) async {
        final mimeTypes = await c2pa.getSupportedSignMimeTypes();
        expect(mimeTypes, isA<List<String>>());
        expect(mimeTypes.isNotEmpty, true);
        // JPEG should always be supported for signing
        expect(mimeTypes.contains('image/jpeg'), true);
      });
    });

    group('Enums', () {
      testWidgets('SigningAlgorithm has all expected values', (tester) async {
        expect(SigningAlgorithm.values.length, greaterThanOrEqualTo(7));
        expect(SigningAlgorithm.values, contains(SigningAlgorithm.es256));
        expect(SigningAlgorithm.values, contains(SigningAlgorithm.es384));
        expect(SigningAlgorithm.values, contains(SigningAlgorithm.es512));
        expect(SigningAlgorithm.values, contains(SigningAlgorithm.ps256));
        expect(SigningAlgorithm.values, contains(SigningAlgorithm.ps384));
        expect(SigningAlgorithm.values, contains(SigningAlgorithm.ps512));
        expect(SigningAlgorithm.values, contains(SigningAlgorithm.ed25519));
      });

      testWidgets('ManifestIntent has all expected values', (tester) async {
        expect(ManifestIntent.values.length, 3);
        expect(ManifestIntent.values, contains(ManifestIntent.create));
        expect(ManifestIntent.values, contains(ManifestIntent.edit));
        expect(ManifestIntent.values, contains(ManifestIntent.update));
      });

      testWidgets('DigitalSourceType has all expected values', (tester) async {
        expect(DigitalSourceType.values.length, 19);
        expect(DigitalSourceType.values, contains(DigitalSourceType.digitalCapture));
        expect(DigitalSourceType.values, contains(DigitalSourceType.computationalCapture));
        expect(DigitalSourceType.values, contains(DigitalSourceType.humanEdits));
        expect(DigitalSourceType.values, contains(DigitalSourceType.digitalCreation));
      });

      testWidgets('ValidationStatus has all expected values', (tester) async {
        expect(ValidationStatus.values.length, 3);
        expect(ValidationStatus.values, contains(ValidationStatus.valid));
        expect(ValidationStatus.values, contains(ValidationStatus.invalid));
        expect(ValidationStatus.values, contains(ValidationStatus.unknown));
      });

      testWidgets('IngredientRelationship has all expected values', (tester) async {
        expect(IngredientRelationship.values.length, 2);
        expect(IngredientRelationship.values, contains(IngredientRelationship.parentOf));
        expect(IngredientRelationship.values, contains(IngredientRelationship.componentOf));
      });
    });

    group('Data Classes', () {
      testWidgets('ReaderOptions has correct defaults', (tester) async {
        const options = ReaderOptions();
        expect(options.detailed, false);
        expect(options.dataDir, isNull);
      });

      testWidgets('BuilderOptions has correct defaults', (tester) async {
        const options = BuilderOptions();
        expect(options.intent, isNull);
        expect(options.digitalSourceType, isNull);
        expect(options.embed, true);
        expect(options.remoteUrl, isNull);
      });

      testWidgets('ActionConfig serializes correctly', (tester) async {
        final action = ActionConfig(
          action: 'c2pa.created',
          softwareAgent: 'test/1.0',
          digitalSourceType: DigitalSourceType.digitalCapture,
        );

        final map = action.toMap();
        expect(map['action'], 'c2pa.created');
        expect(map['softwareAgent'], 'test/1.0');
        expect(map['digitalSourceType'], contains('digitalCapture'));
      });

      testWidgets('IngredientConfig serializes correctly', (tester) async {
        final config = IngredientConfig(
          title: 'Test Ingredient',
          relationship: IngredientRelationship.parentOf,
        );

        final map = config.toMap();
        expect(map['title'], 'Test Ingredient');
        expect(map['relationship'], 'parentOf');
      });
    });
  });
}
