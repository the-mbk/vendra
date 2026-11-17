// Receipt Print / Share: which way the PDF goes on each platform. On the web it
// never touches the printing plugin's platform channel (the cause of
// "MissingPluginException ... printPdf on channel net.nfet.printing"); on a phone
// without a print service it falls back to sharing, and the snackbar never shows
// the raw platform error.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:vendra_vendor/features/vendor/models/pos_receipt.dart';
import 'package:vendra_vendor/features/vendor/services/receipt_output.dart';
import 'package:vendra_vendor/features/vendor/widgets/receipt_slip.dart';

/// Records calls; throws [printError] / [shareError] when set
class _FakeDriver implements PdfOutputDriver {
  final ReceiptOutcome printResult;
  final ReceiptOutcome shareResult;
  final Object? printError;
  final Object? shareError;
  final calls = <String>[];
  PdfPageFormat? format;

  _FakeDriver({
    this.printResult = ReceiptOutcome.printDialog,
    this.shareResult = ReceiptOutcome.shared,
    this.printError,
    this.shareError,
  });

  @override
  Future<ReceiptOutcome> print(Uint8List bytes, {required String name, required PdfPageFormat format}) async {
    calls.add('print:$name');
    this.format = format;
    if (printError != null) throw printError!;
    return printResult;
  }

  @override
  Future<ReceiptOutcome> share(Uint8List bytes, {required String filename}) async {
    calls.add('share:$filename');
    if (shareError != null) throw shareError!;
    return shareResult;
  }
}

final _bytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]); // "%PDF"
final _missing = MissingPluginException('No implementation found for method printPdf on channel net.nfet.printing');

