import 'package:flutter_test/flutter_test.dart';
import 'package:cmc_native/main.dart';

void main() {
  test('CMC.CENTER target URL configuration test', () {
    expect(CmcWebViewScreen.initialUrl, 'https://center.cisztermedia-szfvar.hu');
  });
}
