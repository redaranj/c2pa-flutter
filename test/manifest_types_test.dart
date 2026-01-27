import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:c2pa_flutter/c2pa.dart';

void main() {
  group('Enums', () {
    test('PredefinedAction has correct values', () {
      expect(PredefinedAction.created.value, 'c2pa.created');
      expect(PredefinedAction.edited.value, 'c2pa.edited');
      expect(PredefinedAction.aiGenerated.value, 'c2pa.ai_generated');
    });

    test('Relationship serializes correctly', () {
      expect(Relationship.parentOf.toJson(), 'parentOf');
      expect(Relationship.componentOf.toJson(), 'componentOf');
      expect(Relationship.inputTo.toJson(), 'inputTo');
    });

    test('Relationship deserializes correctly', () {
      expect(Relationship.fromJson('parentOf'), Relationship.parentOf);
      expect(Relationship.fromJson('componentOf'), Relationship.componentOf);
      expect(Relationship.fromJson('inputTo'), Relationship.inputTo);
      expect(Relationship.fromJson('unknown'), Relationship.componentOf);
    });

    test('DigitalSourceType has correct URLs', () {
      expect(
        DigitalSourceType.digitalCapture.url,
        'http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture',
      );
      expect(
        DigitalSourceType.trainedAlgorithmicMedia.url,
        'http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia',
      );
      expect(
        DigitalSourceType.empty.url,
        'http://c2pa.org/digitalsourcetype/empty',
      );
    });

    test('DigitalSourceType.fromUrl works', () {
      expect(
        DigitalSourceType.fromUrl(
          'http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture',
        ),
        DigitalSourceType.digitalCapture,
      );
      expect(DigitalSourceType.fromUrl(null), isNull);
      expect(DigitalSourceType.fromUrl('unknown'), isNull);
    });

    test('Role has correct values', () {
      expect(Role.edited.value, 'c2pa.edited');
      expect(Role.cropped.value, 'c2pa.cropped');
    });

    test('ImageRegionType has correct URLs', () {
      expect(
        ImageRegionType.crop.url,
        'http://cv.iptc.org/newscodes/imageregionrole/crop',
      );
    });
  });

  group('Coordinate', () {
    test('toJson and fromJson round-trip', () {
      final coord = Coordinate(x: 10.5, y: 20.3);
      final json = coord.toJson();
      final decoded = Coordinate.fromJson(json);

      expect(decoded.x, 10.5);
      expect(decoded.y, 20.3);
    });

    test('equality works', () {
      final a = Coordinate(x: 1, y: 2);
      final b = Coordinate(x: 1, y: 2);
      final c = Coordinate(x: 3, y: 4);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('Shape', () {
    test('rectangle factory creates correct shape', () {
      final shape = Shape.rectangle(
        origin: Coordinate(x: 0, y: 0),
        width: 100,
        height: 50,
        unit: UnitType.pixel,
      );

      expect(shape.type, ShapeType.rectangle);
      expect(shape.width, 100);
      expect(shape.height, 50);
    });

    test('circle factory creates correct shape', () {
      final shape = Shape.circle(
        origin: Coordinate(x: 50, y: 50),
        radius: 25,
      );

      expect(shape.type, ShapeType.circle);
      expect(shape.radius, 25);
    });

    test('polygon factory creates correct shape', () {
      final shape = Shape.polygon(
        vertices: [
          Coordinate(x: 0, y: 0),
          Coordinate(x: 100, y: 0),
          Coordinate(x: 50, y: 100),
        ],
      );

      expect(shape.type, ShapeType.polygon);
      expect(shape.vertices?.length, 3);
    });

    test('toJson and fromJson round-trip', () {
      final shape = Shape.rectangle(
        origin: Coordinate(x: 10, y: 20),
        width: 100,
        height: 50,
        inside: true,
        unit: UnitType.percent,
      );

      final json = shape.toJson();
      final decoded = Shape.fromJson(json);

      expect(decoded.type, ShapeType.rectangle);
      expect(decoded.origin?.x, 10);
      expect(decoded.width, 100);
      expect(decoded.inside, true);
      expect(decoded.unit, UnitType.percent);
    });
  });

  group('RegionRange', () {
    test('SpatialRange serializes correctly', () {
      final range = SpatialRange(
        shape: Shape.rectangle(
          origin: Coordinate(x: 0, y: 0),
          width: 100,
          height: 100,
        ),
      );

      final json = range.toJson();
      expect(json.containsKey('shape'), true);
    });

    test('TemporalRange serializes correctly', () {
      final range = TemporalRange(
        time: Time(start: '0:00', end: '1:30'),
      );

      final json = range.toJson();
      expect(json.containsKey('time'), true);
    });

    test('FrameRange serializes correctly', () {
      final range = FrameRange(frame: Frame(start: 0, end: 100));

      final json = range.toJson();
      expect(json.containsKey('frame'), true);
    });

    test('RegionRange.fromJson detects type correctly', () {
      final spatial = RegionRange.fromJson({
        'shape': {'type': 'rectangle', 'width': 100, 'height': 100}
      });
      expect(spatial, isA<SpatialRange>());

      final temporal = RegionRange.fromJson({
        'time': {'start': '0:00', 'end': '1:00'}
      });
      expect(temporal, isA<TemporalRange>());

      final frame = RegionRange.fromJson({'frame': {'start': 0, 'end': 100}});
      expect(frame, isA<FrameRange>());
    });
  });

  group('RegionOfInterest', () {
    test('spatial factory creates correct region', () {
      final region = RegionOfInterest.spatial(
        shape: Shape.rectangle(
          origin: Coordinate(x: 0, y: 0),
          width: 100,
          height: 100,
        ),
        role: Role.edited,
        regionType: ImageRegionType.mainSubject,
      );

      expect(region.region.length, 1);
      expect(region.region.first, isA<SpatialRange>());
      expect(region.role, Role.edited);
    });

    test('toJson and fromJson round-trip', () {
      final region = RegionOfInterest(
        region: [
          SpatialRange(
            shape: Shape.rectangle(
              origin: Coordinate(x: 10, y: 20),
              width: 50,
              height: 50,
            ),
          ),
        ],
        description: 'Test region',
        name: 'Region 1',
        role: Role.areaOfInterest,
      );

      final json = region.toJson();
      final decoded = RegionOfInterest.fromJson(json);

      expect(decoded.description, 'Test region');
      expect(decoded.name, 'Region 1');
      expect(decoded.region.length, 1);
    });
  });

  group('Action', () {
    test('created factory sets correct values', () {
      final action = Action.created(
        sourceType: DigitalSourceType.digitalCapture,
        softwareAgent: 'TestApp/1.0',
      );

      expect(action.action, 'c2pa.created');
      expect(action.digitalSourceType, DigitalSourceType.digitalCapture.url);
      expect(action.softwareAgent, 'TestApp/1.0');
    });

    test('edited factory sets correct values', () {
      final action = Action.edited(
        softwareAgent: 'TestApp/1.0',
        changes: [
          RegionOfInterest.spatial(
            shape: Shape.rectangle(
              origin: Coordinate(x: 0, y: 0),
              width: 100,
              height: 100,
            ),
          ),
        ],
      );

      expect(action.action, 'c2pa.edited');
      expect(action.changes?.length, 1);
    });

    test('aiGenerated factory sets correct values', () {
      final action = Action.aiGenerated(
        sourceType: DigitalSourceType.trainedAlgorithmicMedia,
        softwareAgent: 'AI Model v1',
        parameters: {'model': 'test-model'},
      );

      expect(action.action, 'c2pa.ai_generated');
      expect(
        action.digitalSourceType,
        DigitalSourceType.trainedAlgorithmicMedia.url,
      );
      expect(action.parameters?['model'], 'test-model');
    });

    test('toJson and fromJson round-trip', () {
      final action = Action(
        action: 'c2pa.edited',
        softwareAgent: 'TestApp/1.0',
        when: '2024-01-15T10:30:00Z',
        parameters: {'key': 'value'},
      );

      final json = action.toJson();
      final decoded = Action.fromJson(json);

      expect(decoded.action, 'c2pa.edited');
      expect(decoded.softwareAgent, 'TestApp/1.0');
      expect(decoded.when, '2024-01-15T10:30:00Z');
      expect(decoded.parameters?['key'], 'value');
    });
  });

  group('Ingredient', () {
    test('parent factory sets correct relationship', () {
      final ingredient = Ingredient.parent(title: 'Parent Image');

      expect(ingredient.relationship, Relationship.parentOf);
      expect(ingredient.title, 'Parent Image');
    });

    test('component factory sets correct relationship', () {
      final ingredient = Ingredient.component(title: 'Component');

      expect(ingredient.relationship, Relationship.componentOf);
    });

    test('toJson and fromJson round-trip', () {
      final ingredient = Ingredient(
        title: 'Test Ingredient',
        format: 'image/jpeg',
        relationship: Relationship.parentOf,
        documentId: 'doc-123',
        instanceId: 'inst-456',
      );

      final json = ingredient.toJson();
      final decoded = Ingredient.fromJson(json);

      expect(decoded.title, 'Test Ingredient');
      expect(decoded.format, 'image/jpeg');
      expect(decoded.relationship, Relationship.parentOf);
      expect(decoded.documentId, 'doc-123');
    });
  });

  group('ClaimGeneratorInfo', () {
    test('claimGeneratorString formats correctly', () {
      final info = ClaimGeneratorInfo(name: 'TestApp', version: '1.0.0');
      expect(info.claimGeneratorString, 'TestApp/1.0.0');

      final infoNoVersion = ClaimGeneratorInfo(name: 'TestApp');
      expect(infoNoVersion.claimGeneratorString, 'TestApp');
    });

    test('toJson and fromJson round-trip', () {
      final info = ClaimGeneratorInfo(
        name: 'TestApp',
        version: '2.0',
        icon: {'format': 'image/png', 'identifier': 'icon.png'},
      );

      final json = info.toJson();
      final decoded = ClaimGeneratorInfo.fromJson(json);

      expect(decoded.name, 'TestApp');
      expect(decoded.version, '2.0');
      expect(decoded.icon?['format'], 'image/png');
    });
  });

  group('TrainingMiningEntry', () {
    test('dataMining factory creates correct entry', () {
      final entry = TrainingMiningEntry.dataMining(
        permission: TrainingMiningPermission.notAllowed,
      );

      expect(entry.use, 'dataMining');
      expect(entry.permission, TrainingMiningPermission.notAllowed);
    });

    test('aiTraining factory creates correct entry', () {
      final entry = TrainingMiningEntry.aiTraining(
        permission: TrainingMiningPermission.constrained,
        constraintInfo: 'Only for research',
      );

      expect(entry.use, 'aiTraining');
      expect(entry.permission, TrainingMiningPermission.constrained);
      expect(entry.constraintInfo, 'Only for research');
    });

    test('toJson serializes permission correctly', () {
      final entry = TrainingMiningEntry(
        use: 'aiInference',
        permission: TrainingMiningPermission.allowed,
      );

      final json = entry.toJson();
      expect(json['use'], 'aiInference');
      expect(json['allowed'], true);
    });
  });

  group('Assertions', () {
    test('ActionsAssertion serializes correctly', () {
      final assertion = ActionsAssertion(
        actions: [
          Action.created(sourceType: DigitalSourceType.digitalCapture),
        ],
      );

      final json = assertion.toJson();
      expect(json['label'], 'c2pa.actions');
      expect((json['data'] as Map)['actions'], isA<List>());
    });

    test('CreativeWorkAssertion serializes correctly', () {
      final assertion = CreativeWorkAssertion(
        author: 'John Doe',
        copyrightNotice: '2024 John Doe',
      );

      final json = assertion.toJson();
      expect(json['label'], 'stds.schema-org.CreativeWork');
      expect((json['data'] as Map)['author'], 'John Doe');
      expect((json['data'] as Map)['@context'], 'https://schema.org/');
    });

    test('TrainingMiningAssertion serializes correctly', () {
      final assertion = TrainingMiningAssertion(
        entries: [
          TrainingMiningEntry.aiTraining(
            permission: TrainingMiningPermission.notAllowed,
          ),
        ],
      );

      final json = assertion.toJson();
      expect(json['label'], 'c2pa.training-mining');
    });

    test('CustomAssertion allows arbitrary data', () {
      final assertion = CustomAssertion(
        label: 'custom.my-assertion',
        data: {'key': 'value', 'number': 42},
      );

      final json = assertion.toJson();
      expect(json['label'], 'custom.my-assertion');
      expect((json['data'] as Map)['key'], 'value');
    });

    test('AssertionDefinition.fromJson parses actions assertion', () {
      final json = {
        'label': 'c2pa.actions',
        'data': {
          'actions': [
            {'action': 'c2pa.created'}
          ]
        }
      };

      final assertion = AssertionDefinition.fromJson(json);
      expect(assertion, isA<ActionsAssertion>());
      expect((assertion as ActionsAssertion).actions.length, 1);
    });
  });

  group('ManifestDefinition', () {
    test('created factory generates correct manifest', () {
      final manifest = ManifestDefinition.created(
        title: 'My Photo',
        claimGenerator: ClaimGeneratorInfo(name: 'TestApp', version: '1.0'),
        sourceType: DigitalSourceType.digitalCapture,
      );

      expect(manifest.title, 'My Photo');
      expect(manifest.claimGeneratorInfo.length, 1);
      expect(manifest.assertions.length, 1);
      expect(manifest.assertions.first, isA<ActionsAssertion>());
    });

    test('aiGenerated factory generates correct manifest', () {
      final manifest = ManifestDefinition.aiGenerated(
        title: 'AI Image',
        claimGenerator: ClaimGeneratorInfo(name: 'AIApp', version: '2.0'),
        trainingMining: TrainingMiningAssertion(
          entries: [
            TrainingMiningEntry.aiTraining(
              permission: TrainingMiningPermission.notAllowed,
            ),
          ],
        ),
      );

      expect(manifest.title, 'AI Image');
      expect(manifest.assertions.length, 2);
    });

    test('toJsonString produces valid JSON', () {
      final manifest = ManifestDefinition(
        title: 'Test Image',
        claimGeneratorInfo: [ClaimGeneratorInfo(name: 'Test', version: '1.0')],
        assertions: [
          ActionsAssertion(actions: [Action.created()]),
        ],
      );

      final jsonStr = manifest.toJsonString();
      expect(() => jsonDecode(jsonStr), returnsNormally);

      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(decoded['title'], 'Test Image');
      expect(decoded['claim_generator'], 'Test/1.0');
    });

    test('fromJson and toJson round-trip', () {
      final original = ManifestDefinition(
        title: 'Round Trip Test',
        claimGeneratorInfo: [
          ClaimGeneratorInfo(name: 'TestApp', version: '1.0'),
        ],
        assertions: [
          ActionsAssertion(
            actions: [
              Action.created(sourceType: DigitalSourceType.digitalCapture),
            ],
          ),
          CreativeWorkAssertion(author: 'Test Author'),
        ],
        ingredients: [
          Ingredient.parent(title: 'Parent Image'),
        ],
        vendor: 'test-vendor',
        format: 'image/jpeg',
      );

      final jsonStr = original.toJsonString();
      final decoded = ManifestDefinition.fromJson(jsonStr);

      expect(decoded.title, 'Round Trip Test');
      expect(decoded.claimGeneratorInfo.length, 1);
      expect(decoded.assertions.length, 2);
      expect(decoded.ingredients.length, 1);
      expect(decoded.vendor, 'test-vendor');
      expect(decoded.format, 'image/jpeg');
    });

    test('toJson includes claim_generator for compatibility', () {
      final manifest = ManifestDefinition(
        title: 'Test',
        claimGeneratorInfo: [
          ClaimGeneratorInfo(name: 'App', version: '1.0'),
        ],
      );

      final json = manifest.toJson();
      expect(json['claim_generator'], 'App/1.0');
      expect(json['claim_generator_info'], isA<List>());
    });
  });

  group('ResourceRef', () {
    test('toJson and fromJson round-trip', () {
      final ref = ResourceRef(
        identifier: 'self#jumbf=/c2pa/thumbnail.jpg',
        format: 'image/jpeg',
      );

      final json = ref.toJson();
      final decoded = ResourceRef.fromJson(json);

      expect(decoded.identifier, ref.identifier);
      expect(decoded.format, 'image/jpeg');
    });
  });

  group('HashedUri', () {
    test('toJson and fromJson round-trip', () {
      final uri = HashedUri(
        url: 'https://example.com/cert',
        alg: 'sha256',
        hash: 'abc123',
      );

      final json = uri.toJson();
      final decoded = HashedUri.fromJson(json);

      expect(decoded.url, uri.url);
      expect(decoded.alg, 'sha256');
      expect(decoded.hash, 'abc123');
    });
  });

  group('ValidationResults', () {
    test('toJson and fromJson round-trip', () {
      final results = ValidationResults(
        errors: [ValidationStatusEntry(code: 'ERR01', explanation: 'Error')],
        warnings: [ValidationStatusEntry(code: 'WARN01')],
        informational: [],
      );

      final json = results.toJson();
      final decoded = ValidationResults.fromJson(json);

      expect(decoded.errors.length, 1);
      expect(decoded.warnings.length, 1);
      expect(decoded.errors.first.code, 'ERR01');
    });
  });

  group('Metadata', () {
    test('toJson and fromJson round-trip', () {
      final metadata = Metadata(
        dateTime: DateTime(2024, 1, 15, 10, 30),
        reference: 'ref-123',
        dataSource: DataSource(type: 'localProvider'),
      );

      final json = metadata.toJson();
      final decoded = Metadata.fromJson(json);

      expect(decoded.dateTime?.year, 2024);
      expect(decoded.reference, 'ref-123');
      expect(decoded.dataSource?.type, 'localProvider');
    });
  });
}