void main() {
  group('web', () {
    test('prints through the browser at 80 mm and never calls the plugin', () async {
      final browser = _FakeDriver();
      final plugin = _FakeDriver(printError: _missing, shareError: _missing);
      final output = ReceiptOutput(isWeb: true, browserDriver: browser, pluginDriver: plugin);

      expect(await output.print(_bytes, name: 'POS-000042'), ReceiptOutcome.printDialog);
      expect(browser.calls, ['print:POS-000042']);
      expect(browser.format, PdfPageFormat.roll80);
      expect(plugin.calls, isEmpty);
    });

    test('passes on the browser fallback (opened in a new tab)', () async {
      final browser = _FakeDriver(printResult: ReceiptOutcome.openedInTab);
      final output = ReceiptOutput(isWeb: true, browserDriver: browser, pluginDriver: _FakeDriver());
      expect(await output.print(_bytes, name: 'POS-1'), ReceiptOutcome.openedInTab);
    });

    test('downloads the PDF when the browser print throws', () async {
      final browser = _FakeDriver(printError: StateError('iframe blocked'), shareResult: ReceiptOutcome.downloaded);
      final output = ReceiptOutput(isWeb: true, browserDriver: browser, pluginDriver: _FakeDriver());

      expect(await output.print(_bytes, name: 'POS-000042'), ReceiptOutcome.downloaded);
      expect(browser.calls, ['print:POS-000042', 'share:POS-000042.pdf']);
    });

    test('Share downloads <receiptNumber>.pdf in the browser', () async {
      final browser = _FakeDriver(shareResult: ReceiptOutcome.downloaded);
      final plugin = _FakeDriver();
      final output = ReceiptOutput(isWeb: true, browserDriver: browser, pluginDriver: plugin);

      expect(await output.share(_bytes, filename: 'POS-000042.pdf'), ReceiptOutcome.downloaded);
      expect(browser.calls, ['share:POS-000042.pdf']);
      expect(plugin.calls, isEmpty);
    });

    test('a blocked download is a friendly error', () async {
      final browser = _FakeDriver(printError: StateError('x'), shareError: StateError('y'));
      final output = ReceiptOutput(isWeb: true, browserDriver: browser, pluginDriver: _FakeDriver());
      await expectLater(
        output.print(_bytes, name: 'POS-1'),
        throwsA(isA<ReceiptOutputException>().having((e) => e.message, 'message', contains('Allow pop-ups'))),
      );
    });
  });

  group('mobile', () {
    test('prints with the plugin and never the browser', () async {
      final browser = _FakeDriver(printError: UnsupportedError('web only'));
      final plugin = _FakeDriver();
      final output = ReceiptOutput(isWeb: false, browserDriver: browser, pluginDriver: plugin);

      expect(await output.print(_bytes, name: 'POS-7'), ReceiptOutcome.printDialog);
      expect(plugin.calls, ['print:POS-7']);
      expect(browser.calls, isEmpty);
    });

    test('MissingPluginException on print falls back to sharing the PDF', () async {
      final plugin = _FakeDriver(printError: _missing);
      final output = ReceiptOutput(isWeb: false, browserDriver: _FakeDriver(), pluginDriver: plugin);

      expect(await output.print(_bytes, name: 'POS-7'), ReceiptOutcome.sharedInsteadOfPrint);
      expect(plugin.calls, ['print:POS-7', 'share:POS-7.pdf']);
    });

    test('a PlatformException (no print service) also falls back to sharing', () async {
      final plugin = _FakeDriver(printError: PlatformException(code: 'PRINT_ERROR', message: 'No print service'));
      final output = ReceiptOutput(isWeb: false, browserDriver: _FakeDriver(), pluginDriver: plugin);
      expect(await output.print(_bytes, name: 'POS-7'), ReceiptOutcome.sharedInsteadOfPrint);
    });

    test('no plugin at all: a friendly message without the exception text', () async {
      final plugin = _FakeDriver(printError: _missing, shareError: _missing);
      final output = ReceiptOutput(isWeb: false, browserDriver: _FakeDriver(), pluginDriver: plugin);
      await expectLater(
        output.print(_bytes, name: 'POS-7'),
        throwsA(isA<ReceiptOutputException>()
            .having((e) => e.message, 'message', ReceiptOutput.unavailableMessage)
            .having((e) => e.message, 'message', isNot(contains('MissingPlugin')))),
      );
      await expectLater(output.share(_bytes, filename: 'POS-7.pdf'), throwsA(isA<ReceiptOutputException>()));
    });

    test('other print failures are not turned into a share', () async {
      final plugin = _FakeDriver(printError: StateError('PDF too big'));
      final output = ReceiptOutput(isWeb: false, browserDriver: _FakeDriver(), pluginDriver: plugin);
      await expectLater(output.print(_bytes, name: 'POS-7'), throwsA(isA<ReceiptOutputException>()));
      expect(plugin.calls, ['print:POS-7']);
    });
  });

  test('outcome notes', () {
    String? note(ReceiptOutcome o, {bool printing = true}) =>
        receiptOutcomeMessage(o, printing: printing, filename: 'POS-1.pdf');
    expect(note(ReceiptOutcome.printDialog), isNull);
    expect(note(ReceiptOutcome.cancelled), isNull);
    expect(note(ReceiptOutcome.shared, printing: false), isNull);
    expect(note(ReceiptOutcome.openedInTab), contains('new tab'));
    expect(note(ReceiptOutcome.downloaded), contains('POS-1.pdf was downloaded'));
    expect(note(ReceiptOutcome.downloaded, printing: false), 'Saved POS-1.pdf to your downloads.');
    expect(note(ReceiptOutcome.sharedInsteadOfPrint), contains('shared as a PDF instead'));
  });

  group('ReceiptActions', () {
    final receipt = PosReceipt.fromJson({
      'receipt_number': 'POS-000042',
      'store': {'name': 'Usman Electronics'},
      'sale': {
        'id': 42,
        'total_amount': 900,
        'created_at': '2026-11-14T10:30:00Z',
        'items': [
          {'product_name': 'USB-C Cable', 'quantity': 2, 'unit_price': 450},
        ],
      },
    });
    late ReceiptOutput original;
    setUp(() => original = ReceiptOutput.instance);
    tearDown(() => ReceiptOutput.instance = original);

    Future<void> tapPrint(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReceiptActions(receipt: receipt))));
      await tester.runAsync(() async {
        await tester.tap(find.text('Print'));
        // Builds the PDF for real, then hands it to the fake driver
        for (var i = 0; i < 50 && find.byType(SnackBar).evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pump();
    }

    testWidgets('a phone without the print plugin shares instead, with a friendly note', (tester) async {
      final plugin = _FakeDriver(printError: _missing);
      ReceiptOutput.instance = ReceiptOutput(isWeb: false, browserDriver: _FakeDriver(), pluginDriver: plugin);

      await tapPrint(tester);

      expect(plugin.calls, ['print:POS-000042', 'share:POS-000042.pdf']);
      expect(find.textContaining('shared as a PDF instead'), findsOneWidget);
      expect(find.textContaining('MissingPluginException'), findsNothing);
    });

    testWidgets('when nothing works the snackbar is friendly, not the raw exception', (tester) async {
      ReceiptOutput.instance = ReceiptOutput(
        isWeb: false,
        browserDriver: _FakeDriver(),
        pluginDriver: _FakeDriver(printError: _missing, shareError: _missing),
      );

      await tapPrint(tester);

      expect(find.text(ReceiptOutput.unavailableMessage), findsOneWidget);
      expect(find.textContaining('MissingPluginException'), findsNothing);
      expect(find.textContaining('net.nfet.printing'), findsNothing);
    });
  });
}
