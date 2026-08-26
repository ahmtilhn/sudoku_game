import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coin packs remain consumable and preserve Google Play lifecycle', () {
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
    expect(source, contains('_startCoinPurchase(details)'));
    expect(source, contains('_recoverAndroidConsumables()'));
    expect(source, contains('queryPastPurchases()'));
    expect(source, contains('_consumeAndroidCoinPurchase(purchase)'));
    expect(source, contains('BillingResponse.ok'));
    expect(source, contains('BillingResponse.itemNotOwned'));
    expect(source, contains("exception.code == 'purchase_replayed'"));
    expect(source, contains('!snapshot.androidConsumptionHandledByServer'));
    expect(source, contains('throw _CoinConsumptionException'));
  });

  test('iOS stays on StoreKit 2 and never forces the legacy StoreKit 1 path', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final storeSource = File(
      'lib/services/coin_store_service.dart',
    ).readAsStringSync();
    final projectSource = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(mainSource, isNot(contains('enableStoreKit1')));
    expect(mainSource, isNot(contains('_configureApplePurchaseQueue')));
    expect(storeSource, contains('isStoreKit2PurchaseMode'));
    expect(storeSource, contains('SK2Transaction.unfinishedTransactions()'));
    expect(storeSource, contains('SK2PurchaseDetails'));
    expect(storeSource, contains('transaction.receiptData ?? transaction.id'));
    expect(projectSource, contains('IPHONEOS_DEPLOYMENT_TARGET = 15.0;'));
  });

  test('iOS recovers unfinished purchases before allowing another charge', () {
    final source = File(
      'lib/services/coin_store_service.dart',
    ).readAsStringSync();

    expect(source, contains('_recoverAppleUnfinishedTransactions('));
    expect(source, contains('onlyProductId: productId'));
    expect(source, contains('recovered.contains(productId)'));
    expect(source, contains('_applePendingVerificationTransactions'));
    expect(source, contains('_finishedAppleTransactionKeys'));
    expect(source, contains('_appleTransactionKey(purchase)'));
    expect(source, contains('_enqueuePurchases(purchases)'));
    expect(source, contains('storekit_duplicate_product_object'));
    expect(source, contains('No new charge was started.'));
  });

  test('iOS sends StoreKit 2 JWS data unchanged to the production verifier', () {
    final source = File(
      'lib/services/coin_store_service.dart',
    ).readAsStringSync();
    final backend = File(
      'backend/social_worker/src/production_purchase_verification_v2.ts',
    ).readAsStringSync();

    expect(source, contains('_verificationDataForServer(purchase)'));
    expect(source, contains('if (serverData.isNotEmpty) return serverData;'));
    expect(source, contains('_transactionIdForServer('));
    expect(
      source,
      contains(r"return 'storekit:${purchase.productID}:$timestamp:'"),
    );
    expect(source, contains('_stableVerificationHash(verificationData)'));
    expect(backend, contains('tryDecodeUntrustedStoreKitJws(input.verificationData)'));
    expect(backend, contains('inApps/v1/transactions/'));
    expect(backend, contains('verifyAppleStoreKitJws(signedTransactionInfo'));
    expect(backend, contains('expectedBundleId: bundleId'));
    expect(backend, contains("verificationSource: 'app_store_server_api_verified_jws'"));
  });

  test('iOS preserves charged transactions on transient server failures', () {
    final source = File(
      'lib/services/coin_store_service.dart',
    ).readAsStringSync();

    expect(source, contains('_handleAppleVerificationFailure('));
    expect(source, contains('_isPermanentAppleVerificationFailure'));
    expect(source, contains('_permanentAppleVerificationCodes'));
    expect(source, contains('_markAppleVerificationPending(purchase)'));
    expect(source, contains('_completePurchaseSafely(purchase)'));
    expect(source, contains('_AppleCompletionException'));
    expect(
      source,
      contains('Your purchase was credited, but App Store finalization is still'),
    );
    expect(source, contains("code == 'purchase_replayed'"));
  });

  test('no-ads remains a non-consumable entitlement with Apple recovery', () {
    final source = File(
      'lib/services/coin_store_service.dart',
    ).readAsStringSync();

    expect(source, contains("androidNoAdsProductId = 'no_ads'"));
    expect(source, contains("iosNoAdsProductId = 'sudoku_duel_no_ads'"));
    expect(source, contains('buyNonConsumable(String productId)'));
    expect(source, contains('_store.buyNonConsumable('));
    expect(source, contains('onlyProductId: productId'));
  });

  test('Apple bundle ids stay aligned with production verification', () {
    final iosProject = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final macosConfig = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    final workerConfig = File(
      'backend/social_worker/wrangler.production.toml',
    ).readAsStringSync();

    expect(
      iosProject,
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.devovia.sudokuduel;'),
    );
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

  test('coin store screen routes products through the correct purchase APIs', () {
    final source = File(
      'lib/features/economy/coin_store_screen.dart',
    ).readAsStringSync();

    expect(source, contains('onBuy: () => _store.buy(product.id)'));
    expect(source, contains('onBuy: () => _store.buyNonConsumable('));
    expect(source, contains('CoinStoreService.noAdsProductId'));
  });
}
