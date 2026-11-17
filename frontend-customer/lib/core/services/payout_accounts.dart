// ══════════════════════════════════════════════════════════════
// Vendra App - Payout accounts (payments.payoutsTo == 'payoneer' | 'stripe_account')
// Withdrawals go to the user's own account with the payout provider, set up
// once on the provider's pages:
//   Payoneer  the user signs in to Payoneer (or creates a free account) and
//             links it to Vendra; payouts land in their Payoneer balance in
//             USD, and they withdraw from Payoneer to their bank
//   Stripe    a Stripe Express account; Stripe pays out to their bank
//   GET  /api/payouts/account             where the user stands (PayoutAccountStatus)
//   POST /api/payouts/account/onboarding  → { url } the provider's setup / linking page
//   POST /api/payouts/account/dashboard   → { url } their Payoneer account / Stripe Express dashboard
// The provider sends the user back to a "go back to the app" page; the app
// then re-reads the account (on resume, or when they tap "I've finished").
// ══════════════════════════════════════════════════════════════

import 'package:url_launcher/url_launcher.dart';

import '../../config/api_config.dart';
import '../models/payment_model.dart';
import 'api_service.dart';

class PayoutAccounts {
  const PayoutAccounts();

  /// GET /api/payouts/account
  Future<PayoutAccountStatus> fetch() async {
    final res = await ApiService().get(ApiConfig.payoutAccount);
    return PayoutAccountStatus.fromJson(_data(res.data));
  }

  /// POST /api/payouts/account/onboarding → the provider's setup / linking page (creates the account if needed)
  Future<String> onboardingUrl() async => _url((await ApiService().post(ApiConfig.payoutOnboarding)).data);

  /// POST /api/payouts/account/dashboard → the user's Payoneer account page / Stripe Express dashboard
  Future<String> dashboardUrl() async => _url((await ApiService().post(ApiConfig.payoutDashboard)).data);

  /// POST /api/withdrawals { amount } → sent to the payout account (no card token)
  Future<WithdrawalResult> withdraw(double amount) async =>
      WithdrawalResult.fromJson(_data((await ApiService().post(ApiConfig.withdrawals, data: {'amount': amount})).data));

  /// Opens a payout provider's page in the browser (a new tab on the web). False if it
  /// couldn't be opened — e.g. a popup blocker; show a button that opens [url].
  Future<bool> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (_) {
      return false;
    }
  }

  /// Readable text for a failed call
  static String errorMessage(Object error) =>
      error is FormatException ? error.message : ApiService.getErrorMessage(error);

  static Map<String, dynamic> _data(dynamic body) {
    final data = body is Map ? body['data'] : null;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const FormatException('Unexpected response from the server.');
  }

  static String _url(dynamic body) {
    final url = _data(body)['url']?.toString() ?? '';
    if (url.isEmpty) throw const FormatException('No link came back from the payout provider. Please try again.');
    return url;
  }
}
