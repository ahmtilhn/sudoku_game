import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart'
    as storekit;
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart'
    as storekit2;

import 'economy_api_client.dart';
import 'economy_service.dart';

class CoinStoreService extends ChangeNotifier {
  CoinStoreService._();

  static final CoinStoreService instance = CoinStoreService._();

  static const String androidNoAdsProductId = 'no_ads';
  static const String iosNoAdsProductId = 'sudoku_duel_no_ads';

  static bool get isAppleStorePlatform => Platform.isIOS || Platform.isMacOS;
  static bool get isStoreKit2PurchaseMode =>
      isAppleStorePlatform &&
      storekit.InAppPurchaseStoreKitPlatform.isStoreKit2Enabled;

  static String get noAdsProductId =>
      isAppleStorePlatform ? iosNoAdsProductId : androidNoAdsProductId;

  static const Set<String> coinProductIds = <String>{
    'coins_100',
    'coins_500',
    'coins_1000',
    'coins_5000',
    'coins_10000',
    'coins_50000',
    'coins_100000',
  };
  static Set<String> get entitlementProductIds => <String>{noAdsProductId};
  static Set<String> get productIds => <String>{
    ...coinProductIds,
    ...entitlementProductIds,
  };

  static const Set<BillingResponse> _retryableConsumeResponses =
      <BillingResponse>{
        BillingResponse.serviceTimeout,
        BillingResponse.serviceDisconnected,
        BillingResponse.serviceUnavailable,
        BillingResponse.networkError,
        BillingResponse.error,
      };

  final InAppPurchase _store = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  List<ProductDetails> products = const <ProductDetails>[];
  bool available = false;
  bool loading = false;
  String? error;
  String? pendingProductId;
  bool _initialized = false;

  ProductDetails? product(String id) {
    for (final item in products) {
      if (item.id == id) return item;
    }
    return null;
  }

  ProductDetails? get noAdsProduct => product(noAdsProductId);
  List<ProductDetails> get coinProducts => products
      .where((product) => coinProductIds.contains(product.id))
      .toList(growable: false);

  Future<void> initialize() async {
    if (_initialized) {
      if (products.isEmpty) await refreshProducts();
      return;
    }
    _initialized = true;
    _purchaseSubscription = _store.purchaseStream.listen(
      (purchases) => unawaited(_handlePurchases(purchases)),
      onError: (Object purchaseError) {
        error = 'The store purchase connection failed.';
        pendingProductId = null;
        EconomyService.instance.setPurchaseProcessing(false);
        notifyListeners();
      },
    );
    await refreshProducts();

    // Google Play keeps an unconsumed consumable as owned. Recover those tokens
    // on startup so an interrupted/failed consume cannot permanently block the
    // same Coin package from being purchased again. The backend grant is
    // idempotent, so replaying an already verified token is safe.
    if (Platform.isAndroid && available) {
      await _recoverAndroidConsumables();
    }
    if (isAppleStorePlatform && available) {
      await _recoverAppleUnfinishedTransactions();
    }
  }

