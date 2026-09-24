import 'package:flutter_test/flutter_test.dart';
import 'package:api_client/api.dart';

void main() {
  test('sözleşme tipi kullanılabilir', () {
    final h = HealthResponse(status: 'healthy', version: '1.0.0', state: 1);
    expect(h.status, 'healthy');
  });
}
