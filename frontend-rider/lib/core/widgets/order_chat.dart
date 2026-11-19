// ══════════════════════════════════════════════════════════════
// Vendra App - Order chat (customer ↔ assigned rider)
// GET/POST /api/orders/:id/messages; new messages arrive live
// ('chat:message'). Neither side needs the other's phone number.
// Writable only while the rider is on the delivery; afterwards the
// thread is read-only. Quick replies cover the usual doorstep notes.
//
//   OrderChatButton(orderId: 12, myRole: 'customer', otherLabel: 'your rider')
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../config/app_theme.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';
import '../services/contact_launcher.dart';
import '../services/realtime_service.dart';
import 'user_avatar.dart';

String _messagesPath(int orderId) => '/api/orders/$orderId/messages';

/// One-tap messages for each side
const Map<String, List<String>> chatQuickReplies = {
  'customer': ['Leave it at the door', 'Please don\'t ring the bell', 'I\'m outside the main gate', 'I\'ll be there in 2 minutes'],
  'rider': ['I\'m at the store', 'On my way to you', 'I\'m outside', 'I can\'t find the address'],
};

/// "Message rider" button with a count of messages that arrived since it was last opened
class OrderChatButton extends StatefulWidget {
  final int orderId;

  /// 'customer' or 'rider': the side this app is on
  final String myRole;

  /// Who the messages go to, e.g. "your rider" / "the customer"
  final String otherLabel;

  const OrderChatButton({super.key, required this.orderId, required this.myRole, required this.otherLabel});

  @override
  State<OrderChatButton> createState() => _OrderChatButtonState();
}

class _OrderChatButtonState extends State<OrderChatButton> {
  StreamSubscription<ChatMessage>? _sub;
  int _unread = 0;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _sub = RealtimeService().chatMessages.listen((m) {
      if (m.orderId == widget.orderId && m.senderRole != widget.myRole && !_open && mounted) {
        setState(() => _unread++);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _openChat() async {
    setState(() { _open = true; _unread = 0; });
    await showOrderChat(context, orderId: widget.orderId, myRole: widget.myRole, otherLabel: widget.otherLabel);
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _openChat,
      icon: Badge(
        isLabelVisible: _unread > 0,
        label: Text('$_unread'),
        child: const Icon(Icons.chat_bubble_outline, size: 20),
      ),
      label: Text('Message ${widget.otherLabel}'),
    );
  }
}

Future<void> showOrderChat(BuildContext context,
    {required int orderId, required String myRole, required String otherLabel}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _OrderChatSheet(orderId: orderId, myRole: myRole, otherLabel: otherLabel),
  );
}

class _OrderChatSheet extends StatefulWidget {
  final int orderId;
  final String myRole;
  final String otherLabel;
  const _OrderChatSheet({required this.orderId, required this.myRole, required this.otherLabel});

  @override
  State<_OrderChatSheet> createState() => _OrderChatSheetState();
}

class _OrderChatSheetState extends State<_OrderChatSheet> {
  static final _time = DateFormat('h:mm a');
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  StreamSubscription<ChatMessage>? _sub;
  bool _loading = true;
  bool _open = false;
  bool _sending = false;
  String? _error;
  ChatCounterpart? _with;

  @override
  void initState() {
    super.initState();
    _sub = RealtimeService().chatMessages.listen((m) {
      if (m.orderId != widget.orderId || _messages.any((x) => x.id == m.id) || !mounted) return;
      setState(() => _messages.add(m));
      _scrollToEnd();
    });
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().get(_messagesPath(widget.orderId));
      final data = Map<String, dynamic>.from(res.data['data'] as Map);
      if (!mounted) return;
      setState(() {
        _open = data['open'] == true;
        _with = ChatCounterpart.tryParse(data['with']);
        _messages
          ..clear()
          ..addAll((data['messages'] as List<dynamic>).map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m))));
        _loading = false;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = ApiService.getErrorMessage(e); });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send(String text) async {
    final body = text.trim();
    if (body.isEmpty || _sending) return;
    setState(() { _sending = true; _error = null; });
    try {
      final res = await ApiService().post(_messagesPath(widget.orderId), data: {'body': body});
      final m = ChatMessage.fromJson(Map<String, dynamic>.from(res.data['data'] as Map));
      if (!mounted) return;
      setState(() {
        if (!_messages.any((x) => x.id == m.id)) _messages.add(m);
        _input.clear();
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiService.getErrorMessage(e);
        if (ApiService.getErrorCode(e) == 'CHAT_CLOSED') _open = false;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.7;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            _header(),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _open ? 'No messages yet. Send a quick note below.' : 'No messages were sent on this delivery.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) => _bubble(_messages[i]),
                        ),
            ),
            if (_messages.isNotEmpty || _open)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                child: Row(
                  children: [
                    Icon(Icons.verified_user_outlined, size: 14, color: AppColors.textLight),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Saved with Order #${widget.orderId}. If anything goes wrong, report the order and Vendra will review this chat.',
                        style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight),
                      ),
                    ),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(_error!, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.error)),
              ),
            if (_open) _composer() else _closedNotice(),
          ],
        ),
      ),
    );
  }

  /// Who you're talking to: photo, short name, role, and a call button while the delivery is open
  Widget _header() {
    final other = _with;
    final name = other?.name ?? 'Messages with ${widget.otherLabel}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Row(
        children: [
          UserAvatar(
            name: other?.name ?? widget.otherLabel,
            photoUrl: other?.photoUrl,
            size: 44,
            badge: other?.isRider == true ? AppIcons.rider : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(
                  other == null ? 'Order #${widget.orderId}' : '${other.subtitle} · Order #${widget.orderId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (other?.phone != null)
            IconButton(
              tooltip: 'Call ${maskPhone(other!.phone)}',
              onPressed: () => ContactLauncher.call(context, other.phone),
              icon: Icon(Icons.call_outlined, color: AppColors.secondary),
            ),
          IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ],
      ),
    );
  }

  Widget _bubble(ChatMessage m) {
    final mine = m.senderRole == widget.myRole;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: mine ? AppColors.secondary : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(m.body, style: GoogleFonts.poppins(fontSize: 14, color: mine ? Colors.white : AppColors.textPrimary)),
            if (m.createdAt != null)
              Text(_time.format(m.createdAt!.toLocal()),
                  style: GoogleFonts.poppins(fontSize: 10, color: mine ? Colors.white70 : AppColors.textLight)),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
          children: [
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final q in chatQuickReplies[widget.myRole] ?? const <String>[])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(label: Text(q), onPressed: _sending ? null : () => _send(q)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: !_sending,
                    maxLength: 500,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    decoration: const InputDecoration(hintText: 'Write a message', counterText: ''),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Send',
                  onPressed: _sending ? null : () => _send(_input.text),
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _closedNotice() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Chat is closed: it is open only while a rider is on the delivery.',
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}