  Future<void> refreshProducts() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      available = await _store.isAvailable();
      if (!available) {
        products = const <ProductDetails>[];
        error = 'The Coin Store is not available on this device.';
        return;
      }
      final response = await _store.queryProductDetails(productIds);
      products = response.productDetails.toList(growable: false)
        ..sort((a, b) {
          if (a.id == noAdsProductId) return -1;
          if (b.id == noAdsProductId) return 1;
          return coinAmount(a.id).compareTo(coinAmount(b.id));
        });
      if (response.error != null) {
        error = response.error!.message;
      } else if (products.isEmpty) {
        error = 'Coin products are not configured in this store yet.';
      } else if (response.notFoundIDs.isNotEmpty) {
        error = 'Some Coin products are not available in this test store.';
      }
      debugPrint(
        'Coin Store products refreshed: platform=$_purchasePlatformForLog '
        'available=$available found=${products.map((p) => p.id).join(',')} '
        'missing=${response.notFoundIDs.join(',')}',
      );
    } catch (_) {
      available = false;
      products = const <ProductDetails>[];
      error = 'The Coin Store could not be loaded.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> buy(String productId) async {
    return buyConsumable(productId);
  }

  Future<bool> buyConsumable(String productId) async {
    if (pendingProductId != null) return false;
    if (!coinProductIds.contains(productId)) return false;
    final details = product(productId);
    if (details == null) {
      error = 'This Coin package is not available.';
      notifyListeners();
      return false;
    }
    pendingProductId = productId;
    error = null;
    EconomyService.instance.setPurchaseProcessing(true);
    notifyListeners();
    try {
      if (Platform.isAndroid) await _recoverAndroidConsumables();
      if (isAppleStorePlatform) await _recoverAppleUnfinishedTransactions();
      debugPrint(
        'Coin Store starting purchase: platform=$_purchasePlatformForLog '
        'productId=$productId',
      );
      var started = await _startCoinPurchase(details);
      if (!started && Platform.isAndroid) {
        await _recoverAndroidConsumables();
        started = await _startCoinPurchase(details);
      }
      if (!started && isAppleStorePlatform) {
        await _recoverAppleUnfinishedTransactions();
        started = await _startCoinPurchase(details);
      }
      if (!started) {
        pendingProductId = null;
        EconomyService.instance.setPurchaseProcessing(false);
        notifyListeners();
      }
      return started;
    } catch (startError, stackTrace) {
      debugPrint(
        'Coin Store purchase start failed: platform=$_purchasePlatformForLog '
        'productId=$productId error=$startError',
      );
      debugPrintStack(stackTrace: stackTrace);
      if (Platform.isAndroid) {
        try {
          await _recoverAndroidConsumables();
          final recoveredStart = await _startCoinPurchase(details);
          if (recoveredStart) return true;
        } catch (_) {
          // Fall through to the user-facing purchase-start error below.
        }
      }
      if (isAppleStorePlatform) {
        try {
          await _recoverAppleUnfinishedTransactions();
          final recoveredStart = await _startCoinPurchase(details);
          if (recoveredStart) return true;
        } catch (_) {
          // Fall through to the user-facing purchase-start error below.
        }
      }
      pendingProductId = null;
      error = 'The purchase could not be started.';
      EconomyService.instance.setPurchaseProcessing(false);
      notifyListeners();
      return false;
    }
  }

  Future<void> _recoverIosUnfinishedTransactions() async {
    try {
      final transactions =
          await storekit2.SK2Transaction.unfinishedTransactions();
      final pendingPurchases = transactions
          .where((transaction) => productIds.contains(transaction.productId))
          .where((transaction) => transaction.id.trim().isNotEmpty)
          .map(_purchaseDetailsFromStoreKit2Transaction)
          .toList(growable: false);
      if (pendingPurchases.isEmpty) return;

      debugPrint(
        'Recovering ${pendingPurchases.length} unfinished App Store purchase(s).',
      );
      await _handlePurchases(pendingPurchases);
    } catch (recoveryError) {
      // Recovery is best-effort. StoreKit can still redeliver the same
      // transaction through purchaseStream while the app is running.
      debugPrint(
        'App Store unfinished purchase recovery failed: $recoveryError',
      );
    }
  }

  PurchaseDetails _purchaseDetailsFromStoreKit2Transaction(
    storekit2.SK2Transaction transaction,
  ) {
    return storekit.SK2PurchaseDetails(
      productID: transaction.productId,
      purchaseID: transaction.id,
      verificationData: PurchaseVerificationData(
        localVerificationData: transaction.jsonRepresentation ?? '',
        serverVerificationData: transaction.receiptData ?? transaction.id,
        source: storekit.kIAPSource,
      ),
      transactionDate: transaction.purchaseDate,
      status: PurchaseStatus.purchased,
      appAccountToken: transaction.appAccountToken,
    );
  }

  Future<void> _recoverAppleUnfinishedTransactions() async {
    if (!isStoreKit2PurchaseMode) return;
    try {
      await _recoverIosUnfinishedTransactions().timeout(
        const Duration(seconds: 4),
      );
    } on TimeoutException {
      debugPrint(
        'App Store unfinished purchase recovery timed out; continuing purchase.',
      );
    }
  }

  Future<bool> _startCoinPurchase(ProductDetails details) {
    return _store.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: details),
      // Apple consumables must auto-consume. Android stays manual: the token is
      // first verified/granted by the backend, then explicitly consumed below.
      autoConsume: isAppleStorePlatform,
    );
  }

  Future<bool> buyNonConsumable(String productId) async {
    if (pendingProductId != null) return false;
    if (!entitlementProductIds.contains(productId)) return false;
    final details = product(productId);
    if (details == null) {
      error = 'This entitlement is not available.';
      notifyListeners();
      return false;
    }
    pendingProductId = productId;
    error = null;
    EconomyService.instance.setPurchaseProcessing(true);
    notifyListeners();
    try {
      final started = await _store.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: details),
      );
      if (!started) {
        pendingProductId = null;
        EconomyService.instance.setPurchaseProcessing(false);
        notifyListeners();
      }
      return started;
    } catch (_) {
      pendingProductId = null;
      error = 'The purchase could not be started.';
      EconomyService.instance.setPurchaseProcessing(false);
      notifyListeners();
      return false;
    }
  }

  Future<void> restorePurchases() async {
    try {
      await _store.restorePurchases();
    } catch (_) {
      error = 'Purchases could not be restored.';
      notifyListeners();
    }
  }

  Future<void> _recoverAndroidConsumables() async {
    try {
      final androidAddition = _store
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final response = await androidAddition.queryPastPurchases();
      if (response.error != null) {
        debugPrint(
          'Google Play consumable recovery query failed: ${response.error}',
        );
        return;
      }

      final pendingConsumables = response.pastPurchases
          .where((purchase) => coinProductIds.contains(purchase.productID))
          .toList(growable: false);
      if (pendingConsumables.isEmpty) return;

      debugPrint(
        'Recovering ${pendingConsumables.length} unconsumed Google Play purchase(s).',
      );
      await _handlePurchases(pendingConsumables);
    } catch (recoveryError) {
      // Recovery is best-effort and must never make the whole store unavailable.
      // The normal purchase stream can still redeliver the same token later.
      debugPrint('Google Play consumable recovery failed: $recoveryError');
    }
  }

  Future<void> _consumeAndroidCoinPurchase(PurchaseDetails purchase) async {
    final androidAddition = _store
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();

    Object? lastThrownError;
    BillingResultWrapper? lastResult;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final result = await androidAddition.consumePurchase(purchase);
        lastResult = result;

        // itemNotOwned is also a success for our verified token: production may
        // have consumed it server-side before the client fallback runs.
        if (result.responseCode == BillingResponse.ok ||
            result.responseCode == BillingResponse.itemNotOwned) {
          return;
        }

        if (!_retryableConsumeResponses.contains(result.responseCode) ||
            attempt == 2) {
          break;
        }
      } catch (consumeError) {
        if (_looksAlreadyConsumed(consumeError)) return;
        lastThrownError = consumeError;
        if (attempt == 2) break;
      }

      await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
    }

    final details = lastResult == null
        ? lastThrownError?.toString() ?? 'unknown Google Play error'
        : '${lastResult.responseCode.name}: '
              '${lastResult.debugMessage ?? 'no debug message'}';
    throw _CoinConsumptionException(
      'Coin purchase was verified but Google Play could not consume it. '
      'The purchase will be retried automatically. ($details)',
    );
  }

  bool _looksAlreadyConsumed(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('itemnotowned') ||
        message.contains('item not owned') ||
        message.contains('already consumed') ||
        message.contains('already been consumed');
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (!productIds.contains(purchase.productID)) continue;
      final isNoAds = purchase.productID == noAdsProductId;
      debugPrint(
        'Coin Store purchase update: platform=$_purchasePlatformForLog '
        'productId=${purchase.productID} status=${purchase.status.name} '
        'pendingComplete=${purchase.pendingCompletePurchase} '
        'purchaseIdPresent=${purchase.purchaseID?.trim().isNotEmpty == true}',
      );
      if (purchase.status == PurchaseStatus.pending) {
        pendingProductId = purchase.productID;
        EconomyService.instance.setPurchaseProcessing(true);
        notifyListeners();
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        error = purchase.error?.message ?? 'The purchase failed.';
        pendingProductId = null;
        EconomyService.instance.setPurchaseProcessing(false);
        EconomyService.instance.reportError(error!);
        if (purchase.pendingCompletePurchase) {
          await _store.completePurchase(purchase);
        }
        notifyListeners();
        continue;
      }

      if (purchase.status == PurchaseStatus.canceled) {
        pendingProductId = null;
        EconomyService.instance.setPurchaseProcessing(false);
        if (purchase.pendingCompletePurchase) {
          await _store.completePurchase(purchase);
        }
        notifyListeners();
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        pendingProductId = purchase.productID;
        EconomyService.instance.setPurchaseProcessing(true);
        notifyListeners();

        try {
          final verificationData = _verificationDataForServer(purchase);
          final fallbackTransaction =
              '${purchase.productID}:${purchase.transactionDate ?? DateTime.now().millisecondsSinceEpoch}:$verificationData';
          final transactionId = purchase.purchaseID?.trim().isNotEmpty == true
              ? purchase.purchaseID!.trim()
              : fallbackTransaction;
          debugPrint(
            'Coin Store verifying purchase: platform=$_purchasePlatformForLog '
            'productId=${purchase.productID} '
            'transactionIdPresent=${transactionId.trim().isNotEmpty} '
            'verification=${_verificationDataKind(verificationData)}',
          );
          final snapshot = await EconomyApiClient.instance.verifyPurchase(
            platform: isAppleStorePlatform ? 'ios' : 'android',
            productId: purchase.productID,
            transactionId: transactionId,
            verificationData: verificationData,
          );

          if (Platform.isAndroid &&
              !isNoAds &&
              !snapshot.androidConsumptionHandledByServer) {
            // Do not swallow consumption failures. A verified Coin token must be
            // consumed before completing the transaction, otherwise Play keeps
            // the product owned and blocks the next purchase of the same pack.
            await _consumeAndroidCoinPurchase(purchase);
          }

          if (purchase.pendingCompletePurchase) {
            await _store.completePurchase(purchase);
          }

          await EconomyService.instance.applyPurchaseWallet(snapshot);
          error = null;
        } on _CoinConsumptionException catch (exception) {
          error = exception.message;
          EconomyService.instance.reportError(exception.message);
          debugPrint(exception.message);
          // Intentionally do not complete the purchase. The owned token remains
          // discoverable by queryPastPurchases and will be retried on next start.
        } on EconomyApiException catch (exception) {
          if (Platform.isAndroid &&
              !isNoAds &&
              exception.code == 'purchase_replayed') {
            await _consumeAndroidCoinPurchase(purchase);
            if (purchase.pendingCompletePurchase) {
              await _store.completePurchase(purchase);
            }
            await EconomyService.instance.refresh(showLoading: false);
            error = null;
            continue;
          }
          error = exception.message;
          EconomyService.instance.reportError(exception.message);
          debugPrint(
            'Coin Store server verification failed: '
            'status=${exception.statusCode} code=${exception.code} '
            'message=${exception.message}',
          );
          // Keep the transaction pending when server verification is unavailable
          // so the SDK can redeliver it after the backend is fixed.
        } catch (_) {
          error = 'The purchase is pending server verification.';
          EconomyService.instance.reportError(error!);
        } finally {
          pendingProductId = null;
          EconomyService.instance.setPurchaseProcessing(false);
          notifyListeners();
        }
      }
    }
  }

  int coinAmount(String productId) {
    return int.tryParse(productId.replaceFirst('coins_', '')) ?? 0;
  }

  String _verificationDataForServer(PurchaseDetails purchase) {
    final serverData = purchase.verificationData.serverVerificationData.trim();
    if (!isAppleStorePlatform || _looksLikeCompactJws(serverData)) {
      return serverData;
    }

    // StoreKit 1 exposes the app receipt instead of a StoreKit 2 transaction
    // JWS. The backend can verify App Store purchases from the transaction ID,
    // so avoid sending a large receipt blob that may exceed request limits.
    final purchaseId = purchase.purchaseID?.trim();
    if (purchaseId != null && purchaseId.isNotEmpty) return purchaseId;
    return serverData;
  }

  String get _purchasePlatformForLog {
    if (Platform.isAndroid) return 'android';
    if (isAppleStorePlatform) {
      return isStoreKit2PurchaseMode ? 'apple_storekit2' : 'apple_storekit1';
    }
    return Platform.operatingSystem;
  }

  String _verificationDataKind(String value) {
    if (_looksLikeCompactJws(value)) return 'compact_jws(${value.length})';
    return 'opaque(${value.length})';
  }

  bool _looksLikeCompactJws(String value) {
    final parts = value.split('.');
    return parts.length == 3 && parts.every((part) => part.isNotEmpty);
  }

  Future<void> disposeService() async {
    await _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    _initialized = false;
  }
}

class _CoinConsumptionException implements Exception {
  const _CoinConsumptionException(this.message);

  final String message;

  @override
  String toString() => message;
}
