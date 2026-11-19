// Parcel weight class shown before a rider accepts (SRDS §2.4.3, PR 03)
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_rider/features/rider/models/rider_models.dart';
import 'package:vendra_rider/features/rider/widgets/parcel_profile_chip.dart';

RiderOrder _task(int grams, {bool complete = true}) => RiderOrder.fromJson({
      'id': 1,
      'status': 'ready_for_pickup',
      'itemCount': 2,
      'parcelWeightGrams': grams,
      'parcelWeightComplete': complete,
    });

void main() {
  test('weight classes: < 3 kg standard, 3 – 8 kg medium, > 8 kg heavy', () {
    expect(_task(1200).parcelClass, ParcelClass.standard);
    expect(_task(3000).parcelClass, ParcelClass.medium);
    expect(_task(8000).parcelClass, ParcelClass.medium);
    expect(_task(20000).parcelClass, ParcelClass.heavy);
  });

  test('missing weights never pass as a standard parcel', () {
    expect(_task(0, complete: false).parcelClass, ParcelClass.unknown);
    expect(_task(1200, complete: false).parcelClass, ParcelClass.unknown);
    // Listed weights alone already exceed a class boundary: that is a safe lower bound
    expect(_task(9000, complete: false).parcelClass, ParcelClass.heavy);
  });

  test('kg formatting', () {
    expect(formatKg(1200), '1.2 kg');
    expect(formatKg(20000), '20 kg');
  });
}
