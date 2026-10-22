// ══════════════════════════════════════════════════════════════
// Vendra App - Card gateway client (Vendra Pay)
// The app talks to the gateway directly with the publishable key, so card
// numbers never reach the Vendra API — only single-use tokens do:
//   POST /v1/tokens                       tokenize a card → tok_…
//   POST /v1/payment_intents/:id/verify   3-D Secure one-time password
//   GET  /v1/test-cards                   sandbox cards (development only)
// Uses its own Dio client: no JWT, no session-expiry handling.
// Gateway errors are `{ error: { type, code, message } }` (402 for card errors).
// ══════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';

import '../../config/api_config.dart';
import '../models/app_config_model.dart';
import '../models/payment_model.dart';
import 'app_config.dart';

/// A gateway refusal with a message that can be shown as is
class CardGatewayException implements Exception {
  final String message;

  /// Gateway code, e.g. invalid_number, incorrect_otp, card_declined —
  /// or `network` when the gateway couldn't be reached
  final String? code;
  final int? statusCode;

  const CardGatewayException(this.message, {this.code, this.statusCode});

  bool get isIncorrectOtp => code == 'incorrect_otp';

  @override
  String toString() => message;
}

class CardGateway {
  final PaymentSettings settings;
  final Dio _dio;

  CardGateway({PaymentSettings? settings, Dio? dio})
      : settings = settings ?? AppConfig.current.payments,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: {'Content-Type': 'application/json'},
            ));

  /// The gateway URL the device can reach. The backend advertises
  /// `http://localhost:4242`; an emulator (10.0.2.2) or a phone on the LAN
  /// must use the API's host instead, keeping the gateway's scheme and port.
  static String resolveGatewayUrl(String gatewayUrl, [String apiBaseUrl = ApiConfig.baseUrl]) {
    final gateway = Uri.tryParse(gatewayUrl.trim());
    if (gateway == null || gateway.host.isEmpty) return gatewayUrl;
    const loopback = {'localhost', '127.0.0.1', '::1'};
    if (!loopback.contains(gateway.host)) return _trimSlash(gatewayUrl.trim());
    final api = Uri.tryParse(apiBaseUrl);
    if (api == null || api.host.isEmpty || loopback.contains(api.host)) return _trimSlash(gatewayUrl.trim());
    return _trimSlash(gateway.replace(host: api.host).toString());
  }

  static String _trimSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  String get baseUrl => resolveGatewayUrl(settings.gatewayUrl);

  Options get _auth => Options(headers: {'Authorization': 'Bearer ${settings.publishableKey}'});

  void _ensureConfigured() {
    if (!settings.isAvailable) {
      throw const CardGatewayException('Card payments are unavailable right now. Please try again later.',
          code: 'not_configured');
    }
  }

  /// Turns a card into a single-use token (valid 15 minutes)
  Future<CardToken> tokenize({
    required String number,
    required int expMonth,
    required int expYear,
    required String cvc,
  }) async {
    _ensureConfigured();
    try {
      final res = await _dio.post(
        '$baseUrl/v1/tokens',
        data: {'number': number, 'exp_month': expMonth, 'exp_year': expYear, 'cvc': cvc},
        options: _auth,
      );
      return CardToken.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw toException(e);
    }
  }

  /// Sends the one-time password for a payment that came back `requires_action`.
  /// Returns the gateway's new intent status (`succeeded`, or `failed` after the
  /// last wrong attempt). A wrong code with attempts left throws
  /// [CardGatewayException] with code `incorrect_otp`.
  Future<String> verifyOtp(String gatewayIntentId, String otp) async {
    _ensureConfigured();
    try {
      final res = await _dio.post(
        '$baseUrl/v1/payment_intents/${Uri.encodeComponent(gatewayIntentId)}/verify',
        data: {'otp': otp.trim()},
        options: _auth,
      );
      return (res.data is Map ? (res.data as Map)['status'] : null)?.toString() ?? 'processing';
    } catch (e) {
      throw toException(e);
    }
  }

  /// Sandbox cards with their behaviour. Only call when `features.testCards` is on.
  Future<TestCardList> testCards() async {
    if (settings.gatewayUrl.isEmpty) return const TestCardList();
    try {
      final res = await _dio.get('$baseUrl/v1/test-cards');
      return TestCardList.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw toException(e);
    }
  }

  /// Maps any gateway failure to a readable [CardGatewayException]
  static CardGatewayException toException(Object error) {
    if (error is CardGatewayException) return error;
    if (error is DioException) {
      final body = error.response?.data;
      final err = body is Map ? body['error'] : null;
      if (err is Map) {
        final code = err['code']?.toString();
        return CardGatewayException(
          _friendly(code) ?? err['message']?.toString() ?? 'The card was refused.',
          code: code,
          statusCode: error.response?.statusCode,
        );
      }
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return const CardGatewayException('The payment service took too long to respond. Please try again.',
              code: 'network');
        case DioExceptionType.connectionError:
          return const CardGatewayException('Cannot reach the payment service. Check your connection.',
              code: 'network');
        default:
          return CardGatewayException('Payment service error. Please try again.',
              code: 'network', statusCode: error.response?.statusCode);
      }
    }
    return CardGatewayException(error.toString());
  }

  /// Wording for codes whose gateway message is too technical; null keeps the
  /// gateway's own message (it already includes e.g. the attempts left)
  static String? _friendly(String? code) {
    switch (code) {
      case 'test_card_required':
        return 'Only test cards are accepted in this sandbox. Use one of the test cards.';
      case 'invalid_api_key':
        return 'Card payments are misconfigured. Please contact support.';
      case 'resource_missing':
        return 'This payment has expired. Please start again.';
      default:
        return null;
    }
  }
}
