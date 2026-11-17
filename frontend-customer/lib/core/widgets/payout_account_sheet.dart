// ══════════════════════════════════════════════════════════════
// Vendra App - Payout account sheet (payments.payoutsTo == 'payoneer' | 'stripe_account')
// Shown by the withdraw flow until the user's payout account can receive
// withdrawals. The wording follows the account's provider:
//                       Payoneer                              Stripe
//   no account          "Link your Payoneer account"          "Set up payouts with Stripe"
//   setup not finished  "Finish linking on Payoneer"          "Finish setup"
//   details sent        "Payoneer is reviewing your account"  "Stripe is checking your details"
//                       + "Check again"                       + "Check again"
//   ready               → the sheet closes with the status
// The provider's page opens in the browser (a new tab on the web). When the
// app comes back to the foreground, or the user taps "I've finished", the
// account is read again (GET /api/payouts/account).
//
//   final status = await showPayoutAccountSheet(context, status: current);
//   if (status?.isReady == true) ... ask for the amount
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../models/payment_model.dart';
import '../services/app_config.dart';
import '../services/payout_accounts.dart';
import 'card_entry_sheet.dart';
import 'vendra_button.dart';

/// Resolves to the status once the account is ready, or null if dismissed
Future<PayoutAccountStatus?> showPayoutAccountSheet(
  BuildContext context, {
  required PayoutAccountStatus status,
  PayoutAccounts accounts = const PayoutAccounts(),
}) {
  return showModalBottomSheet<PayoutAccountStatus>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => PayoutAccountSheet(status: status, accounts: accounts),
  );
}

class PayoutAccountSheet extends StatefulWidget {
  final PayoutAccountStatus status;
  final PayoutAccounts accounts;

  const PayoutAccountSheet({super.key, required this.status, this.accounts = const PayoutAccounts()});

  @override
  State<PayoutAccountSheet> createState() => _PayoutAccountSheetState();
}

class _PayoutAccountSheetState extends State<PayoutAccountSheet> with WidgetsBindingObserver {
  late PayoutAccountStatus _status = widget.status;

  /// What is running: onboarding | check | open
  String? _busy;
  String? _error;

  /// Set after a check that found the account still not ready
  String? _note;

  /// The provider's page was opened: offer "I've finished" and check on resume
  bool _openedProvider = false;

