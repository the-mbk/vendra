// ══════════════════════════════════════════════════════════════
// Vendra Customer App - What an order's receipt says
// One place that turns an order into receipt wording, shared by the
// on-screen receipt (order_receipt_screen.dart) and its PDF
// (order_receipt_pdf.dart), so the two always match:
//   stamp        PAID / REFUNDED / PART REFUNDED / CANCELLED / UNDER REVIEW
//   payment      wallet or the card that paid, and where the money is now
//                (held in escrow, released to the store, refunded)
//   totals       subtotal, delivery fee, total charged, any refund to the
//                wallet and what the customer paid in the end
// ══════════════════════════════════════════════════════════════

import 'package:intl/intl.dart';
import 'package:vendra_customer/vendra_core.dart';

enum ReceiptStamp {
  paid('PAID'),
  refunded('REFUNDED'),
  partlyRefunded('PART REFUNDED'),
  cancelled('CANCELLED'),
  underReview('UNDER REVIEW');

  final String label;
  const ReceiptStamp(this.label);
}

/// A label / value row in the receipt's details block
typedef ReceiptDetail = ({String label, String value});

class OrderReceipt {
  final OrderModel order;
  const OrderReceipt(this.order);

  static final _dateTime = DateFormat('d MMM yyyy, h:mm a');

  /// Same order number the orders list shows
  String get number => '#VDR-${order.id.toString().padLeft(5, '0')}';

  /// PDF file name, without the extension
  String get fileName => 'Vendra-Order-${order.id}';

  bool get isCancelled => order.status == 'cancelled';
  double get total => order.totalAmount;
  double get refunded => order.refundedAmount;

  /// What the customer paid once refunds are taken off
  double get netPaid => (total - refunded).clamp(0, double.infinity).toDouble();

  /// Kept by the store when a confirmed order was cancelled late (the rest came back)
  double get lateCancellationFee => isCancelled && refunded > 0 && refunded < total - 0.005 ? total - refunded : 0;

  ReceiptStamp get stamp {
    if (isCancelled) {
      if (refunded <= 0) return ReceiptStamp.cancelled;
      return refunded >= total - 0.005 ? ReceiptStamp.refunded : ReceiptStamp.partlyRefunded;
    }
    if (order.escrowStatus == 'disputed') return ReceiptStamp.underReview;
    if (order.escrowStatus == 'refunded') return ReceiptStamp.refunded;
    if (refunded > 0) return ReceiptStamp.partlyRefunded;
    return ReceiptStamp.paid;
  }

  DateTime? get placedAt => order.createdAt == null ? null : DateTime.tryParse(order.createdAt!)?.toLocal();

  String formatDate(DateTime? at) => at == null ? '-' : _dateTime.format(at.toLocal());

  String get paymentMethod =>
      order.paymentMethod == 'card' ? (order.cardLabel ?? 'Debit / credit card') : 'Vendra wallet';

  /// Where the money is now
  String get paymentStatus {
    if (isCancelled) {
      return refunded > 0 ? 'Refunded to your Vendra wallet' : 'Order cancelled';
    }
    switch (order.escrowStatus) {
      case 'released':
        return refunded > 0 ? 'Settled: part refunded to your wallet, the rest paid to the store' : 'Paid to the store';
      case 'refunded':
        return 'Refunded to your Vendra wallet';
      case 'disputed':
        return 'Held by Vendra while your report is reviewed';
      default:
        return order.status == 'delivered'
            ? 'Held by Vendra until the report window closes'
            : 'Held by Vendra until your order is delivered';
    }
  }

  String get fulfilment => order.isDelivery ? 'Home delivery' : 'Self pickup at the store';

  String get orderStatus => isCancelled ? 'Cancelled' : order.statusText;

  /// Order number, dates, fulfilment, address and payment, in reading order
  List<ReceiptDetail> get details => [
        (label: 'Order number', value: number),
        (label: 'Placed', value: formatDate(placedAt)),
        if (order.deliveredAt != null)
          (label: order.isDelivery ? 'Delivered' : 'Collected', value: formatDate(order.deliveredAt))
        else
          (label: 'Status', value: orderStatus),
        if (isCancelled && (order.cancellationReason ?? '').isNotEmpty)
          (label: 'Reason', value: order.cancellationReason!),
        (label: 'Fulfilment', value: fulfilment),
        if (order.isDelivery && (order.deliveryAddress ?? '').isNotEmpty)
          (label: 'Deliver to', value: order.deliveryAddress!),
        (label: 'Paid with', value: paymentMethod),
        (label: 'Payment', value: paymentStatus),
      ];

  String get deliveryFeeText => order.isDelivery ? formatRupees(order.deliveryFee) : 'Free';

  String get refundLabel => isCancelled ? 'Refunded to your wallet' : 'Dispute refund to your wallet';

  /// A short closing note under the totals
  String get footnote {
    if (lateCancellationFee > 0) {
      return 'The store kept ${formatRupees(lateCancellationFee)} as a late-cancellation fee because it had '
          'already accepted the order.';
    }
    return 'Vendra holds your payment in escrow and pays the store only after the order reaches you.';
  }

  /// "2 × Rs. 1,500"
  static String unitLine(OrderItemModel item) => '${item.quantity} × ${formatRupees(item.unitPrice)}';

  /// The built-in PDF fonts only draw Latin-1: swap the few typographic characters we use
  static String pdfSafe(String text) {
    const swaps = {
      '×': 'x',
      '—': '-',
      '–': '-',
      '‘': "'",
      '’': "'",
      '“': '"',
      '”': '"',
      '…': '...',
      '•': '*',
      '·': '-',
      '₨': 'Rs.',
      '−': '-',
    };
    final out = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      if (swaps.containsKey(ch)) {
        out.write(swaps[ch]);
      } else if (rune == 0x0A || (rune >= 0x20 && rune <= 0x7E) || (rune >= 0xA0 && rune <= 0xFF)) {
        out.write(ch);
      } else {
        out.write('?');
      }
    }
    return out.toString();
  }
}
