// lib/services/billing_service.dart
// Saber+ v1.7.0 — Google Play Billing (Android nativo).
//
// Por qué existe: Colombia NO participa en el programa de billing alternativo
// de Google Play → las compras de productos digitales DENTRO del APK Android
// DEBEN usar Google Play Billing (política de Play Store). La versión WEB
// sigue usando Wompi (upgrade_screen.dart decide con kIsWeb).
//
// Responsabilidades:
//  - Envolver `InAppPurchase.instance` (plugin in_app_purchase 3.2.x) en un
//    singleton con textos de UI en español.
//  - Cargar los 3 productos premium desde Play Console y exponer su precio
//    real con moneda local (ProductDetails.price).
//  - Emitir eventos tipados por `purchaseStream`: la UI verifica cada compra
//    en el backend (verify_play_purchase.php, NUNCA confiar en el cliente)
//    y SIEMPRE llama a completePurchase() después (acknowledge en Android;
//    si no se hace, Google reembolsa a los 3 días).
//
// ⚠️ NOTA TÉCNICA (web): no se importa `dart:io` directamente porque rompe la
// compilación de Flutter Web con dart2js (ver lib/core/io_shim/io_shim.dart,
// la convención del proyecto). La detección de "Android nativo" usa
// `!kIsWeb && defaultTargetPlatform == TargetPlatform.android`, que es
// exactamente equivalente a `!kIsWeb && Platform.isAndroid` y compila en
// todas las plataformas. El guard de kIsWeb va SIEMPRE primero.
//
// Estados de compra (PurchaseStatus 3.x) → evento tipado:
//  - purchased / restored → la UI debe verificar en backend y completar.
//  - error                → mensaje claro al usuario (y completar si aplica).
//  - pending              → informativo (no se completa: Google la confirma
//                           después vía RTDN / nueva entrega del stream).
//  - canceled             → informativo silencioso.

import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/utils/app_logger.dart';

/// IDs de producto configurados en Google Play Console
/// (ver docs/PLAY_BILLING_SETUP.md — deben coincidir EXACTAMENTE).
class BillingProductIds {
  BillingProductIds._();

  /// Suscripción mensual.
  static const String monthly = 'saberplus_premium_monthly';

  /// Suscripción anual.
  static const String annual = 'saberplus_premium_annual';

  /// Producto único no-consumible (vitalicio).
  static const String lifetime = 'saberplus_premium_lifetime';

  /// Todos los IDs consultados a Play en loadProducts().
  static const Set<String> all = {monthly, annual, lifetime};
}

/// Producto de Play listo para la UI: [price] viene formateado por Google
/// con la moneda local del usuario (p. ej. "25.000,00 $"), por eso es String.
class PlayProduct {
  const PlayProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.rawPrice,
    required this.currencyCode,
  });

  final String id;
  final String title;
  final String description;

  /// Precio formateado con moneda local (así lo muestra Play Store).
  final String price;

  /// Precio numérico sin formatear (en la moneda local).
  final double rawPrice;

  /// Código ISO de la moneda (p. ej. COP).
  final String currencyCode;
}

/// Tipos de evento que emite [BillingService.purchaseStream].
enum BillingEventType {
  /// Compra nueva confirmada por Play → verificar en backend y completar.
  purchased,

  /// Compra restaurada (reinstalación / "Restaurar compras") → mismo flujo.
  restored,

  /// Pago pendiente (efectivo/PSE desde Play) → informativo, NO completar.
  pending,

  /// Error durante la compra → mensaje al usuario.
  error,

  /// El usuario cerró la ventana de pago de Play → informativo.
  canceled,
}

/// Evento tipado de compra. [purchaseToken] es el token server-side
/// (verificationData.serverVerificationData en Android) que el backend usa
/// para verificar contra la Google Play Developer API. [orderId] es
/// purchaseID en Android (orderId de la factura de Play).
class BillingEvent {
  const BillingEvent({
    required this.type,
    this.productId,
    this.purchaseToken,
    this.orderId,
    required this.message,
    this.purchase,
  });

  final BillingEventType type;
  final String? productId;
  final String? purchaseToken;
  final String? orderId;
  final String message;
  final PurchaseDetails? purchase;

  bool get needsVerification =>
      type == BillingEventType.purchased || type == BillingEventType.restored;
}

/// Singleton que envuelve el plugin in_app_purchase.
///
/// Uso (pantalla de upgrade):
/// ```dart
/// final billing = BillingService.instance;
/// if (await billing.init()) {
///   await billing.loadProducts();
///   billing.purchaseStream.listen((event) { ... });
///   await billing.buyProduct(BillingProductIds.monthly);
/// }
/// ```
class BillingService {
  BillingService._();

  static final BillingService instance = BillingService._();

  /// true solo en Android nativo (NO web): único entorno donde Play Billing
  /// está disponible en Saber+ (iOS/desktop usan otros canales).
  static bool get isAndroidNativePlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final InAppPurchase _iap = InAppPurchase.instance;

  final Map<String, ProductDetails> _productDetails = {};
  final Map<String, PlayProduct> _products = {};

