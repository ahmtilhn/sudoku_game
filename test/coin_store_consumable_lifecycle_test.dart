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
    expect(source, isNot(contains('_purchaseAccountBlocker')));
    expect(source, isNot(contains('connectPlayGamesAccount()')));
    expect(
      source,
      contains('if (Platform.isAndroid) await _recoverAndroidConsumables();'),
    );
    expect(source, contains('started = await _startCoinPurchase(details);'));
    expect(
      source,
      contains('final recoveredStart = await _startCoinPurchase(details);'),
    );
    expect(source, contains('isAppleStorePlatform'));
    expect(source, contains('Platform.isIOS || Platform.isMacOS'));
    expect(source, contains('isStoreKit2PurchaseMode'));
    expect(source, contains('autoConsume: isAppleStorePlatform'));
    expect(source, contains('_recoverAndroidConsumables()'));
    expect(source, contains('queryPastPurchases()'));
    expect(source, contains('_consumeAndroidCoinPurchase(purchase)'));
    expect(source, contains('BillingResponse.ok'));
    expect(source, contains('BillingResponse.itemNotOwned'));
    expect(source, contains("exception.code == 'purchase_replayed'"));
    expect(source, contains('!snapshot.androidConsumptionHandledByServer'));
    expect(source, contains('throw _CoinConsumptionException'));
    expect(source, contains('Intentionally do not complete the purchase.'));
    expect(
      source,
      contains('Coin Store Apple purchase is pending server verification'),
    );
    expect(
      source,
      contains(
        'Do not complete the App Store transaction or surface this as a',
      ),
    );
  });

  test(
    'iOS recovers unfinished StoreKit 2 purchases without touching Android',
    () {
      final source = File(
        'lib/services/coin_store_service.dart',
      ).readAsStringSync();

      expect(
        source,
        contains(
          "package:in_app_purchase_storekit/in_app_purchase_storekit.dart",
        ),
      );
      expect(source, contains('if (isAppleStorePlatform && available)'));
      expect(
        source,
        contains(
          'if (isAppleStorePlatform) await _recoverAppleUnfinishedTransactions();',
        ),
      );
      expect(source, contains('if (!isStoreKit2PurchaseMode) return;'));
      expect(source, contains('const Duration(seconds: 4)'));
      expect(source, contains('_recoverIosUnfinishedTransactions()'));
      expect(source, contains('SK2Transaction'));
      expect(source, contains('unfinishedTransactions()'));
      expect(source, contains('SK2PurchaseDetails'));
      expect(source, contains('_purchaseDetailsFromStoreKit2Transaction'));
      expect(source, contains('App Store unfinished purchase recovery failed'));
    },
  );

  test('iOS keeps StoreKit receipt verification data off transaction id', () {
    final source = File(
      'lib/services/coin_store_service.dart',
    ).readAsStringSync();

    expect(source, contains('_verificationDataForServer(purchase)'));
    expect(source, contains('_transactionIdForServer('));
    expect(source, contains('_looksLikeCompactJws(serverData)'));
    expect(source, contains('!isAppleStorePlatform'));
    expect(source, contains('StoreKit 1 exposes the app receipt'));
    expect(source, contains('return purchaseId;'));
    expect(source, contains(r"'receipt:${purchase.productID}:$timestamp:'"));
    expect(source, contains('_stableVerificationHash(verificationData)'));
    expect(
      source,
      isNot(
        contains(
          r'${purchase.productID}:${purchase.transactionDate ?? DateTime.now().millisecondsSinceEpoch}:$verificationData',
        ),
      ),
    );
  });

  test(
    'Apple payment sheet uses StoreKit 1 before InAppPurchase is created',
    () {
      final source = File('lib/main.dart').readAsStringSync();

      expect(source, contains('_configureApplePurchaseQueue()'));
      expect(
        source.indexOf('await _configureApplePurchaseQueue();'),
        lessThan(source.indexOf('CoinStoreService.instance.initialize')),
      );
      expect(
        source,
        contains('InAppPurchaseStoreKitPlatform.enableStoreKit1()'),
      );
      expect(source, contains('defaultTargetPlatform == TargetPlatform.iOS'));
      expect(source, contains('defaultTargetPlatform == TargetPlatform.macOS'));
    },
  );

  test('no-ads remains a non-consumable entitlement', () {
    final source = File(
      'lib/services/coin_store_service.dart',
    ).readAsStringSync();

    expect(source, contains("androidNoAdsProductId = 'no_ads'"));
    expect(source, contains("iosNoAdsProductId = 'sudoku_duel_no_ads'"));
    expect(source, contains('buyNonConsumable(String productId)'));
    expect(source, contains('_store.buyNonConsumable('));
  });

  test('macOS bundle id stays aligned with App Store verification', () {
    final macosConfig = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    final workerConfig = File(
      'backend/social_worker/wrangler.production.toml',
    ).readAsStringSync();

    expect(
      macosConfig,
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.devovia.sudokuduel'),
    );
    expect(
      workerConfig,
      contains('APPLE_BUNDLE_ID = "com.devovia.sudokuduel"'),
    );
    expect(macosConfig, isNot(contains('com.example.sudokuGame')));
  });

  test('coin store screen routes coin packs through consumable buy flow', () {
    final source = File(
      'lib/features/economy/coin_store_screen.dart',
    ).readAsStringSync();

    expect(source, contains('onBuy: () => _store.buy(product.id)'));
    expect(source, contains('onBuy: () => _store.buyNonConsumable('));
    expect(source, contains('CoinStoreService.noAdsProductId'));
  });
}
