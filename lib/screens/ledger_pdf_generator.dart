import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../models/schema.dart';

Future<Uint8List> generateLedgerPdf(Party party, List<Transaction> history) async {
  final pdf = pw.Document();

  // --- 1. Filter Out Zero Amounts ---
  final validTransactions = history.where((t) => t.amount > 0).toList();

  // --- 2. Calculate Totals (Strictly Ledger Only) ---
  double totalDebit = 0;  // Dr (Decreases Dealer Debt / Increases Customer Debt)
  double totalCredit = 0; // Cr (Increases Dealer Debt / Decreases Customer Debt)

  for (var t in validTransactions) {
    // SKIP CASH TRANSACTIONS (Immediate Settlement)
    if (t.type == "PURCHASE" || t.type == "SALE_CASH" || t.type == "SALE_BANK") {
      continue;
    }

    if (party.type == "DEALER") {
      // --- DEALER LOGIC ---
      // CREDIT SIDE (Liability Increases - We Owe More)
      // 1. Purchase on Credit
      // 2. Opening Balance (Assuming "I Owe Him" default)
      if (t.type == "PURCHASE_CREDIT" || t.type == "OPENING_BALANCE") {
        totalCredit += t.amount;
      }
      // DEBIT SIDE (Liability Decreases - We Paid/Returned)
      // 1. Payment Out
      // 2. Returns
      // 3. Stock Corrections (Deleting stock acts like a return)
      else if (t.type == "PAYMENT_OUT" || t.type == "DEALER_RETURN" || t.type.contains("CORRECTION")) {
        totalDebit += t.amount;
      }
    } else {
      // --- CUSTOMER LOGIC ---
      // CREDIT SIDE (Asset Decreases - They Paid Us)
      // 1. Payment In
      // 2. Returns
      // 3. Stock Corrections
      if (t.type.contains("PAYMENT_IN") || t.type == "RETURN_CREDIT" || t.type == "CREDIT_ADDED" || t.type.contains("CORRECTION")) {
        totalCredit += t.amount;
      }
      // DEBIT SIDE (Asset Increases - They Owe More)
      // 1. Sale on Credit
      // 2. Opening Balance (Assuming "They Owe Me" default)
      else if (t.type == "SALE_CREDIT" || t.type == "OPENING_BALANCE") {
        totalDebit += t.amount;
      }
    }
  }

  // --- 3. Calculate Net Balance ---
  // Dealer: Credit (Payable) - Debit (Paid)
  // Customer: Debit (Receivable) - Credit (Paid)
  double calcBalance = 0;
  if (party.type == "DEALER") {
    calcBalance = totalCredit - totalDebit;
  } else {
    calcBalance = totalDebit - totalCredit;
  }

  String statusLabel = "";
  PdfColor statusColor = PdfColors.black;

  if (party.type == "DEALER") {
    // For Dealers: Positive Result = Net Payable (We Owe)
    if (calcBalance > 0) {
      statusLabel = "PAYABLE (YOU OWE)";
      statusColor = PdfColors.red;
    } else if (calcBalance < 0) {
      statusLabel = "ADVANCE (OWES YOU)";
      statusColor = PdfColors.green;
    } else {
      statusLabel = "SETTLED";
      statusColor = PdfColors.grey;
    }
  } else {
    // For Customers: Positive Result = Net Receivable (They Owe)
    if (calcBalance > 0) {
      statusLabel = "RECEIVABLE (OWES YOU)";
      statusColor = PdfColors.green;
    } else if (calcBalance < 0) {
      statusLabel = "ADVANCE (YOU OWE)";
      statusColor = PdfColors.red;
    } else {
      statusLabel = "SETTLED";
      statusColor = PdfColors.grey;
    }
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20),
      build: (pw.Context context) {
        return [
          // --- HEADER ---
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text("HAMII MOBILES", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                pw.Text("Shop LG-30 Dpoint Plaza Gujranwala", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                pw.Text("0300-7444459", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text("LEDGER STATEMENT", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.Text("Generated: ${DateFormat('dd-MMM-yyyy').format(DateTime.now()).toUpperCase()}", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
              ]),
            ],
          ),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 10),

          // --- PARTY DETAILS ---
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(5)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text("ACCOUNT FOR:", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
                  pw.Text(party.name.toUpperCase(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.Text(party.type.toUpperCase(), style: const pw.TextStyle(fontSize: 10)),
                ],),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Text("PHONE:", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
                  pw.Text(party.phone.isEmpty ? "N/A" : party.phone, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                ]),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // --- TRANSACTION TABLE ---
          pw.Table.fromTextArray(
            headers: ['DATE', 'DESCRIPTION', 'DEBIT (DR)', 'CREDIT (CR)'],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellStyle: const pw.TextStyle(fontSize: 9),
            rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            data: validTransactions.map((t) {
              // --- COLUMN LOGIC ---
              String dr = "-";
              String cr = "-";

              bool isCash = (t.type == "PURCHASE" || t.type == "SALE_CASH" || t.type == "SALE_BANK");

              if (!isCash) {
                if (party.type == "DEALER") {
                  // Dealer: Purchase/Opening = Credit, Payment/Return = Debit
                  if (t.type == "PURCHASE_CREDIT" || t.type == "OPENING_BALANCE") {
                    cr = t.amount.toInt().toString();
                  } else {
                    dr = t.amount.toInt().toString();
                  }
                } else {
                  // Customer: Payment/Return = Credit, Sale/Opening = Debit
                  if (t.type.contains("PAYMENT_IN") || t.type == "RETURN_CREDIT" || t.type == "CREDIT_ADDED" || t.type.contains("CORRECTION")) {
                    cr = t.amount.toInt().toString();
                  } else {
                    dr = t.amount.toInt().toString();
                  }
                }
              }

              // Description Formatting
              String desc = t.description?.toUpperCase() ?? "-";
              if (t.paymentSource != null && t.paymentSource != "Ledger") {
                desc += "\nVIA ${t.paymentSource!.toUpperCase()}";
              }

              return [
                DateFormat('dd-MMM-yyyy').format(t.date).toUpperCase(),
                desc,
                dr,
                cr
              ];
            }).toList(),
          ),

          pw.SizedBox(height: 15),
          pw.Divider(),

          // --- SUMMARY FOOTER ---
          pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Container(
                  width: 200,
                  child: pw.Column(
                      children: [
                        _summaryRow("TOTAL DEBIT (DR):", totalDebit, PdfColors.black),
                        _summaryRow("TOTAL CREDIT (CR):", totalCredit, PdfColors.black),
                        pw.Divider(thickness: 1),
                        pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text("NET TOTAL:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                              pw.Text("Rs ${calcBalance.abs().toInt()}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                            ]
                        ),
                        pw.SizedBox(height: 5),
                        pw.Container(
                          width: double.infinity,
                          padding: const pw.EdgeInsets.symmetric(vertical: 4),
                          decoration: pw.BoxDecoration(color: statusColor, borderRadius: pw.BorderRadius.circular(4)),
                          child: pw.Text(
                              statusLabel,
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)
                          ),
                        ),
                      ]
                  ),
                )
              ]
          ),

          pw.Spacer(),
          pw.Center(child: pw.Text("Computer Generated Report - Hamii Mobiles", style: const pw.TextStyle(color: PdfColors.grey, fontSize: 8))),
        ];
      },
    ),
  );

  return pdf.save();
}

pw.Widget _summaryRow(String label, double value, PdfColor color) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
        pw.Text("Rs ${value.toInt()}", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: color)),
      ],
    ),
  );
}