  /// Eventos comprados/restaurados que llegaron mientras no había UI
  /// escuchando (p. ej. la compra confirma justo después de cerrar la
  /// pantalla). Se re-emiten cuando alguien vuelve a escuchar el stream,
  /// porque Android NO re-entrega compras ya conocidas por el plugin.
  final List<BillingEvent> _unconsumed = [];

  late final StreamController<BillingEvent> _controller =
      StreamController<BillingEvent>.broadcast(onListen: _flushUnconsumed);

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  bool _initialized = false;
  bool _available = false;

  /// true si init() ya corrió con éxito en esta sesión.
  bool get isInitialized => _initialized;

  /// true si Google Play Billing está disponible en este dispositivo.
  bool get isAvailable => _available;

  /// Productos cargados desde Play Console, indexados por productId.
  Map<String, PlayProduct> get products => Map.unmodifiable(_products);

  /// true si ya se cargó al menos un producto real de Play.
  bool get hasProducts => _products.isNotEmpty;

  /// Stream tipado de eventos de compra (broadcast: varias suscripciones OK).
  ///
  /// Tras recibir purchased/restored, la UI DEBE:
  ///   1. llamar a ApiService.verifyPlayPurchase(...),
  ///   2. SIEMPRE llamar a [completePurchase] (aunque el paso 1 falle).
  Stream<BillingEvent> get purchaseStream => _controller.stream;

  /// Inicializa Play Billing. Solo hace algo en Android nativo
  /// (`!kIsWeb && Platform.isAndroid`); en cualquier otra plataforma
  /// retorna false sin tocar el plugin.
  Future<bool> init() async {
    if (!isAndroidNativePlatform) {
      AppLogger.d('BillingService: plataforma sin Play Billing (web/no-Android)');
      return false;
    }
    if (_initialized) return _available;

    try {
      _available = await _iap.isAvailable();
      if (!_available) {
        AppLogger.w('BillingService: Google Play Billing NO disponible');
        return false;
      }

      // Suscribirse UNA sola vez al stream crudo del plugin. Android entrega
      // por aquí: compras nuevas, compras pendientes de acknowledge (reinstall
      // / compra hecha con la pantalla cerrada) y resultados de restore.
      _purchaseSub ??= _iap.purchaseStream.listen(
        _onPurchaseUpdates,
        onError: (Object e) {
          AppLogger.e('BillingService: error en purchaseStream', e);
          _emit(const BillingEvent(
            type: BillingEventType.error,
            message: 'Ocurrió un error inesperado con Google Play. Intenta de nuevo.',
          ));
        },
      );

      _initialized = true;
      AppLogger.i('BillingService: Play Billing inicializado');
      return true;
    } catch (e) {
      AppLogger.e('BillingService: error en init()', e);
      return false;
    }
  }

  /// Consulta a Play los productos de [BillingProductIds.all] y guarda el
  /// mapa productId → [PlayProduct]. Retorna la lista cargada (vacía si
  /// Play aún no los tiene configurados o algo falla).
  Future<List<PlayProduct>> loadProducts() async {
    if (!_initialized) return const <PlayProduct>[];

    try {
      final response = await _iap.queryProductDetails(BillingProductIds.all);

      if (response.error != null) {
        AppLogger.e(
          'BillingService: queryProductDetails error',
          '${response.error!.code}: ${response.error!.message}',
        );
      }
      if (response.notFoundIDs.isNotEmpty) {
        AppLogger.w(
          'BillingService: productos NO encontrados en Play Console: '
          '${response.notFoundIDs.join(', ')}',
        );
      }

      _products.clear();
      _productDetails.clear();
      for (final details in response.productDetails) {
        _productDetails[details.id] = details;
        _products[details.id] = PlayProduct(
          id: details.id,
          title: details.title,
          description: details.description,
          price: details.price,
          rawPrice: details.rawPrice,
          currencyCode: details.currencyCode,
        );
      }

      AppLogger.i('BillingService: ${_products.length} productos cargados de Play');
      return _products.values.toList(growable: false);
    } catch (e) {
      AppLogger.e('BillingService: error cargando productos', e);
      return const <PlayProduct>[];
    }
  }

  /// Lanza el flujo de compra en Google Play.
  ///
  /// `buyNonConsumable` sirve en Android tanto para suscripciones como para
  /// productos únicos no-consumibles (lifetime). El resultado de la compra
  /// NO llega aquí: llega por [purchaseStream].
  ///
  /// Lanza [StateError] si el servicio no está listo o el producto no existe,
  /// y [Exception] con mensaje en español si Play no aceptó lanzar el flujo
  /// (p. ej. otra compra en curso).
  Future<void> buyProduct(String productId) async {
    if (!_initialized) {
      throw StateError('Play Billing no está inicializado en este dispositivo.');
    }
    final details = _productDetails[productId];
    if (details == null) {
      throw StateError(
        'El producto "$productId" no está disponible en Google Play '
        '(revisa la configuración en Play Console).',
      );
    }

    final PurchaseParam purchaseParam = PurchaseParam(productDetails: details);
    final bool launched =
        await _iap.buyNonConsumable(purchaseParam: purchaseParam);

    if (!launched) {
      // Suele pasar si ya hay una compra en curso; el usuario reintenta.
      throw Exception(
        'No se pudo iniciar la compra en Google Play. '
        'Espera unos segundos e inténtalo de nuevo.',
      );
    }
    AppLogger.i('BillingService: flujo de compra lanzado para $productId');
  }

