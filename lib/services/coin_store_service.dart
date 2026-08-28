import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  static const Set<String> _permanentAppleVerificationCodes = <String>{
    'bundle_mismatch',
    'product_mismatch',
    'transaction_mismatch',
    'purchase_revoked',
    'purchase_not_owned',
    'product_type_mismatch',
    'unknown_product',
  };

  final InAppPurchase _store = InAppPurchase.instance;
  final Map<String, String> _applePendingVerificationTransactions =
      <String, String>{};
  final Set<String> _finishedAppleTransactionKeys = <String>{};
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Future<void> _purchaseHandlingQueue = Future<void>.value();

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
      (purchases) => unawaited(_enqueuePurchases(purchases)),
      onError: (Object purchaseError, StackTrace stackTrace) {
        debugPrint('Coin Store purchase stream failed: $purchaseError');
        debugPrintStack(stackTrace: stackTrace);
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

    // StoreKit 2 is the default Apple purchase API. Recover unfinished
    // transactions after subscribing to purchaseStream so a purchase that was
    // charged before an app restart can be verified, credited and finished.
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
        error = 'Some Coin products are not available in this store.';
      }
      debugPrint(
        'Coin Store products refreshed: platform=$_purchasePlatformForLog '
        'available=$available found=${products.map((p) => p.id).join(',')} '
        'missing=${response.notFoundIDs.join(',')}',
      );
    } catch (loadError, stackTrace) {
      debugPrint('Coin Store product refresh failed: $loadError');
      debugPrintStack(stackTrace: stackTrace);
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

    _beginPurchaseAttempt(productId);
    try {
      if (Platform.isAndroid) await _recoverAndroidConsumables();

      if (isAppleStorePlatform) {
        final recovered = await _recoverAppleUnfinishedTransactions(
          onlyProductId: productId,
        );
        if (recovered.contains(productId)) {
          _finishPurchaseAttempt();
          // The existing App Store transaction was handled by recovery. Never
          // start a second charge from the same tap.
          return error == null &&
              !_hasPendingApplePurchaseForProduct(productId);
        }
      }

      debugPrint(
        'Coin Store starting purchase: platform=$_purchasePlatformForLog '
        'productId=$productId',
      );
      var started = await _startCoinPurchase(details);
      if (!started && Platform.isAndroid) {
        await _recoverAndroidConsumables();
        started = await _startCoinPurchase(details);
      }
      if (!started) {
        _finishPurchaseAttempt();
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
        } catch (retryError, retryStackTrace) {
          debugPrint('Google Play purchase retry failed: $retryError');
          debugPrintStack(stackTrace: retryStackTrace);
        }
      }

      if (isAppleStorePlatform) {
        // StoreKit 2 deliberately rejects a duplicate product when an unfinished
        // transaction exists. Recover that transaction instead of blindly
        // issuing a second payment request.
        final recovered = await _recoverAppleUnfinishedTransactions(
          onlyProductId: productId,
        );
        if (recovered.contains(productId)) {
          _finishPurchaseAttempt();
          return error == null &&
              !_hasPendingApplePurchaseForProduct(productId);
        }
      }

      _finishPurchaseAttempt();
      error = _purchaseStartMessage(startError);
      EconomyService.instance.reportError(error!);
      notifyListeners();
      return false;
    }
  }

  Future<Set<String>> _recoverAppleUnfinishedTransactions({
    String? onlyProductId,
  }) async {
    if (!isAppleStorePlatform || !isStoreKit2PurchaseMode) {
      return const <String>{};
    }

    try {
      final transactions =
          await storekit2.SK2Transaction.unfinishedTransactions().timeout(
            const Duration(seconds: 4),
          );
      final relevant = transactions
          .where((transaction) => productIds.contains(transaction.productId))
          .where(
            (transaction) =>
                onlyProductId == null || transaction.productId == onlyProductId,
          )
          .where((transaction) => transaction.id.trim().isNotEmpty)
          .toList(growable: false);
      if (relevant.isEmpty) return const <String>{};

      final recoveredProductIds = relevant
          .map((transaction) => transaction.productId)
          .toSet();
      debugPrint(
        'Recovering ${relevant.length} unfinished StoreKit 2 purchase(s): '
        '${recoveredProductIds.join(',')}',
      );
      await _enqueuePurchases(
        relevant
            .map(_purchaseDetailsFromStoreKit2Transaction)
            .toList(growable: false),
      );
      return recoveredProductIds;
    } on TimeoutException {
      debugPrint(
        'App Store unfinished purchase recovery timed out; '
        'StoreKit duplicate protection remains active.',
      );
      return const <String>{};
    } catch (recoveryError, stackTrace) {
      // Recovery is best-effort. StoreKit 2 also refuses duplicate purchases
      // natively, so a failed recovery query can never cause a second charge for
      // an already-unfinished product.
      debugPrint(
        'App Store unfinished purchase recovery failed: $recoveryError',
      );
      debugPrintStack(stackTrace: stackTrace);
      return const <String>{};
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
        // receiptData is StoreKit 2's signed JWS transaction. If an older
        // runtime fails to expose it, the backend can securely resolve the
        // transaction from the App Store Server API using purchaseID.
        serverVerificationData: transaction.receiptData ?? transaction.id,
        source: storekit.kIAPSource,
      ),
      transactionDate: transaction.purchaseDate,
      status: PurchaseStatus.purchased,
      appAccountToken: transaction.appAccountToken,
    );
  }

  Future<bool> _startCoinPurchase(ProductDetails details) {
    return _store.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: details),
      // Apple consumables are completed through StoreKit after secure backend
      // verification. Android stays manual so its token can be consumed only
      // after the backend grant succeeds.
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

    _beginPurchaseAttempt(productId);
    try {
      if (isAppleStorePlatform) {
        final recovered = await _recoverAppleUnfinishedTransactions(
          onlyProductId: productId,
        );
        if (recovered.contains(productId)) {
          _finishPurchaseAttempt();
          return error == null &&
              !_hasPendingApplePurchaseForProduct(productId);
        }
      }

      final started = await _store.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: details),
      );
      if (!started) _finishPurchaseAttempt();
      return started;
    } catch (startError, stackTrace) {
      debugPrint(
        'Coin Store entitlement purchase start failed: '
        'platform=$_purchasePlatformForLog productId=$productId '
        'error=$startError',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (isAppleStorePlatform) {
        final recovered = await _recoverAppleUnfinishedTransactions(
          onlyProductId: productId,
        );
        if (recovered.contains(productId)) {
          _finishPurchaseAttempt();
          return error == null &&
              !_hasPendingApplePurchaseForProduct(productId);
        }
      }

      _finishPurchaseAttempt();
      error = _purchaseStartMessage(startError);
      EconomyService.instance.reportError(error!);
      notifyListeners();
      return false;
    }
  }

  Future<void> restorePurchases() async {
    try {
      error = null;
      await _store.restorePurchases();
    } catch (restoreError, stackTrace) {
      debugPrint('Purchase restore failed: $restoreError');
      debugPrintStack(stackTrace: stackTrace);
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
      await _enqueuePurchases(pendingConsumables);
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

  Future<void> _enqueuePurchases(List<PurchaseDetails> purchases) async {
    if (purchases.isEmpty) return;

    final previous = _purchaseHandlingQueue;
    final gate = Completer<void>();
    _purchaseHandlingQueue = gate.future;
    try {
      await previous;
      await _handlePurchases(purchases);
    } catch (queueError, stackTrace) {
      debugPrint('Coin Store purchase handling failed: $queueError');
      debugPrintStack(stackTrace: stackTrace);
      error ??= 'The purchase is waiting to be processed.';
      EconomyService.instance.setPurchaseProcessing(false);
      notifyListeners();
    } finally {
      if (!gate.isCompleted) gate.complete();
    }
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

      if (isAppleStorePlatform &&
          _finishedAppleTransactionKeys.contains(
            _appleTransactionKey(purchase),
          )) {
        debugPrint(
          'Skipping already-finished App Store transaction: '
          'productId=${purchase.productID} purchaseId=${purchase.purchaseID}',
        );
        continue;
      }

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
          final completed = await _completePurchaseSafely(purchase);
          if (isAppleStorePlatform && completed) {
            _markAppleTransactionFinished(purchase);
          }
        }
        notifyListeners();
        continue;
      }

      if (purchase.status == PurchaseStatus.canceled) {
        pendingProductId = null;
        EconomyService.instance.setPurchaseProcessing(false);
        if (purchase.pendingCompletePurchase) {
          final completed = await _completePurchaseSafely(purchase);
          if (isAppleStorePlatform && completed) {
            _markAppleTransactionFinished(purchase);
          }
        }
        notifyListeners();
        continue;
      }

      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }

      pendingProductId = purchase.productID;
      EconomyService.instance.setPurchaseProcessing(true);
      if (isAppleStorePlatform) {
        _markAppleVerificationPending(purchase);
      }
      notifyListeners();

      try {
        final verificationData = _verificationDataForServer(purchase);
        final transactionId = _transactionIdForServer(
          purchase,
          verificationData,
        );
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

        if (isAppleStorePlatform) {
          // Apple recommends delivering verified content before finishing the
          // transaction. The backend grant is idempotent, so if finish fails the
          // same transaction can safely be recovered without double-crediting.
          await EconomyService.instance.applyPurchaseWallet(snapshot);
          if (purchase.pendingCompletePurchase) {
            final completed = await _completePurchaseSafely(purchase);
            if (!completed) {
              throw const _AppleCompletionException();
            }
          }
          _markAppleTransactionFinished(purchase);
        } else {
          if (purchase.pendingCompletePurchase) {
            await _store.completePurchase(purchase);
          }
          await EconomyService.instance.applyPurchaseWallet(snapshot);
        }
        error = null;
      } on _CoinConsumptionException catch (exception) {
        error = exception.message;
        EconomyService.instance.reportError(exception.message);
        debugPrint(exception.message);
        // Intentionally do not complete the purchase. The owned token remains
        // discoverable by queryPastPurchases and will be retried on next start.
      } on _AppleCompletionException {
        _markAppleVerificationPending(purchase);
        error =
            'Your purchase was credited, but App Store finalization is still '
            'pending. It will be retried automatically.';
        debugPrint(
          'Coin Store Apple transaction was granted but could not be finished: '
          'productId=${purchase.productID} purchaseId=${purchase.purchaseID}',
        );
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

        if (isAppleStorePlatform) {
          await _handleAppleVerificationFailure(purchase, exception);
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
      } catch (verificationError, stackTrace) {
        if (isAppleStorePlatform) {
          _markAppleVerificationPending(purchase);
          error = _applePendingVerificationMessage();
          debugPrint(
            'Coin Store Apple purchase verification is pending: '
            '$verificationError',
          );
          debugPrintStack(stackTrace: stackTrace);
          continue;
        }
        error = 'The purchase is pending server verification.';
        EconomyService.instance.reportError(error!);
      } finally {
        pendingProductId = null;
        EconomyService.instance.setPurchaseProcessing(false);
        notifyListeners();
      }
    }
  }

  Future<void> _handleAppleVerificationFailure(
    PurchaseDetails purchase,
    EconomyApiException exception,
  ) async {
    final code = exception.code;
    debugPrint(
      'Coin Store Apple server verification failed: '
      'status=${exception.statusCode} code=$code message=${exception.message}',
    );

    if (code == 'purchase_replayed') {
      final completed =
          !purchase.pendingCompletePurchase ||
          await _completePurchaseSafely(purchase);
      if (completed) {
        _markAppleTransactionFinished(purchase);
      } else {
        _markAppleVerificationPending(purchase);
      }
      error = completed
          ? 'This App Store purchase was already credited to another player account.'
          : 'This App Store purchase was already used and is waiting for App Store finalization.';
      EconomyService.instance.reportError(error!);
      return;
    }

    if (_isPermanentAppleVerificationFailure(exception)) {
      final completed =
          !purchase.pendingCompletePurchase ||
          await _completePurchaseSafely(purchase);
      if (completed) {
        _markAppleTransactionFinished(purchase);
      } else {
        _markAppleVerificationPending(purchase);
      }
      error = completed
          ? exception.message
          : '${exception.message} App Store finalization will be retried.';
      EconomyService.instance.reportError(error!);
      return;
    }

    // Network/auth/server configuration failures must never lose a charged
    // purchase. Leave it unfinished so StoreKit 2 redelivers the transaction,
    // and block a second charge for the same product by recovering it first.
    _markAppleVerificationPending(purchase);
    error = _applePendingVerificationMessage();
  }

  bool _isPermanentAppleVerificationFailure(EconomyApiException exception) {
    return exception.code != null &&
        _permanentAppleVerificationCodes.contains(exception.code);
  }

  bool _hasPendingApplePurchaseForProduct(String productId) {
    return _applePendingVerificationTransactions.values.contains(productId);
  }

  String _appleTransactionKey(PurchaseDetails purchase) {
    final purchaseId = purchase.purchaseID?.trim();
    if (purchaseId != null && purchaseId.isNotEmpty) return purchaseId;
    final verificationData = purchase.verificationData.serverVerificationData
        .trim();
    return '${purchase.productID}:${purchase.transactionDate ?? 'unknown'}:'
        '${_stableVerificationHash(verificationData)}';
  }

  void _markAppleVerificationPending(PurchaseDetails purchase) {
    _applePendingVerificationTransactions[_appleTransactionKey(purchase)] =
        purchase.productID;
  }

  void _markAppleTransactionFinished(PurchaseDetails purchase) {
    final key = _appleTransactionKey(purchase);
    _applePendingVerificationTransactions.remove(key);
    _finishedAppleTransactionKeys.add(key);
  }

  Future<bool> _completePurchaseSafely(PurchaseDetails purchase) async {
    try {
      await _store.completePurchase(purchase);
      return true;
    } catch (completionError, stackTrace) {
      debugPrint(
        'Coin Store completePurchase failed: platform=$_purchasePlatformForLog '
        'productId=${purchase.productID} purchaseId=${purchase.purchaseID} '
        'error=$completionError',
      );
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  void _beginPurchaseAttempt(String productId) {
    pendingProductId = productId;
    error = null;
    EconomyService.instance.setPurchaseProcessing(true);
    notifyListeners();
  }

  void _finishPurchaseAttempt() {
    pendingProductId = null;
    EconomyService.instance.setPurchaseProcessing(false);
    notifyListeners();
  }

  String _purchaseStartMessage(Object startError) {
    if (isAppleStorePlatform && startError is PlatformException) {
      if (startError.code == 'storekit_duplicate_product_object') {
        return 'A previous App Store purchase for this package is still being '
            'verified. No new charge was started.';
      }
      final detail = startError.message?.trim();
      if (detail != null && detail.isNotEmpty) {
        return 'The App Store purchase could not be started. $detail';
      }
      return 'The App Store purchase could not be started. Please try again.';
    }
    return 'The purchase could not be started.';
  }

  String _applePendingVerificationMessage() {
    return 'A previous App Store purchase is waiting for secure verification. '
        'No new charge was started.';
  }

  int coinAmount(String productId) {
    return int.tryParse(productId.replaceFirst('coins_', '')) ?? 0;
  }

  String _verificationDataForServer(PurchaseDetails purchase) {
    final serverData = purchase.verificationData.serverVerificationData.trim();
    if (!isAppleStorePlatform) return serverData;

    // StoreKit 2 supplies a signed JWS transaction as serverVerificationData.
    // Send it unchanged. If StoreKit cannot expose the JWS, send purchaseID as
    // a non-secret lookup hint; the backend still verifies the transaction
    // independently with Apple's App Store Server API before granting anything.
    if (serverData.isNotEmpty) return serverData;
    return purchase.purchaseID?.trim() ?? '';
  }

  String _transactionIdForServer(
    PurchaseDetails purchase,
    String verificationData,
  ) {
    final purchaseId = purchase.purchaseID?.trim();
    if (purchaseId != null && purchaseId.isNotEmpty) return purchaseId;

    final timestamp =
        purchase.transactionDate ??
        DateTime.now().millisecondsSinceEpoch.toString();
    if (isAppleStorePlatform) {
      return 'storekit:${purchase.productID}:$timestamp:'
          '${_stableVerificationHash(verificationData)}';
    }
    return '${purchase.productID}:$timestamp:${_stableVerificationHash(verificationData)}';
  }

  String _stableVerificationHash(String value) {
    var hash = 0xcbf29ce484222325;
    for (var index = 0; index < value.length; index++) {
      hash ^= value.codeUnitAt(index);
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
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
    _applePendingVerificationTransactions.clear();
    _finishedAppleTransactionKeys.clear();
    _purchaseHandlingQueue = Future<void>.value();
    _initialized = false;
  }
}

class _CoinConsumptionException implements Exception {
  const _CoinConsumptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _AppleCompletionException implements Exception {
  const _AppleCompletionException();
}
