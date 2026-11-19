// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Shop staff (owner only, SRDS §1.3)
// The owner adds cashiers, packers and inventory managers, each with a
// 4–6 digit PIN they use on "Switch user". Edit name / role, reset a PIN
// (also lifts a 5-wrong-PIN lockout), remove (their sessions end at once;
// sales and packing history keep the name) or restore.
//   GET/POST /api/vendor/staff · PUT/DELETE /api/vendor/staff/:id
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../models/staff_member.dart';
import '../services/staff_api.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  final StaffApi _api = StaffApi();
  List<StaffMember> _staff = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _api.list();
      if (mounted) {
        setState(() {
          _staff = list;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      // 403 STAFF_NOT_ALLOWED if a staff session somehow got here
      if (mounted) {
        setState(() {
          _loading = false;
          _error = ApiService.getErrorMessage(e);
        });
      }
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ));
  }

  /// Runs one change, reports it and reloads the list
  Future<void> _run(Future<String> Function() action) async {
    try {
      final message = await action();
      _snack(message);
      await _load(silent: true);
    } catch (e) {
      _snack(ApiService.getErrorMessage(e), error: true);
    }
  }

  Future<void> _openForm([StaffMember? member]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _StaffFormSheet(api: _api, member: member),
    );
    if (saved == true) {
      _snack(member == null ? 'Staff member added.' : 'Staff member updated.');
      _load(silent: true);
    }
  }

  Future<void> _resetPin(StaffMember m) async {
    final pin = await showDialog<String>(context: context, builder: (_) => _NewPinDialog(name: m.fullName));
    if (pin != null) _run(() => _api.update(m.id, pin: pin));
  }

  Future<void> _remove(StaffMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove ${m.fullName}?', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          "They're signed out straight away and can't switch in any more. Their past sales and packing keep their name.",
          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.stockRed, foregroundColor: Colors.white),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) _run(() => _api.remove(m.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Shop staff', style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
      floatingActionButton: _error == null && !_loading
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add staff'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? _errorView()
              : RefreshIndicator(
                  onRefresh: () => _load(silent: true),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      _intro(),
                      const SizedBox(height: 12),
                      if (_staff.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Column(
                            children: [
                              Icon(Icons.groups_outlined, size: 56, color: AppColors.textLight),
                              const SizedBox(height: 8),
                              Text('No staff yet', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                              Text('Tap Add staff to give someone a PIN.',
                                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                      for (final m in _staff) _staffCard(m),
                    ],
                  ),
                ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.poppins(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _intro() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: AppColors.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Staff sign in on this device with "Switch user" and their PIN, and only see what their role needs. '
              'Your wallet, staff and store settings stay owner-only.',
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.secondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _staffCard(StaffMember m) {
    final role = m.roleInfo;
    final muted = !m.isActive;
    final lastSeen = m.lastLoginAt == null
        ? 'Never signed in'
        : 'Last sign-in ${DateFormat('d MMM, h:mm a').format(m.lastLoginAt!)}';
    return Opacity(
      opacity: muted ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
          leading: CircleAvatar(
            backgroundColor: role.color.withValues(alpha: 0.12),
            child: Icon(role.icon, color: role.color, size: 20),
          ),
          title: Text(m.fullName,
              overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${role.label} · ${role.summary}',
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(lastSeen, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight)),
                  if (!m.isActive) _tag('Removed', AppColors.textSecondary),
                  if (m.isActive && m.isLocked) _tag('PIN locked', AppColors.stockRed),
                ],
              ),
            ],
          ),
          onTap: m.isActive ? () => _openForm(m) : null,
          trailing: PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              switch (v) {
                case 'edit':
                  _openForm(m);
                case 'pin':
                  _resetPin(m);
                case 'remove':
                  _remove(m);
                case 'restore':
                  _run(() => _api.update(m.id, isActive: true));
              }
            },
            itemBuilder: (_) => m.isActive
                ? const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'pin', child: Text('Reset PIN')),
                    PopupMenuItem(value: 'remove', child: Text('Remove', style: TextStyle(color: AppColors.stockRed))),
                  ]
                : const [PopupMenuItem(value: 'restore', child: Text('Restore'))],
          ),
        ),
      ),
    );
  }

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
      );
}

/// PIN field: digits only, at most 6
TextField _pinField(TextEditingController ctrl, {required String label, String? error, bool autofocus = false}) =>
    TextField(
      controller: ctrl,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      obscureText: true,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
      decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.pin_outlined, size: 20), errorText: error),
    );

// ══════════════════════════════════════════════════════════════
// Add / edit sheet
// ══════════════════════════════════════════════════════════════
class _StaffFormSheet extends StatefulWidget {
  final StaffApi api;
  final StaffMember? member; // null = add
  const _StaffFormSheet({required this.api, this.member});

  @override
  State<_StaffFormSheet> createState() => _StaffFormSheetState();
}

class _StaffFormSheetState extends State<_StaffFormSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.member?.fullName ?? '');
  final TextEditingController _pin = TextEditingController();
  late String _role = widget.member?.role ?? staffRoles.first.key;
  String? _nameError;
  String? _pinError;
  String? _error;
  bool _saving = false;

  bool get _isEdit => widget.member != null;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    setState(() {
      _nameError = name.length < 2 ? "Enter the staff member's name" : null;
      _pinError = validatePin(_pin.text, required: !_isEdit);
      _error = null;
    });
    if (_nameError != null || _pinError != null) return;

    setState(() => _saving = true);
    try {
      final pin = _pin.text.trim();
      if (_isEdit) {
        final m = widget.member!;
        await widget.api.update(
          m.id,
          fullName: name != m.fullName ? name : null,
          role: _role != m.role ? _role : null,
          pin: pin.isEmpty ? null : pin,
        );
      } else {
        await widget.api.add(fullName: name, role: _role, pin: pin);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // e.g. 409 "A store can have up to 20 active staff."
      if (mounted) {
        setState(() {
          _saving = false;
          _error = ApiService.getErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_isEdit ? 'Edit ${widget.member!.fullName}' : 'Add staff member',
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                  errorText: _nameError,
                ),
              ),
              const SizedBox(height: 14),
              Text('Role', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              for (final r in staffRoles)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _role == r.key ? r.color : AppColors.hairline, width: _role == r.key ? 1.5 : 1),
                  ),
                  child: ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onTap: () => setState(() => _role = r.key),
                    leading: Icon(r.icon, color: r.color),
                    title: Text(r.label, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text(r.summary, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
                    trailing: Icon(
                      _role == r.key ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: _role == r.key ? r.color : AppColors.textLight,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              _pinField(_pin,
                  label: _isEdit ? 'New PIN (leave empty to keep)' : 'PIN (4–6 digits)', error: _pinError),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.error)),
                ),
              const SizedBox(height: 16),
              VendraButton(
                text: _isEdit ? 'Save changes' : 'Add staff member',
                icon: Icons.check,
                isLoading: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for a new 4–6 digit PIN; pops with it (or null)
class _NewPinDialog extends StatefulWidget {
  final String name;
  const _NewPinDialog({required this.name});

  @override
  State<_NewPinDialog> createState() => _NewPinDialogState();
}

class _NewPinDialogState extends State<_NewPinDialog> {
  final _pin = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _confirm() {
    final error = validatePin(_pin.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, _pin.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('New PIN for ${widget.name}', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 17)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pinField(_pin, label: 'PIN (4–6 digits)', error: _error, autofocus: true),
          const SizedBox(height: 8),
          Text('A new PIN also unlocks someone locked out by wrong PINs.',
              style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _confirm, child: const Text('Set PIN')),
      ],
    );
  }
}
