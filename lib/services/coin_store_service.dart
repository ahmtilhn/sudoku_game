import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'economy_api_client.dart';
import 'economy_service.dart';
import 'firebase_session_service.dart';

class CoinStoreService extends ChangeNotifier {
  CoinStoreService._();

  static final CoinStoreService instance = CoinStoreService._();

  static const Set<String> productIds = <String>{
    'coins_100',
    'coins_500',
    'coins_1000',
    'coins_5000',
    'coins_10000',
    'coins_50000',
    'coins_100000',
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
        ..sort((a, b) => coinAmount(a.id).compareTo(coinAmount(b.id)));
      if (response.error != null) {
        error = response.error!.message;
      } else if (products.isEmpty) {
        error = 'Coin products are not configured in this store yet.';
      } else if (response.notFoundIDs.isNotEmpty) {
        error = 'Some Coin products are not available in this test store.';
      }
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
    if (pendingProductId != null) return false;
    if (!FirebaseSessionService.isProtected) {
      error =
          'Protect or sign in to your player account before buying Coins. Paid Coins cannot be attached to an unrecoverable guest account.';
      notifyListeners();
      return false;
    }
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
      final started = await _store.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: details),
        // StoreKit requires auto-consumption for consumables. Google Play stays
        // manual so the token is consumed after the backend verifies/grants it.
        autoConsume: Platform.isIOS,
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

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (!productIds.contains(purchase.productID)) continue;
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
        try {
          if (!FirebaseSessionService.isProtected) {
            throw const EconomyApiException(
              409,
              'Sign in to the protected player account that made this purchase.',
              code: 'account_protection_required',
            );
          }
          final verificationData =
              purchase.verificationData.serverVerificationData;
          final fallbackTransaction =
              '${purchase.productID}:${purchase.transactionDate ?? DateTime.now().millisecondsSinceEpoch}:$verificationData';
          final transactionId = purchase.purchaseID?.trim().isNotEmpty == true
              ? purchase.purchaseID!.trim()
              : fallbackTransaction;
          final snapshot = await EconomyApiClient.instance.verifyPurchase(
            platform: Platform.isIOS ? 'ios' : 'android',
            productId: purchase.productID,
            transactionId: transactionId,
            verificationData: verificationData,
          );

          if (Platform.isAndroid) {
            try {
              final androidAddition = _store
                  .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
              await androidAddition.consumePurchase(purchase);
            } catch (consumeError) {
              // Production may already have consumed this token server-side.
              // Verification/grant is idempotent, so a duplicate consume error
              // must not hide the wallet update from the player.
              debugPrint(
                'Android consumable already handled or delayed: $consumeError',
              );
            }
          }
          if (purchase.pendingCompletePurchase) {
            await _store.completePurchase(purchase);
          }

          await EconomyService.instance.applyPurchaseWallet(snapshot);
          error = null;
        } on EconomyApiException catch (exception) {
          error = exception.message;
          EconomyService.instance.reportError(exception.message);
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

  Future<void> disposeService() async {
    await _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    _initialized = false;
  }
}
