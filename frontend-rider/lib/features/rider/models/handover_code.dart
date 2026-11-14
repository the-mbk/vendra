// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Handover code feedback (anti GPS-spoofing)
// Confirming a delivery needs the customer's 4-digit code. The deliver
// endpoint answers a bad code with 400 OTP_REQUIRED, 422 WRONG_OTP
// { attemptsLeft } or 429 OTP_LOCKED { lockedUntil }; this turns those
// into what the code dialog shows.
// ══════════════════════════════════════════════════════════════

import 'package:vendra_rider/vendra_core.dart';

/// Length of the customer's delivery code
const handoverCodeLength = 4;

/// Five wrong codes lock the handover for this long (server LOCK_MINUTES)
const handoverLockDuration = Duration(minutes: 10);

class HandoverCodeFeedback {
  final int id;
  final String message;
  final int? attemptsLeft;

  /// Set while the handover is locked after too many wrong codes
  final DateTime? lockedUntil;

  const HandoverCodeFeedback(this.id, this.message, {this.attemptsLeft, this.lockedUntil});

  /// Null when [code] isn't a handover-code error (e.g. OUTSIDE_GEOFENCE).
  /// [now] is only for tests.
  static HandoverCodeFeedback? fromError(
    int id, {
    required String? code,
    required Map<String, dynamic>? data,
    required String message,
    DateTime? now,
  }) {
    switch (code) {
      case 'OTP_REQUIRED':
        return HandoverCodeFeedback(id, message);
      case 'WRONG_OTP':
        final left = toIntOrNull(data?['attemptsLeft']);
        return HandoverCodeFeedback(
          id,
          message,
          attemptsLeft: left,
          // The last wrong code locks it, but that reply carries no time: estimate it
          lockedUntil: left == 0 ? (now ?? DateTime.now()).add(handoverLockDuration) : null,
        );
      case 'OTP_LOCKED':
        return HandoverCodeFeedback(
          id,
          message,
          lockedUntil: toDate(data?['lockedUntil']) ?? (now ?? DateTime.now()).add(handoverLockDuration),
        );
      default:
        return null;
    }
  }

  bool isLocked([DateTime? now]) => lockedUntil != null && lockedUntil!.isAfter(now ?? DateTime.now());
}