  /// Restaura compras anteriores (reinstalaciones / nuevo dispositivo).
  /// Las compras restauradas llegan por [purchaseStream] con estado restored.
  Future<void> restorePurchases() async {
    if (!_initialized) {
      throw StateError('Play Billing no está inicializado en este dispositivo.');
    }
    AppLogger.i('BillingService: restaurando compras anteriores...');
    await _iap.restorePurchases();
  }

  /// Confirma (acknowledge) una compra ante Google.
  ///
  /// ⚠️ DEBE llamarse SIEMPRE después de intentar la verificación en el
  /// backend (incluso si la verificación falló por red): si no se confirma
  /// dentro de 3 días, Google reembolsa automáticamente. La verificación
  /// puede reintentarse luego con "Restaurar compras".
  ///
  /// No hace nada si la compra no está pendiente de confirmación.
  Future<void> completePurchase(PurchaseDetails purchase) async {
    try {
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
        AppLogger.i(
          'BillingService: compra ${purchase.productID} confirmada (acknowledge)',
        );
      }
    } catch (e) {
      AppLogger.e('BillingService: error al confirmar la compra', e);
    }
  }

  /// Limpieza total del listener y del controller (tests / cierre de app).
  /// La UI NO debe llamar esto al cerrar la pantalla — solo cancelar su
  /// propia suscripción a [purchaseStream]; el servicio es singleton y vive
  /// toda la sesión.
  Future<void> dispose() async {
    await _purchaseSub?.cancel();
    _purchaseSub = null;
    _initialized = false;
    await _controller.close();
  }

  // ─────────────────────────────────────────────
  // Interno
  // ─────────────────────────────────────────────

  void _onPurchaseUpdates(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      _handlePurchase(purchase);
    }
  }

  Future<void> _handlePurchase(PurchaseDetails purchase) async {
    final String token = purchase.verificationData.serverVerificationData;

    switch (purchase.status) {
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        if (token.isEmpty) {
          AppLogger.e(
            'BillingService: compra sin purchaseToken (${purchase.productID})',
          );
          await _completeIfPending(purchase);
          return;
        }
        _emit(BillingEvent(
          type: purchase.status == PurchaseStatus.purchased
              ? BillingEventType.purchased
              : BillingEventType.restored,
          productId: purchase.productID,
          purchaseToken: token,
          // En Android, purchaseID ES el orderId de la factura de Play.
          orderId: purchase.purchaseID,
          message: purchase.status == PurchaseStatus.purchased
              ? 'Compra realizada. Verificando con el servidor...'
              : 'Compra restaurada. Verificando con el servidor...',
          purchase: purchase,
        ));
        break;

      case PurchaseStatus.pending:
        // NO completar: Google confirma el pago después (efectivo/PSE) y
        // volverá a entregar la compra con estado purchased.
        _emit(BillingEvent(
          type: BillingEventType.pending,
          productId: purchase.productID,
          message: 'Tu pago está pendiente de confirmación por Google Play. '
              'Tu cuenta Premium se activará automáticamente al confirmarse.',
        ));
        break;

      case PurchaseStatus.error:
        _emit(BillingEvent(
          type: BillingEventType.error,
          productId: purchase.productID,
          message: 'La compra no se completó: '
              '${purchase.error?.message ?? "error desconocido de Google Play"}. '
              'No se realizó ningún cobro.',
        ));
        await _completeIfPending(purchase);
        break;

      case PurchaseStatus.canceled:
        _emit(const BillingEvent(
          type: BillingEventType.canceled,
          message: 'Compra cancelada.',
        ));
        await _completeIfPending(purchase);
        break;
    }
  }

  Future<void> _completeIfPending(PurchaseDetails purchase) async {
    try {
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    } catch (e) {
      AppLogger.e('BillingService: error al limpiar compra fallida', e);
    }
  }

  void _emit(BillingEvent event) {
    if (_controller.isClosed) return;
    if (_controller.hasListener) {
      _controller.add(event);
    } else if (event.needsVerification) {
      // Nadie escucha (pantalla cerrada): guardar para re-emitir cuando la
      // UI vuelva a suscribirse.
      _unconsumed.add(event);
      AppLogger.w(
        'BillingService: evento ${event.type.name} sin listener; '
        'quedó en cola (${_unconsumed.length})',
      );
    }
  }

  void _flushUnconsumed() {
    if (_unconsumed.isEmpty) return;
    final pending = List<BillingEvent>.of(_unconsumed);
    _unconsumed.clear();
    for (final event in pending) {
      if (_controller.hasListener) {
        _controller.add(event);
      } else {
        _unconsumed.add(event);
      }
    }
  }
}
