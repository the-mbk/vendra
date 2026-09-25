// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Home (Stitch "vendra_rider_home_mobile")
// Online/offline toggle, today's earnings, incoming delivery requests.
// Bottom tabs: Home · Earnings · Profile
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../../../config/app_routes.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_state.dart';
import '../bloc/earnings_bloc.dart';
import '../bloc/rider_home_bloc.dart';
import '../models/rider_models.dart';
import '../widgets/location_settings_sheet.dart';
import '../widgets/task_card.dart';
import 'earnings_screen.dart';
import 'profile_tab.dart';

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  int _tab = 0;
  bool _deliveryOpen = false;
  int _handledMessageId = 0;
  int _handledDeliveryNonce = 0;

  Future<void> _openDelivery(int orderId) async {
    if (_deliveryOpen) return;
    _deliveryOpen = true;
    await Navigator.pushNamed(context, AppRoutes.activeDelivery, arguments: orderId);
    _deliveryOpen = false;
    if (!mounted) return;
    context.read<RiderHomeBloc>().add(const RiderHomeRefreshed());
    context.read<EarningsBloc>().add(const EarningsRequested());
  }

  void _selectTab(int i) {
    setState(() => _tab = i);
    if (i == 1) context.read<EarningsBloc>().add(const EarningsRequested());
  }

  void _onNotificationOrder(BuildContext notificationsContext, int orderId) {
    Navigator.of(notificationsContext).pop();
    if (orderId == context.read<RiderHomeBloc>().state.activeOrderId) {
      _openDelivery(orderId);
    } else {
      _selectTab(1);
    }
  }

  void _onHomeState(BuildContext context, RiderHomeState state) {
    final m = state.message;
    if (m != null && m.id != _handledMessageId) {
      _handledMessageId = m.id;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(m.text),
          backgroundColor: m.isError ? AppColors.error : AppColors.success,
          behavior: SnackBarBehavior.floating,
        ));
    }
    if (state.openDeliveryId != null && state.openDeliveryNonce != _handledDeliveryNonce) {
      _handledDeliveryNonce = state.openDeliveryNonce;
      _openDelivery(state.openDeliveryId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<RiderHomeBloc, RiderHomeState>(
          listenWhen: (a, b) => a.message?.id != b.message?.id || a.openDeliveryNonce != b.openDeliveryNonce,
          listener: _onHomeState,
        ),
      ],
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: IndexedStack(
          index: _tab,
          children: [
            _HomeTab(
              onOpenDelivery: _openDelivery,
              onShowEarnings: () => _selectTab(1),
              onOpenOrder: _onNotificationOrder,
            ),
            const EarningsScreen(),
            const ProfileTab(),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _tab,
          onTap: _selectTab,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textSecondary,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_wallet_outlined),
                activeIcon: Icon(Icons.account_balance_wallet),
                label: 'Earnings'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

// ── Home tab ─────────────────────────────────────────────────

class _HomeTab extends StatelessWidget {
  final ValueChanged<int> onOpenDelivery;
  final VoidCallback onShowEarnings;
  final void Function(BuildContext, int) onOpenOrder;

  const _HomeTab({required this.onOpenDelivery, required this.onShowEarnings, required this.onOpenOrder});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RiderHomeBloc, RiderHomeState>(
      builder: (context, state) {
        return Column(
          children: [
            _Header(state: state, onOpenOrder: onOpenOrder),
            const LocationStatusBanner(),
            Expanded(
              child: state.loading
                  ? const LoadingShimmer(isGrid: false, itemCount: 3)
                  : RefreshIndicator(
                      onRefresh: () {
                        final done = Completer<void>();
                        context.read<RiderHomeBloc>().add(RiderHomeRefreshed(done: done));
                        return done.future;
                      },
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: [
                          if (state.loadError != null)
                            _InfoCard(
                              icon: Icons.cloud_off,
                              color: AppColors.error,
                              title: 'Could not load',
                              body: state.loadError!,
                              actionLabel: 'Retry',
                              onAction: () => context.read<RiderHomeBloc>().add(RiderHomeStarted()),
                            ),
                          _EarningsCard(earnings: state.earnings, onDetails: onShowEarnings),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: Text('Delivery requests',
                                    style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700)),
                              ),
                              if (state.radiusKm != null)
                                Text('within ${state.radiusKm!.toStringAsFixed(0)} km',
                                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ..._taskSection(context, state),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _taskSection(BuildContext context, RiderHomeState state) {
    final bloc = context.read<RiderHomeBloc>();
    if (state.activeOrderId != null || state.reason == 'busy') {
      return [
        _InfoCard(
          icon: Icons.delivery_dining,
          color: AppColors.primary,
          title: 'Delivery in progress${state.activeOrderId != null ? ' · #${state.activeOrderId}' : ''}',
          body: 'Finish your current delivery to receive new requests.',
          actionLabel: 'Open delivery',
          onAction: state.activeOrderId != null ? () => onOpenDelivery(state.activeOrderId!) : null,
        ),
      ];
    }
    if (!state.isOnline || state.reason == 'offline') {
      return [
        _InfoCard(
          icon: Icons.power_settings_new,
          color: AppColors.textSecondary,
          title: 'You are offline',
          body: 'Go online to receive delivery requests from stores near you.',
          actionLabel: 'Go online',
          onAction: state.togglingStatus ? null : () => bloc.add(const RiderOnlineToggled(true)),
        ),
      ];
    }
    if (state.reason == 'no_location') {
      return [
        _InfoCard(
          icon: Icons.location_searching,
          color: AppColors.reservedAmber,
          title: 'Waiting for your location',
          body: 'Nearby requests appear once your location reaches the server. '
              'Check GPS, or turn on "Simulate location".',
          actionLabel: 'Location settings',
          onAction: () => showLocationSettings(context),
        ),
      ];
    }
    final tasks = state.tasks;
    if (tasks.isEmpty) {
      return [
        const _InfoCard(
          icon: Icons.radar,
          color: AppColors.secondary,
          title: 'No requests right now',
          body: 'New requests from nearby stores show up here automatically. Pull down to refresh.',
        ),
      ];
    }
    return [
      for (final t in tasks)
        TaskCard(
          key: ValueKey(t.id),
          task: t,
          accepting: state.acceptingId == t.id,
          disabled: state.acceptingId != null && state.acceptingId != t.id,
          onAccept: () => bloc.add(RiderTaskAccepted(t.id)),
          onDecline: () => bloc.add(RiderTaskDeclined(t.id)),
        ),
    ];
  }
}

class _Header extends StatelessWidget {
  final RiderHomeState state;
  final void Function(BuildContext, int) onOpenOrder;
  const _Header({required this.state, required this.onOpenOrder});

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final user = auth is Authenticated ? auth.user : null;
    final name = user?.fullName ?? 'Rider';
    final first = name.split(' ').first;
    final initials = name.trim().isEmpty
        ? 'R'
        : name.trim().split(RegExp(r'\s+')).take(2).map((p) => p[0].toUpperCase()).join();

    return Container(
      color: AppColors.secondary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.white24,
                    child: Text(initials,
                        style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$_greeting, $first',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                        Row(
                          children: [
                            const Icon(Icons.two_wheeler, size: 14, color: Colors.white70),
                            const SizedBox(width: 4),
                            Text(vehicleLabel(state.vehicleType ?? user?.vehicleType),
                                style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Location settings',
                    onPressed: () => showLocationSettings(context),
                    icon: const Icon(Icons.my_location, color: Colors.white),
                  ),
                  NotificationBell(color: Colors.white, onOpenOrder: onOpenOrder),
                ],
              ),
              const SizedBox(height: 14),
              _OnlineToggle(
                online: state.isOnline,
                busy: state.togglingStatus,
                onChanged: (v) => context.read<RiderHomeBloc>().add(RiderOnlineToggled(v)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnlineToggle extends StatelessWidget {
  final bool online;
  final bool busy;
  final ValueChanged<bool> onChanged;
  const _OnlineToggle({required this.online, required this.busy, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget segment(bool value, String label) {
      final selected = online == value;
      final color = value ? AppColors.success : AppColors.textSecondary;
      return Expanded(
        child: GestureDetector(
          onTap: busy || selected ? null : () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy && !selected)
                  const SizedBox(
                      width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                else
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: selected ? color : Colors.white54, shape: BoxShape.circle),
                  ),
                const SizedBox(width: 8),
                Text(label,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, color: selected ? AppColors.textPrimary : Colors.white70)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(28)),
      child: Row(children: [segment(true, 'Online'), segment(false, 'Offline')]),
    );
  }
}

class _EarningsCard extends StatelessWidget {
  final RiderEarnings? earnings;
  final VoidCallback onDetails;
  const _EarningsCard({required this.earnings, required this.onDetails});

  @override
  Widget build(BuildContext context) {
    final e = earnings ?? const RiderEarnings();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Today's Earnings", style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                    Text(rs(e.today),
                        style: GoogleFonts.poppins(fontSize: 30, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ],
                ),
              ),
              TextButton(
                onPressed: onDetails,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Details', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.primary)),
                    const Icon(Icons.chevron_right, color: AppColors.primary, size: 18),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _Stat(icon: Icons.two_wheeler, value: '${e.todayCount}', label: 'Deliveries today')),
              const SizedBox(width: 12),
              Expanded(child: _Stat(icon: Icons.date_range, value: rs(e.week), label: 'This week')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _Stat({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
                Text(label, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _InfoCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600))),
            ],
          ),
          const SizedBox(height: 6),
          Text(body, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            VendraButton(text: actionLabel!, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}
