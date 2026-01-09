import 'package:flutter_test/flutter_test.dart';
import 'package:c2pa/c2pa.dart';
import 'package:c2pa/c2pa_platform_interface.dart';
import 'package:c2pa/c2pa_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockC2paPlatform
    with MockPlatformInterfaceMixin
    implements C2paPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final C2paPlatform initialPlatform = C2paPlatform.instance;

  test('$MethodChannelC2pa is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelC2pa>());
  });

  test('getPlatformVersion', () async {
    C2pa c2paPlugin = C2pa();
    MockC2paPlatform fakePlatform = MockC2paPlatform();
    C2paPlatform.instance = fakePlatform;

    expect(await c2paPlugin.getPlatformVersion(), '42');
  });
}
