import 'package:flutter_test/flutter_test.dart';
import 'package:api_client/api.dart';

void main() {
  test('sözleşme tipi kullanılabilir', () {
    final h = HealthResponse(status: 'healthy');
    expect(h.status, 'healthy');
  });
}
