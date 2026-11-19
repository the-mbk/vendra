// Personal numbers are shown masked; only the call button uses the full number.
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_rider/vendra_core.dart';

void main() {
  test('keeps the network prefix and the last three digits', () {
    expect(maskPhone('0312-4445566'), '0312-***566');
    expect(maskPhone('+92 312 4445566'), '9231-***566');
  });

  test('short numbers are hidden completely, empty ones give nothing', () {
    expect(maskPhone('12345'), '***');
    expect(maskPhone(''), isNull);
    expect(maskPhone(null), isNull);
  });
}
