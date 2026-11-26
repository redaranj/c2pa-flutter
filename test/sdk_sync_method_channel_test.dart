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

// Method channel contract for the c2pa-swift 0.1 / c2pa-android 0.1 APIs:
// argument shapes, call ordering, and the native-to-Dart callbacks for
// signing, progress and HTTP resolution.

import 'dart:async';

import 'package:c2pa_flutter/c2pa.dart';
import 'package:c2pa_flutter/c2pa_method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('org.guardianproject.c2pa');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late MethodChannelC2pa platform;
  late List<MethodCall> calls;
  late Map<String, dynamic Function(MethodCall)> responses;
  var nextHandle = 1;

  /// Sends a call from "native" to the Dart handler and decodes the reply.
  Future<dynamic> fromNative(String method, Map<String, dynamic> args) async {
    final completer = Completer<ByteData?>();
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall(method, args)),
      completer.complete,
    );
    final reply = await completer.future;
    return codec.decodeEnvelope(reply!);
  }

  final pem = PemSigner(
    algorithm: SigningAlgorithm.es256,
    certificatePem: 'CERT',
    privateKeyPem: 'KEY',
  );

  setUp(() {
    platform = MethodChannelC2pa();
    calls = [];
    nextHandle = 1;
    responses = {
      'createBuilder': (_) => nextHandle++,
      'createBuilderWithContext': (_) => nextHandle++,
      'createBuilderFromArchive': (_) => nextHandle++,
      'createContext': (_) => nextHandle++,
      'builderPlaceholder': (_) => Uint8List(16),
      'builderSignEmbeddable': (_) => Uint8List(16),
      'builderNeedsPlaceholder': (_) => true,
      'builderHashType': (_) => 'bmffHash',
      'builderWriteIngredientArchive': (_) => Uint8List.fromList([1, 2]),
      'builderSign': (_) => {
        'signedData': Uint8List.fromList([9]),
        'manifestBytes': Uint8List.fromList([8]),
        'manifestSize': 1,
      },
      'builderSignFile': (_) => {
        'manifestBytes': Uint8List.fromList([8]),
        'manifestSize': 1,
      },
      'composeManifest': (_) => Uint8List.fromList([0xFF, 0xEB]),
      'readCrJson': (_) => '{}',
      'readWithManifest': (_) => '{"manifests": {}}',
      'readFragment': (_) => '{"manifests": {}}',
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return responses[call.method]?.call(call);
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Map<dynamic, dynamic> argsOf(String method) =>
      calls.lastWhere((c) => c.method == method).arguments as Map;

  group('builder call ordering', () {
    test('queued configuration is sent before the next async call', () async {
      final builder = await platform.createBuilder('{}');
      builder.setIntent(
        ManifestIntent.create,
        DigitalSourceType.digitalCapture,
      );
      builder.addAction(const ActionConfig(action: 'c2pa.color_adjustments'));
      await builder.placeholder('image/jpeg');

      expect(calls.map((c) => c.method).toList(), [
        'createBuilder',
        'builderSetIntent',
        'builderAddAction',
        'builderPlaceholder',
      ]);
    });

    test('addIngredientFromFile sends the path under "path"', () async {
      final builder = await platform.createBuilder('{}');
      await builder.addIngredientFromFile(path: '/tmp/in.jpg');
      expect(argsOf('builderAddIngredientFromFile')['path'], '/tmp/in.jpg');
    });
  });

  group('embeddable workflow arguments', () {
    test('exclusions are sent as [start, length] pairs', () async {
      final builder = await platform.createBuilder('{}');
      await builder.setDataHashExclusions(const [
        DataHashExclusion(start: 2, length: 100),
        DataHashExclusion(start: 500, length: 10),
      ]);
      expect(argsOf('builderSetDataHashExclusions')['exclusions'], [
        [2, 100],
        [500, 10],
      ]);
    });

    test('hashType parses the native name', () async {
      final builder = await platform.createBuilder('{}');
      expect(await builder.hashType('video/mp4'), C2paHashType.bmffHash);
    });

    test('hashMdatBytes forwards all fields', () async {
      final builder = await platform.createBuilder('{}');
      await builder.hashMdatBytes(
        mdatId: 3,
        data: Uint8List(4),
        largeSize: true,
      );
      final args = argsOf('builderHashMdatBytes');
      expect(args['mdatId'], 3);
      expect(args['largeSize'], true);
    });

    test('composeManifest forwards bytes and type', () async {
      final result = await platform.composeManifest(
        manifestBytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
      );
      expect(result, [0xFF, 0xEB]);
      expect(argsOf('composeManifest')['mimeType'], 'image/jpeg');
    });
  });

  group('signing', () {
    test('sign without a signer sends a null signer', () async {
      final builder = await platform.createBuilder('{}');
      await builder.sign(sourceData: Uint8List(1), mimeType: 'image/jpeg');
      final args = argsOf('builderSign');
      expect(args.containsKey('signer'), isTrue);
      expect(args['signer'], isNull);
    });

    test('signFile returns the manifest', () async {
      final builder = await platform.createBuilder('{}');
      final result = await builder.signFile(
        sourcePath: '/a.jpg',
        destPath: '/b.jpg',
        signer: pem,
      );
      expect(result.manifestSize, 1);
      expect(argsOf('builderSignFile')['destPath'], '/b.jpg');
    });

    test('CawgIdentitySigner nests both signers with callback ids', () async {
      responses['builderSign'] = (call) async {
        final signer = (call.arguments as Map)['signer'] as Map;
        final identity = signer['identitySigner'] as Map;
        // Native would call back into Dart for the identity signature.
        final signature = await fromNative('signCallback', {
          'callbackId': identity['callbackId'],
          'data': Uint8List.fromList([1]),
        });
        return {
          'signedData': signature,
          'manifestBytes': null,
          'manifestSize': 0,
        };
      };
      final builder = await platform.createBuilder('{}');
      final result = await builder.sign(
        sourceData: Uint8List(1),
        mimeType: 'image/jpeg',
        signer: CawgIdentitySigner(
          claimSigner: pem,
          identitySigner: CallbackSigner(
            algorithm: SigningAlgorithm.es256,
            certificateChainPem: 'CHAIN',
            signCallback: (data) async => Uint8List.fromList([7, 7]),
          ),
          referencedAssertions: const ['c2pa.actions'],
        ),
      );
      expect(result.signedData, [7, 7]);

      final signer = argsOf('builderSign')['signer'] as Map;
      expect(signer['type'], 'cawgIdentity');
      expect((signer['claimSigner'] as Map)['type'], 'pem');
      expect((signer['identitySigner'] as Map)['callbackId'], isNotNull);
      expect(signer['referencedAssertions'], ['c2pa.actions']);
    });

    test('a one-shot callback signer is released after the call', () async {
      final builder = await platform.createBuilder('{}');
      await builder.sign(
        sourceData: Uint8List(1),
        mimeType: 'image/jpeg',
        signer: CallbackSigner(
          algorithm: SigningAlgorithm.es256,
          certificateChainPem: 'CHAIN',
          signCallback: (data) async => data,
        ),
      );
      final id = (argsOf('builderSign')['signer'] as Map)['callbackId'];
      await expectLater(
        fromNative('signCallback', {'callbackId': id, 'data': Uint8List(1)}),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'CALLBACK_NOT_FOUND',
          ),
        ),
      );
    });
  });

  group('contexts', () {
    test(
      'createContext sends settings, signer, progress and resolver',
      () async {
        await platform.createContext(
          settingsHandle: 7,
          signer: pem,
          onProgress: (_) {},
          httpResolver: const NativeHttpResolver(),
        );
        final args = argsOf('createContext');
        expect(args['settingsHandle'], 7);
        expect((args['signer'] as Map)['type'], 'pem');
        expect(args['progress'], true);
        expect(args['httpResolver'], 'native');
      },
    );

    test('progress events reach the context callback', () async {
      final updates = <C2paProgress>[];
      final handle = await platform.createContext(onProgress: updates.add);
      await fromNative('contextProgress', {
        'contextHandle': handle,
        'phase': 'signing',
        'step': 2,
        'total': 4,
      });
      expect(updates.single.phase, C2paProgressPhase.signing);
      expect(updates.single.fraction, 0.5);
    });

    test('unknown progress phases map to unknown', () async {
      final updates = <C2paProgress>[];
      final handle = await platform.createContext(onProgress: updates.add);
      await fromNative('contextProgress', {
        'contextHandle': handle,
        'phase': 'somethingNew',
        'step': 1,
        'total': 0,
      });
      expect(updates.single.phase, C2paProgressPhase.unknown);
      expect(updates.single.fraction, isNull);
    });

    test('httpResolve is answered by the Dart resolver', () async {
      final handle = await platform.createContext(
        httpResolver: CallbackHttpResolver((request) async {
          expect(request.url, 'https://example.com/m.c2pa');
          expect(request.headers['Accept'], 'application/c2pa');
          return C2paHttpResponse(status: 200, body: Uint8List.fromList([5]));
        }),
      );
      final reply = await fromNative('httpResolve', {
        'contextHandle': handle,
        'url': 'https://example.com/m.c2pa',
        'method': 'GET',
        'headers': {'Accept': 'application/c2pa'},
        'body': null,
      });
      expect(reply, {
        'status': 200,
        'body': [5],
      });
    });

    test(
      'a context signer callback lives until the context is disposed',
      () async {
        final handle = await platform.createContext(
          signer: CallbackSigner(
            algorithm: SigningAlgorithm.es256,
            certificateChainPem: 'CHAIN',
            signCallback: (data) async => Uint8List.fromList([3]),
          ),
        );
        final id = (argsOf('createContext')['signer'] as Map)['callbackId'];

        for (var i = 0; i < 2; i++) {
          expect(
            await fromNative('signCallback', {
              'callbackId': id,
              'data': Uint8List(1),
            }),
            [3],
          );
        }

        await platform.contextDispose(handle);
        await expectLater(
          fromNative('signCallback', {'callbackId': id, 'data': Uint8List(1)}),
          throwsA(isA<PlatformException>()),
        );
      },
    );

    test('contextCancel targets the handle', () async {
      await platform.contextCancel(4);
      expect(argsOf('contextCancel')['handle'], 4);
    });
  });

  group('reader', () {
    test('readCrJson needs exactly one of path or data', () {
      expect(() => platform.readCrJson(), throwsArgumentError);
      expect(
        () => platform.readCrJson(path: '/a', data: Uint8List(1)),
        throwsArgumentError,
      );
    });

    test('readWithManifest forwards the manifest', () async {
      await platform.readWithManifest(
        data: Uint8List(2),
        mimeType: 'image/jpeg',
        manifestData: Uint8List(3),
        contextHandle: 9,
      );
      final args = argsOf('readWithManifest');
      expect((args['manifestData'] as Uint8List).length, 3);
      expect(args['contextHandle'], 9);
    });

    test('readFragment forwards both paths', () async {
      await platform.readFragment(
        initPath: '/init.mp4',
        fragmentPath: '/f1.m4s',
      );
      final args = argsOf('readFragment');
      expect(args['initPath'], '/init.mp4');
      expect(args['fragmentPath'], '/f1.m4s');
    });
  });
}
