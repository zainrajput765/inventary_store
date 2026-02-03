import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/db_service.dart';
import '../models/schema.dart';
import 'package:intl/intl.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  // Data Variables
  Map<String, double> accountBalances = {};
  double totalStockValue = 0.0;
  double periodRevenue = 0.0;
  double periodExpenses = 0.0;
  double periodProfit = 0.0;
  DateTimeRange? _dateRange;

  // --- COLOR SCHEME ---
  final Color primaryColor = const Color(0xFF2B3A67); // Royal Navy
  final Color accentColor = const Color(0xFFECA400); // Gold
  final Color bgColor = const Color(0xFFF3F4F6); // Soft Gray

  // --- HELPER: Web-Style "Toast" Snackbar (Matches Stock List Screen) ---
  void _showModernSnackBar(String message, {String type = "SUCCESS"}) {
    Color bg;
    Color textColor;
    IconData icon;
    String title;

    switch (type) {
      case "ERROR":
        bg = const Color(0xFFF2DEDE); // Pale Red
        textColor = const Color(0xFFA94442); // Dark Red
        icon = Icons.cancel;
        title = "Error!";
        break;
      case "WARNING":
        bg = const Color(0xFFFCF8E3); // Pale Yellow
        textColor = const Color(0xFF8A6D3B); // Dark Yellow
        icon = Icons.warning_amber_rounded;
        title = "Warning!";
        break;
      case "INFO":
        bg = const Color(0xFFD9EDF7); // Pale Blue
        textColor = const Color(0xFF31708F); // Dark Blue
        icon = Icons.info;
        title = "Info!";
        break;
      default: // SUCCESS
        bg = const Color(0xFFDFF0D8); // Pale Green
        textColor = const Color(0xFF3C763D); // Dark Green
        icon = Icons.check_circle;
        title = "Success!";
    }

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: textColor, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor)),
                  Text(message, style: TextStyle(fontSize: 12, color: textColor)),
                ],
              ),
            ),
            InkWell(
              onTap: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
              child: Icon(Icons.close, color: textColor, size: 18),
            )
          ],
        ),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: textColor.withOpacity(0.2)),
        ),
        width: MediaQuery.of(context).size.width > 800 ? 400 : null,
        margin: MediaQuery.of(context).size.width > 800 ? null : const EdgeInsets.only(bottom: 20, left: 20, right: 20),
        elevation: 0,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Default to TODAY when opening
    _resetToToday();
    // Auto-Refresh when DB changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DbService>(context, listen: false).addListener(_onDbChange);
    });
  }

  @override
  void dispose() {
    Provider.of<DbService>(context, listen: false).removeListener(_onDbChange);
    super.dispose();
  }

  void _onDbChange() {
    if (mounted) _loadData();
  }

  void _resetToToday() {
    setState(() {
      DateTime now = DateTime.now();
      _dateRange = DateTimeRange(start: now, end: now);
    });
    _loadData();
  }

  Future<void> _loadData() async {
    final db = Provider.of<DbService>(context, listen: false);

    // 1. Current Snapshot Data
    final bals = await db.getCashFlowBalances();
    final stk = await db.getStockValue();

    // 2. Period Data Logic
    DateTime start = _dateRange?.start ?? DateTime.now();
    DateTime rawEnd = _dateRange?.end ?? DateTime.now();

    // Set end date to 23:59:59 to include full day
    DateTime end = DateTime(rawEnd.year, rawEnd.month, rawEnd.day, 23, 59, 59);
    start = DateTime(start.year, start.month, start.day, 0, 0, 0);

    final rev = await db.getRevenueTotal(start, end);
    final exp = await db.getExpenseTotal(start, end);
    final prof = await db.getNetProfit(start, end);

    if (mounted) {
      setState(() {
        accountBalances = bals;
        totalStockValue = stk;
        periodRevenue = rev;
        periodExpenses = exp;
        periodProfit = prof;
      });
    }
  }

  void _pickDateRange() async {
    final newRange = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDateRange: _dateRange ?? DateTimeRange(start: DateTime.now(), end: DateTime.now()),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: primaryColor,
                onPrimary: Colors.white,
                onSurface: primaryColor,
              ),
            ),
            child: child!,
          );
        }
    );
    if (newRange != null) {
      setState(() => _dateRange = newRange);
      _loadData();
    }
  }

  // --- UPDATED: DETAILED PDF GENERATOR ---
  Future<void> _generateReportPdf() async {
    final db = Provider.of<DbService>(context, listen: false);
    final pdf = pw.Document();

    // 1. Prepare Dates
    DateTime start = _dateRange?.start ?? DateTime.now();
    DateTime rawEnd = _dateRange?.end ?? DateTime.now();
    DateTime end = DateTime(rawEnd.year, rawEnd.month, rawEnd.day, 23, 59, 59);
    start = DateTime(start.year, start.month, start.day, 0, 0, 0);

    String dateStr = _dateRange == null
        ? "All Time"
        : "${DateFormat('dd MMM yyyy').format(start)} - ${DateFormat('dd MMM yyyy').format(rawEnd)}";

    // 2. Fetch Detailed Transactions
    final transactions = await db.getTransactionsByDate(start, end);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return [
            // --- HEADER ---
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("HAMII MOBILES", style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  pw.Text("Financial Report", style: pw.TextStyle(fontSize: 16, color: PdfColors.grey700)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Period: $dateStr", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text("Generated: ${DateFormat('dd-MM-yyyy hh:mm a').format(DateTime.now())}", style: const pw.TextStyle(color: PdfColors.grey)),
              ],
            ),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 15),

            // --- SUMMARY SECTION ---
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(5),
                color: PdfColors.grey100,
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _pdfSummaryItem("Total Revenue", periodRevenue, PdfColors.green800),
                  _pdfSummaryItem("Total Expenses", periodExpenses, PdfColors.red800),
                  _pdfSummaryItem("Net Profit", periodProfit, PdfColors.blue800, isBold: true),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // --- DETAILED TRANSACTION TABLE ---
            pw.Text("Detailed Transactions", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),

            pw.Table.fromTextArray(
              headers: ['Date', 'Description', 'Method', 'Type', 'Amount'],
              columnWidths: {
                0: const pw.FixedColumnWidth(60), // Date
                1: const pw.FlexColumnWidth(3),   // Desc
                2: const pw.FixedColumnWidth(70), // Method
                3: const pw.FixedColumnWidth(60), // Type
                4: const pw.FixedColumnWidth(70), // Amount
              },
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
              cellStyle: const pw.TextStyle(fontSize: 9),
              rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
              data: transactions.map((t) {
                // Logic to categorize
                bool isIncome = t.type.contains("SALE") || t.type.contains("IN") || t.type == "OPENING_BALANCE";
                bool isExpense = t.type == "EXPENSE" || t.type.contains("OUT");
                String displayType = isIncome ? "Income" : (isExpense ? "Expense" : "Other");

                // Color Logic for Amount
                PdfColor amtColor = isIncome ? PdfColors.green700 : (isExpense ? PdfColors.red700 : PdfColors.black);
                String prefix = isIncome ? "+" : (isExpense ? "-" : "");

                return [
                  DateFormat('dd-MM\nhh:mm a').format(t.date),
                  t.description ?? t.type,
                  t.paymentSource ?? "Cash", // Explicit Payment Method
                  displayType,
                  pw.Text("$prefix ${t.amount.toInt()}", style: pw.TextStyle(color: amtColor, fontWeight: pw.FontWeight.bold)),
                ];
              }).toList(),
            ),

            pw.SizedBox(height: 20),
            // --- FOOTER: CURRENT BALANCES ---
            pw.Text("Current Wallet Balances:", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 5),
            ...accountBalances.entries.map((e) => pw.Row(
                children: [
                  pw.Container(width: 100, child: pw.Text(e.key, style: const pw.TextStyle(fontSize: 10))),
                  pw.Text("Rs ${e.value.toInt()}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                ]
            )).toList(),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  pw.Widget _pdfSummaryItem(String label, double value, PdfColor color, {bool isBold = false}) {
    return pw.Column(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.Text(
          "Rs ${value.toInt()}",
          style: pw.TextStyle(fontSize: 14, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isToday = _dateRange != null &&
        DateUtils.isSameDay(_dateRange!.start, DateTime.now()) &&
        DateUtils.isSameDay(_dateRange!.end, DateTime.now());

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text("Financial Dashboard", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh), color: accentColor),
          IconButton(
            onPressed: _generateReportPdf,
            icon: const Icon(Icons.download), // Changed icon to Download
            color: accentColor,
            tooltip: "Download Report",
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),

            // --- 1. QUICK ACTIONS ---
            Row(
              children: [
                Expanded(child: _actionButton("Add Expense", Icons.money_off, Colors.redAccent, () => _showAddMoneyDialog("EXPENSE"))),
                const SizedBox(width: 15),
                Expanded(child: _actionButton("Add Investment", Icons.savings, Colors.green, () => _showAddMoneyDialog("INVESTMENT"))),
              ],
            ),
            const SizedBox(height: 25),

            // --- 2. DATE FILTER ---
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 5, offset: const Offset(0, 2))],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickDateRange,
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_month, color: primaryColor),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Analysis Period", style: TextStyle(color: Colors.grey[500], fontSize: 10, fontWeight: FontWeight.bold)),
                                Text(
                                    isToday
                                        ? "Today (${DateFormat('dd MMM').format(DateTime.now())})"
                                        : (_dateRange == null
                                        ? "Select Date"
                                        : "${DateFormat('dd MMM').format(_dateRange!.start)} - ${DateFormat('dd MMM').format(_dateRange!.end)}"),
                                    style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 14)
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(height: 30, width: 1, color: Colors.grey[300]),
                  IconButton(
                    onPressed: _resetToToday,
                    icon: const Icon(Icons.restore),
                    color: Colors.grey[600],
                    tooltip: "Reset View to Today",
                  ),
                  Container(height: 30, width: 1, color: Colors.grey[300]),
                  // --- NEW: VIEW HISTORY BUTTON ---
                  IconButton(
                    onPressed: () => _showTransactionHistory(context),
                    icon: const Icon(Icons.list_alt),
                    color: primaryColor,
                    tooltip: "View Transactions",
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25),

            // --- 3. MAIN SUMMARY CARD ---
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [primaryColor, primaryColor.withOpacity(0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
              ),
              child: Column(
                children: [
                  const Text("NET PROFIT", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 5),
                  Text("Rs ${periodProfit.toInt()}", style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _summaryItem("Revenue", periodRevenue, Icons.arrow_upward, Colors.greenAccent),
                      Container(width: 1, height: 30, color: Colors.white24),
                      _summaryItem("Expenses", periodExpenses, Icons.arrow_downward, Colors.redAccent),
                      Container(width: 1, height: 30, color: Colors.white24),
                      _summaryItem("Stock", totalStockValue, Icons.inventory, accentColor),
                    ],
                  )
                ],
              ),
            ),

            const SizedBox(height: 30),

            // --- 4. ACCOUNT BALANCES ---
            Text("WALLET BALANCES", style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            const SizedBox(height: 15),

            if (accountBalances.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("No accounts active.")))
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: accountBalances.length,
                itemBuilder: (context, index) {
                  String name = accountBalances.keys.elementAt(index);
                  double bal = accountBalances.values.elementAt(index);
                  return _buildBalanceRow(name, bal);
                },
              ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // --- WIDGETS ---

  Widget _actionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: color,
        elevation: 2,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color.withOpacity(0.2))),
      ),
      icon: Icon(icon, size: 20),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _summaryItem(String label, double value, IconData icon, Color color) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          Text("${value >= 1000 ? (value/1000).toStringAsFixed(1)+'k' : value.toInt()}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildBalanceRow(String name, double balance) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: primaryColor.withOpacity(0.05),
                child: Icon(name == "Cash Drawer" ? Icons.storefront : Icons.account_balance, color: primaryColor, size: 20),
              ),
              const SizedBox(width: 15),
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          Text(
              "Rs ${balance.toInt()}",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: balance < 0 ? Colors.red : Colors.black87)
          ),
        ],
      ),
    );
  }

  // --- FEATURE: ADD EXPENSE / INVESTMENT ---
  void _showAddMoneyDialog(String type) {
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String? selectedAccount;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(type == "EXPENSE" ? "Add Expense" : "Add Investment"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: "Description (e.g. Rent, Tea)")),
            const SizedBox(height: 10),
            TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Amount")),
            const SizedBox(height: 10),
            FutureBuilder<List<PaymentAccount>>(
                future: Provider.of<DbService>(context, listen: false).getPaymentAccounts(),
                builder: (context, snapshot) {
                  return DropdownButtonFormField<String>(
                    value: selectedAccount,
                    decoration: const InputDecoration(labelText: "Account"),
                    items: (snapshot.data ?? []).map((a) => DropdownMenuItem(value: a.name, child: Text(a.name))).toList(),
                    onChanged: (val) => selectedAccount = val,
                  );
                }
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (amountCtrl.text.isNotEmpty && selectedAccount != null) {
                double amt = double.parse(amountCtrl.text);
                final db = Provider.of<DbService>(context, listen: false);
                try {
                  if (type == "EXPENSE") {
                    await db.addExpense(amt, descCtrl.text, selectedAccount!);
                  } else {
                    await db.addCapital(amt, descCtrl.text, selectedAccount!);
                  }
                  if (mounted) Navigator.pop(ctx);
                  _showModernSnackBar("Transaction Added Successfully", type: "SUCCESS");
                } catch (e) {
                  // --- CATCH INSUFFICIENT FUNDS ERROR ---
                  if (mounted) Navigator.pop(ctx);
                  // Remove "Exception: " prefix for cleaner display
                  String msg = e.toString().replaceAll("Exception: ", "");
                  _showModernSnackBar(msg, type: "ERROR");
                }
              }
            },
            child: const Text("Save"),
          )
        ],
      ),
    );
  }

  // --- FEATURE: VIEW TRANSACTIONS SHEET ---
  void _showTransactionHistory(BuildContext context) {
    final db = Provider.of<DbService>(context, listen: false);
    // Correct Date Logic for History Query
    DateTime start = _dateRange?.start ?? DateTime.now();
    DateTime rawEnd = _dateRange?.end ?? DateTime.now();
    DateTime end = DateTime(rawEnd.year, rawEnd.month, rawEnd.day, 23, 59, 59);
    start = DateTime(start.year, start.month, start.day, 0, 0, 0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Transaction History", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: Colors.white))
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Transaction>>(
                future: db.getTransactionsByDate(start, end),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final list = snapshot.data!;
                  if (list.isEmpty) return const Center(child: Text("No transactions in this period"));

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    separatorBuilder: (_,__) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final t = list[index];
                      bool isIncome = t.type.contains("SALE") || t.type.contains("IN") || t.type == "OPENING_BALANCE";
                      return ListTile(
                        title: Text(t.description ?? t.type, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(DateFormat('dd MMM hh:mm a').format(t.date), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        trailing: Text(
                          "${isIncome ? '+' : '-'} ${t.amount.toInt()}",
                          style: TextStyle(fontWeight: FontWeight.bold, color: isIncome ? Colors.green : Colors.red, fontSize: 15),
                        ),
                        // CLICK TO SEE DETAILS
                        onTap: () => _showTransactionDetail(context, t),
                      );
                    },
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }

  // --- FEATURE: TRANSACTION DETAIL POPUP ---
  void _showTransactionDetail(BuildContext context, Transaction t) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Transaction Details"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow("Type", t.type),
            _detailRow("Date", DateFormat('dd MMM yyyy, hh:mm a').format(t.date)),
            _detailRow("Amount", "Rs ${t.amount.toInt()}"),
            _detailRow("Account", t.paymentSource ?? "N/A"),
            const SizedBox(height: 10),
            const Text("Description:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
              child: Text(t.description ?? "No details", style: const TextStyle(fontSize: 14)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}