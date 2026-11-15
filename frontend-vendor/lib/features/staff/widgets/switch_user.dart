// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - "Switch user" on the shop's device (SRDS §1.3)
//   showSwitchUser(context)  roster (GET /api/vendor/staff/roster) → pick a
//                            person → PIN pad → staff token
//   backToOwner(context)     the owner's password → a normal vendor login
// Either way the new token becomes the session (AuthBloc SessionSwitched,
// which re-reads /api/auth/me) and the dashboard is rebuilt for the new
// person's permissions. The owner's email is remembered on the device, so
// coming back only asks for the password.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';
import '../../auth/screens/post_sign_in.dart';
import '../models/staff_member.dart';
import '../permissions.dart';
import '../services/owner_email_store.dart';
import '../services/staff_api.dart';
import 'pin_pad_dialog.dart';

/// Who was picked on the switch-user sheet (null member = the store owner)
class _SwitchTarget {
  final StaffMember? member;
  const _SwitchTarget(this.member);
}

/// Opens the roster, asks for the chosen person's PIN (or the owner's
/// password) and switches the session
Future<void> showSwitchUser(BuildContext context) async {
  final auth = context.read<AuthBloc>().state;
  if (auth is! Authenticated) return;

  final target = await showModalBottomSheet<_SwitchTarget>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _SwitchUserSheet(current: auth.user),
  );
  if (target == null || !context.mounted) return;

  final String? token;
  if (target.member == null) {
    token = await _askOwnerPassword(context, auth.user);
  } else {
    token = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PinPadDialog(member: target.member!),
    );
  }
  if (token == null || !context.mounted) return;
  await _applySession(context, token);
}

/// "Back to owner": the owner's password, then the owner's session again
Future<void> backToOwner(BuildContext context) async {
  final auth = context.read<AuthBloc>().state;
  if (auth is! Authenticated) return;
  final token = await _askOwnerPassword(context, auth.user);
  if (token == null || !context.mounted) return;
  await _applySession(context, token);
}

Future<String?> _askOwnerPassword(BuildContext context, UserModel user) async {
  // A staff session's /me carries the owner's account, so its email is a safe fallback
  final email = await OwnerEmailStore.read() ?? user.email;
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _OwnerPasswordDialog(email: email),
  );
}

/// Stores the token as the session, then reopens the dashboard for the new person
Future<void> _applySession(BuildContext context, String token) async {
  final bloc = context.read<AuthBloc>();
  final messenger = ScaffoldMessenger.of(context);
  final done = Completer<String?>();
  bloc.add(SessionSwitched(token: token, done: done));
  final error = await done.future;
  if (!context.mounted) return;

  if (error != null) {
    messenger.showSnackBar(SnackBar(
      content: Text("Couldn't switch user: $error"),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
    ));
    return;
  }
  final state = bloc.state;
  if (state is! Authenticated) return;
  // Rebuilds the dashboard (tabs, data) for the new permissions
  continueAfterSignIn(context, state.user);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('Signed in as ${signedInLabel(state.user)}'),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
}

// ══════════════════════════════════════════════════════════════
// Roster sheet
// ══════════════════════════════════════════════════════════════
class _SwitchUserSheet extends StatefulWidget {
  final UserModel current;
  const _SwitchUserSheet({required this.current});

  @override
  State<_SwitchUserSheet> createState() => _SwitchUserSheetState();
}

class _SwitchUserSheetState extends State<_SwitchUserSheet> {
  late Future<List<StaffMember>> _roster = StaffApi().roster();

  @override
  Widget build(BuildContext context) {
    final current = widget.current;
    final isStaff = current.staff != null;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Switch user', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
                  Text('Who is using this device? Each person signs in with their own PIN.',
                      style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('Now: ${signedInLabel(current)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.secondary)),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            Flexible(
              child: FutureBuilder<List<StaffMember>>(
                future: _roster,
                builder: (context, snap) {
                  final tiles = <Widget>[
                    if (isStaff)
                      _tile(
                        icon: Icons.storefront,
                        color: AppColors.secondary,
                        title: 'Store owner',
                        subtitle: "Back to the owner · needs the owner's password",
                        onTap: () => Navigator.pop(context, const _SwitchTarget(null)),
                      ),
                  ];
                  if (snap.connectionState != ConnectionState.done) {
                    tiles.add(const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ));
                  } else if (snap.hasError) {
                    tiles.add(_message(
                      ApiService.getErrorMessage(snap.error),
                      action: TextButton(
                        onPressed: () => setState(() => _roster = StaffApi().roster()),
                        child: const Text('Try again'),
                      ),
                    ));
                  } else if (snap.data!.isEmpty) {
                    tiles.add(_message(isStaff
                        ? 'No other staff on this store.'
                        : 'No staff yet. Add cashiers, packers and inventory managers under Profile → Shop staff.'));
                  } else {
                    for (final m in snap.data!) {
                      final isMe = m.id == current.staff?.id;
                      tiles.add(_tile(
                        icon: m.roleInfo.icon,
                        color: m.roleInfo.color,
                        title: m.fullName,
                        subtitle: isMe ? '${m.roleInfo.label} · signed in now' : m.roleInfo.label,
                        onTap: isMe ? null : () => Navigator.pop(context, _SwitchTarget(m)),
                      ));
                    }
                  }
                  return ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 12), children: tiles);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      enabled: onTap != null,
      onTap: onTap,
      leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color, size: 20)),
      title: Text(title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
    );
  }

  Widget _message(String text, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          Text(text, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
          if (action != null) action,
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Owner's password (Back to owner)
// ══════════════════════════════════════════════════════════════
class _OwnerPasswordDialog extends StatefulWidget {
  final String email;
  const _OwnerPasswordDialog({required this.email});

  @override
  State<_OwnerPasswordDialog> createState() => _OwnerPasswordDialogState();
}

class _OwnerPasswordDialogState extends State<_OwnerPasswordDialog> {
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_password.text.isEmpty) {
      setState(() => _error = "Enter the owner's password");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await StaffApi().ownerSignIn(widget.email, _password.text);
      if (mounted) Navigator.of(context).pop(token);
    } catch (e) {
      // Wrong password, or LOGIN_RATE_LIMITED after too many tries
      if (mounted) {
        setState(() {
          _busy = false;
          _error = ApiService.getErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: const Icon(Icons.storefront, color: AppColors.secondary, size: 32),
      title: Text('Back to owner', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.email,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscure,
              autofocus: true,
              enabled: !_busy,
              onSubmitted: (_) => _signIn(),
              decoration: InputDecoration(
                labelText: "Owner's password",
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                errorText: _error,
                errorMaxLines: 3,
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _busy ? null : _signIn,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Sign in'),
        ),
      ],
    );
  }
}
