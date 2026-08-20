import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coin packs remain consumable and recover owned Google Play tokens', () {
    final source = File(
      'lib/services/coin_store_service.dart',
    ).readAsStringSync();

    for (final productId in <String>[
      'coins_100',
      'coins_500',
      'coins_1000',
      'coins_5000',
      'coins_10000',
      'coins_50000',
      'coins_100000',
    ]) {
      expect(source, contains("'$productId'"));
    }

    expect(source, contains('buyConsumable(String productId)'));
    expect(source, contains('autoConsume: Platform.isIOS'));
    expect(source, contains('_recoverAndroidConsumables()'));
    expect(source, contains('queryPastPurchases()'));
    expect(source, contains('_consumeAndroidCoinPurchase(purchase)'));
    expect(source, contains('BillingResponse.ok'));
    expect(source, contains('BillingResponse.itemNotOwned'));
    expect(source, contains('throw _CoinConsumptionException'));
    expect(
      source,
      contains('Intentionally do not complete the purchase.'),
    );
  });

  test('no-ads remains a non-consumable entitlement', () {
    final source = File(
      'lib/services/coin_store_service.dart',
    ).readAsStringSync();

    expect(source, contains("androidNoAdsProductId = 'no_ads'"));
    expect(source, contains("iosNoAdsProductId = 'sudoku_duel_no_ads'"));
    expect(source, contains('buyNonConsumable(String productId)'));
    expect(source, contains('_store.buyNonConsumable('));
  });
}
