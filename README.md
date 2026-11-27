# c2pa_flutter

A Flutter plugin for [C2PA](https://c2pa.org/) (Coalition for Content Provenance and Authenticity) that reads, signs and verifies content credentials on iOS and Android.

It wraps the official native SDKs, [c2pa-swift](https://github.com/contentauth/c2pa-swift) 0.1.0 and [c2pa-android](https://github.com/contentauth/c2pa-android) 0.1.2. Both are built on c2pa-rs 0.92.

## Features

- Read manifest stores from files or bytes, as JSON, detailed JSON or crJSON
- Validate assets against sidecar or remote manifests
- Sign with PEM keys, Dart callbacks, the platform keystore, hardware keys (StrongBox / Secure Enclave), remote signing services, or a signer defined in settings
- Combine a claim signer with an X.509 identity signer for CAWG identity assertions
- Build manifests step by step: intents, actions, ingredients, resources, archives and ingredient archives
- Embeddable manifests for data-hash (JPEG, PNG, ...) and BMFF (MP4, HEIF, ...) workflows, including fragmented-MP4 Merkle hashing
- Contexts that carry settings, a signer, a progress callback, cancellation and an HTTP resolver
- Key management: create, import and export keys, CSRs, and hardware key enrollment

## Platform Support

| Platform | Minimum | Build requirement |
|----------|---------|-------------------|
| iOS      | 16.0    | Xcode 26.4+ (c2pa-swift declares Swift tools 6.3); Swift Package Manager |
| Android  | API 28  | compileSdk 36 |

iOS builds use Swift Package Manager only. Enable it with `flutter config --enable-swift-package-manager`.

## Installation

```yaml
dependencies:
  c2pa_flutter:
    git:
      url: https://github.com/guardianproject/c2pa-flutter.git
```

Android apps also need JitPack in their repositories, because c2pa-android is published there:

```groovy
maven { url 'https://jitpack.io' }
```

## Usage

```dart
import 'package:c2pa_flutter/c2pa.dart';

final c2pa = C2pa();
```

### Read

```dart
// Throws C2paManifestNotFoundException when the asset has no manifest.
final json = await c2pa.readFile('/path/to/image.jpg');

final store = await c2pa.readManifestFromBytes(
  bytes,
  'image/jpeg',
  options: const ReaderOptions(detailed: true),
);

final crJson = await c2pa.readCrJsonFromFile('/path/to/image.jpg');

// Validate an asset against a manifest stored separately.
final sidecar = await c2pa.readBytesWithManifest(bytes, 'image/jpeg', manifest);

// Resources such as thumbnails come out through extractResource.
final thumbnail = await c2pa.extractResource(bytes, 'image/jpeg', uri);
```

### Sign

```dart
final signer = PemSigner(
  algorithm: SigningAlgorithm.es256,
  certificatePem: certificateChainPem,
  privateKeyPem: privateKeyPem,
  tsaUrl: 'http://timestamp.digicert.com', // optional
);

final builder = await c2pa.createBuilder(manifestJson);
await builder.setIntent(ManifestIntent.create, DigitalSourceType.digitalCapture);
final result = await builder.sign(
  sourceData: bytes,
  mimeType: 'image/jpeg',
  signer: signer,
);

// Large files: stream natively instead of passing bytes through Dart.
await builder.signFile(
  sourcePath: '/path/to/video.mp4',
  destPath: '/path/to/signed.mp4',
  signer: signer,
);
await builder.dispose();
```

Calls on a builder run in the order they are made, so an un-awaited `setIntent` still lands before the `sign` that follows it.

Other signers are `CallbackSigner`, `KeystoreSigner`, `HardwareSigner`, `RemoteSigner` and `SettingsSigner`. `CawgIdentitySigner` wraps a claim signer and an identity signer:

```dart
final cawg = CawgIdentitySigner(
  claimSigner: signer,
  identitySigner: identitySigner,
  referencedAssertions: ['c2pa.actions'],
);
```

### Contexts

The native SDKs no longer have global settings: a context carries all of the configuration. `C2pa.loadSettings` still works. The plugin keeps those settings and applies them to every reader and builder created without a context.

```dart
final settings = await C2paSettings.create();
await settings.updateFromString(settingsJson, 'json');

final context = await C2paContext.create(
  settings: settings,
  signer: signer,                            // used when sign() gets no signer
  onProgress: (p) => print('${p.phase.name} ${p.step}/${p.total}'),
  httpResolver: const NativeHttpResolver(),  // or CallbackHttpResolver(...)
);

final builder = await c2pa.createBuilderFromContext(context, manifestJson);
final result = await builder.sign(sourceData: bytes, mimeType: 'image/jpeg');

// From anywhere, while an operation runs. The operation throws
// C2paCancelledException.
await context.cancel();

await builder.dispose();
await context.dispose();
```

Builders, settings and contexts hold native resources. Dispose them when you are done; any that are garbage collected undisposed are released then.

### Embeddable manifests

To embed the manifest yourself, use a builder whose context has a signer:

```dart
final placeholder = await builder.placeholder('image/jpeg');
// ... write the asset with the placeholder at `offset` ...
await builder.setDataHashExclusions([
  DataHashExclusion(start: offset, length: placeholder.length),
]);
await builder.updateHashFromBytes('image/jpeg', assetWithPlaceholder);
final manifest = await builder.signEmbeddable('image/jpeg'); // same size as the placeholder
```

`hashType()` tells you which workflow a format uses. `setFixedSizeMerkle()` and `hashMdatBytes()` handle fragmented BMFF. `C2pa.composeManifest()` frames raw `application/c2pa` bytes for a format.

### Errors

Every failure is a `C2paException`, a sealed class whose cases you can match:

```dart
try {
  final store = await c2pa.readManifestFromFile(path);
  print(store.validationStatus); // trusted, valid, invalid or unknown
} on C2paManifestNotFoundException {
  // No content credentials.
} on C2paUnsupportedException catch (e) {
  // Not available on this platform: e.code is NOT_IMPLEMENTED_IOS, ...
} on C2paException catch (e) {
  print('${e.code}: ${e.message}');
}
```

## Platform differences

| Capability | Android | iOS |
|---|---|---|
| `readFragment` (fragmented BMFF reading) | yes | `NOT_IMPLEMENTED_IOS`; c2pa-swift has no fragment reader |
| `readBytesWithManifest` / `readFileWithManifest` with a context | context ignored; c2pa-android has no context-aware form | yes |
| `writeIngredientArchive` | needs `builder.generate_c2pa_archive: true` in settings | yes |
| `createSelfSignedCertificateChain` | `NOT_IMPLEMENTED_ANDROID` | yes |
| `importKey` | EC and RSA, into AndroidKeyStore | EC P-256/384/521, into the keychain |
| `createKey` | es256/es384/es512 software keys; hardware (StrongBox) es256 | es256/es384/es512 keychain keys; hardware (Secure Enclave) es256, devices only |
| Digital source types `empty`, `trainedAlgorithmicData`, `computationalCapture` | via the SDK enum | recorded through an explicit `c2pa.created` action, since the c2pa-swift enum lacks them |

`getSupportedReadMimeTypes()` and `getSupportedSignMimeTypes()` return the lists reported by each native SDK.

## Example

See the [example](example/) directory for a sample app with camera capture, signing and verification.

## License

Dual-licensed under Apache-2.0 and MIT. See [LICENSE-APACHE](LICENSE-APACHE) and [LICENSE-MIT](LICENSE-MIT).

## About C2PA

The [Coalition for Content Provenance and Authenticity (C2PA)](https://c2pa.org/) develops technical specifications for certifying the source and history of media content. C2PA manifests provide a tamper-evident way to attach provenance information to digital content.

## Credits

Developed by [Guardian Project](https://guardianproject.info/).