  /// The browser refused to open the tab (popup blocker): a button opens it
  String? _blockedUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the provider's page (another app or browser tab)
    if (state == AppLifecycleState.resumed && _openedProvider && _busy == null) _check(quiet: true);
  }

  Future<void> _check({bool quiet = false}) async {
    setState(() {
      _busy = 'check';
      _error = null;
      _note = null;
    });
    try {
      final status = await widget.accounts.fetch();
      if (!mounted) return;
      if (status.isReady) {
        Navigator.of(context).pop(status);
        return;
      }
      setState(() {
        _status = status;
        if (!quiet) {
          final checking = status.state == PayoutAccountState.checking;
          _note = status.isPayoneer
              ? checking
                  ? "Payoneer hasn't approved your account yet. Try again a little later."
                  : "Payoneer says your account isn't linked yet."
              : checking
                  ? "Stripe hasn't finished checking yet. Try again in a minute."
                  : "Stripe says the setup isn't finished yet.";
        }
      });
    } catch (e) {
      if (mounted && !quiet) setState(() => _error = PayoutAccounts.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _onboard() async {
    setState(() {
      _busy = 'onboarding';
      _error = null;
      _note = null;
      _blockedUrl = null;
    });
    try {
      final url = await widget.accounts.onboardingUrl();
      final opened = await widget.accounts.openUrl(url);
      if (!mounted) return;
      setState(() {
        _openedProvider = true;
        if (!opened) _blockedUrl = url;
      });
    } catch (e) {
      if (mounted) setState(() => _error = PayoutAccounts.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _openBlocked() async {
    final url = _blockedUrl;
    if (url == null) return;
    final opened = await widget.accounts.openUrl(url);
    if (mounted && opened) setState(() => _blockedUrl = null);
  }

  ({IconData icon, Color color, String title, String text}) get _copy =>
      _status.isPayoneer ? _payoneerCopy : _stripeCopy;

  ({IconData icon, Color color, String title, String text}) get _payoneerCopy {
    switch (_status.state) {
      case PayoutAccountState.none:
        return (
          icon: Icons.account_balance_wallet_outlined,
          color: AppColors.secondary,
          title: 'Link your Payoneer account',
          text: 'Vendra pays your earnings into your Payoneer account, and from Payoneer you can withdraw '
              "them to your bank in Pakistan. Sign in to Payoneer to link your account — if you don't have "
              'one, you can create a free Payoneer account on the same page.',
        );
      case PayoutAccountState.incomplete:
        return (
          icon: Icons.pending_actions_outlined,
          color: AppColors.reservedAmber,
          title: 'Finish linking your Payoneer account',
          text: "Your Payoneer account isn't linked to Vendra yet. Continue on Payoneer's page to sign in "
              'or finish creating your account.',
        );
      case PayoutAccountState.checking:
        return (
          icon: Icons.hourglass_top_rounded,
          color: AppColors.reservedAmber,
          title: 'Payoneer is reviewing your account',
          text: 'You can withdraw as soon as Payoneer approves your account. This can take from a few minutes '
              'to a couple of days; Payoneer emails you if it needs anything else.',
        );
      case PayoutAccountState.ready:
      case PayoutAccountState.notRequired:
        return (
          icon: Icons.check_circle_outline,
          color: AppColors.success,
          title: 'Your Payoneer account is linked',
          text: 'Withdrawals go to your Payoneer balance; from Payoneer you can withdraw them to your bank in Pakistan.',
        );
    }
  }

  ({IconData icon, Color color, String title, String text}) get _stripeCopy {
    switch (_status.state) {
      case PayoutAccountState.none:
        return (
          icon: Icons.account_balance_outlined,
          color: AppColors.secondary,
          title: 'Set up payouts',
          text: 'Withdrawals go to your own Stripe account, and Stripe pays them into your bank. '
              "Set it up once on Stripe's secure pages — it takes a few minutes.",
        );
      case PayoutAccountState.incomplete:
        return (
          icon: Icons.pending_actions_outlined,
          color: AppColors.reservedAmber,
          title: 'Finish your payout setup',
          text: "Your Stripe account isn't finished yet. Continue on Stripe's pages to add the missing details.",
        );
      case PayoutAccountState.checking:
        return (
          icon: Icons.hourglass_top_rounded,
          color: AppColors.reservedAmber,
          title: 'Stripe is checking your details',
          text: 'You can withdraw as soon as Stripe has checked your details. This usually takes a minute or two.',
        );
      case PayoutAccountState.ready:
      case PayoutAccountState.notRequired:
        return (
          icon: Icons.check_circle_outline,
          color: AppColors.success,
          title: 'Your payout account is ready',
          text: 'Withdrawals go to your Stripe account, and Stripe pays them into your bank.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy;
    final state = _status.state;
    final needsSetup = state == PayoutAccountState.none || state == PayoutAccountState.incomplete;
    final busy = _busy != null;
    final name = _status.providerName;

    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 12, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: copy.color.withValues(alpha: 0.12),
                  child: Icon(copy.icon, color: copy.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(copy.title, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(copy.text, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
            if (_status.account != null) ...[
              const SizedBox(height: 6),
              // Payoneer payee ids are short (vendra-12); Stripe's are trimmed
              Text(
                  _status.isPayoneer
                      ? 'Payoneer payee ID ${_status.account!.id}'
                      : 'Stripe account ${_status.account!.shortId}',
                  style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight)),
            ],

            if (_openedProvider && needsSetup) ...[
              const SizedBox(height: 12),
              _InfoBox(
                icon: Icons.open_in_new,
                text: _blockedUrl != null
                    ? "Your browser didn't open $name's page. Tap “Open $name” to continue there."
                    : "$name's page opened in your browser. When you're done there, come back and tap “I've finished”.",
              ),
            ],
            if (_note != null) ...[
              const SizedBox(height: 12),
              _InfoBox(icon: Icons.info_outline, text: _note!),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              CardErrorBox(message: _error!),
            ],
            if (AppConfig.current.features.testCards && needsSetup) ...[
              const SizedBox(height: 12),
              _testModeHint(),
            ],

            const SizedBox(height: 20),
            ..._actions(state, needsSetup, busy, name),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(PayoutAccountState state, bool needsSetup, bool busy, String name) {
    final payoneer = _status.isPayoneer;
    if (_blockedUrl != null) {
      return [
        VendraButton(text: 'Open $name', icon: Icons.open_in_new, onPressed: _openBlocked),
        const SizedBox(height: 8),
        _secondary("I've finished", busy ? null : () => _check()),
      ];
    }
    if (needsSetup && _openedProvider) {
      return [
        VendraButton(text: "I've finished", icon: Icons.refresh, isLoading: _busy == 'check', onPressed: busy ? null : () => _check()),
        const SizedBox(height: 8),
        _secondary('Open $name again', busy ? null : _onboard),
      ];
    }
    switch (state) {
      case PayoutAccountState.none:
        return [
          VendraButton(
            text: payoneer ? 'Link your Payoneer account' : 'Set up payouts with Stripe',
            icon: Icons.open_in_new,
            isLoading: _busy == 'onboarding',
            onPressed: busy ? null : _onboard,
          ),
        ];
      case PayoutAccountState.incomplete:
        return [
          VendraButton(
            text: payoneer ? 'Finish linking on Payoneer' : 'Finish setup',
            icon: Icons.open_in_new,
            isLoading: _busy == 'onboarding',
            onPressed: busy ? null : _onboard,
          ),
          const SizedBox(height: 8),
          _secondary('Check again', busy ? null : () => _check()),
        ];
      case PayoutAccountState.checking:
        return [
          VendraButton(text: 'Check again', icon: Icons.refresh, isLoading: _busy == 'check', onPressed: busy ? null : () => _check()),
          const SizedBox(height: 8),
          // Payoneer: its account page shows what it still needs; Stripe: its setup pages again
          if (payoneer)
            Center(child: PayoutDashboardLink(accounts: widget.accounts, provider: PayoutProvider.payoneer))
          else
            _secondary('Update details on Stripe', busy ? null : _onboard),
        ];
      case PayoutAccountState.ready:
      case PayoutAccountState.notRequired:
        return [
          VendraButton(text: 'Continue', icon: Icons.arrow_forward, onPressed: () => Navigator.of(context).pop(_status)),
        ];
    }
  }

  Widget _secondary(String text, VoidCallback? onPressed) => SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: onPressed,
          child: Text(text, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      );

  /// Development only: how to get through the provider's sandbox pages
  Widget _testModeHint() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, color: Colors.amber.shade800, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _status.isPayoneer
                  ? 'Payoneer sandbox: any password works; use an email containing +fail to see a failed payout.'
                  : "Stripe test mode: on Stripe's pages use the test phone number and the code 000000, "
                      'and pick the test bank account Stripe offers. No real details are needed.',
              style: GoogleFonts.poppins(fontSize: 11, color: Colors.amber.shade900),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoBox({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.secondary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textPrimary))),
        ],
      ),
    );
  }
}

/// "View Payoneer account" — the user's Payoneer account page (balance,
/// payments received from Vendra) — or "View Stripe account" — their Stripe
/// Express dashboard (balance and bank payouts). Shows its own error underneath.
class PayoutDashboardLink extends StatefulWidget {
  final PayoutAccounts accounts;

  /// Whose account page to open (names the link)
  final PayoutProvider provider;

  const PayoutDashboardLink({super.key, this.accounts = const PayoutAccounts(), this.provider = PayoutProvider.stripe});

  @override
  State<PayoutDashboardLink> createState() => _PayoutDashboardLinkState();
}

class _PayoutDashboardLinkState extends State<PayoutDashboardLink> {
  bool _busy = false;
  String? _error;

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = await widget.accounts.dashboardUrl();
      final opened = await widget.accounts.openUrl(url);
      if (!opened && mounted) {
        setState(() => _error = "Couldn't open ${widget.provider.label}. Allow pop-ups for this site and try again.");
      }
    } catch (e) {
      if (mounted) setState(() => _error = PayoutAccounts.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          onPressed: _busy ? null : _open,
          icon: _busy
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.open_in_new, size: 16),
          label: Text('View ${widget.provider.label} account', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        if (_error != null)
          Text(_error!,
              textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.error)),
      ],
    );
  }
}
