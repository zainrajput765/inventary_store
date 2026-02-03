import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/db_service.dart';
import '../models/schema.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'ledger_pdf_generator.dart';

class LedgersScreen extends StatelessWidget {
  const LedgersScreen({super.key});

  void _showModernSnackBar(BuildContext context, String message, {String type = "SUCCESS"}) {
    Color bg;
    Color textColor;
    IconData icon;
    String title;

    switch (type) {
      case "ERROR": bg = const Color(0xFFF2DEDE); textColor = const Color(0xFFA94442); icon = Icons.cancel; title = "Error!"; break;
      case "WARNING": bg = const Color(0xFFFCF8E3); textColor = const Color(0xFF8A6D3B); icon = Icons.warning_amber_rounded; title = "Warning!"; break;
      case "INFO": bg = const Color(0xFFD9EDF7); textColor = const Color(0xFF31708F); icon = Icons.info; title = "Info!"; break;
      default: bg = const Color(0xFFDFF0D8); textColor = const Color(0xFF3C763D); icon = Icons.check_circle; title = "Success!";
    }

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [Icon(icon, color: textColor, size: 24), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor)), Text(message, style: TextStyle(fontSize: 12, color: textColor))])), InkWell(onTap: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(), child: Icon(Icons.close, color: textColor, size: 18))]),
        backgroundColor: bg, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: textColor.withOpacity(0.2))), width: MediaQuery.of(context).size.width > 800 ? 400 : null, margin: MediaQuery.of(context).size.width > 800 ? null : const EdgeInsets.only(bottom: 20, left: 20, right: 20), elevation: 0, duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF2B3A67);
    const secondaryColor = Color(0xFFECA400);
    const bgColor = Color(0xFFF3F4F6);

    return DefaultTabController(length: 2, child: Scaffold(backgroundColor: bgColor, appBar: AppBar(backgroundColor: primaryColor, title: const Text("Ledgers & Khata", style: TextStyle(fontWeight: FontWeight.bold)), centerTitle: true, elevation: 4, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))), bottom: const TabBar(indicatorColor: secondaryColor, indicatorWeight: 4, labelColor: secondaryColor, unselectedLabelColor: Colors.white60, labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14), tabs: [Tab(text: "PAYABLE (Suppliers)"), Tab(text: "RECEIVABLE (Customers)")])), floatingActionButton: FloatingActionButton.extended(backgroundColor: primaryColor, foregroundColor: secondaryColor, icon: const Icon(Icons.person_add), label: const Text("Add Party", style: TextStyle(fontWeight: FontWeight.bold)), onPressed: () => _showAddPartyDialog(context)), body: Column(children: [const SizedBox(height: 15), Expanded(child: TabBarView(children: [PartyList(type: "DEALER", showSnackBar: _showModernSnackBar), PartyList(type: "CUSTOMER", showSnackBar: _showModernSnackBar)])), Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8), color: Colors.white, child: const Text("HAMII MOBILES ACCOUNTS", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 1)))],),),);
  }

  void _showAddPartyDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final balanceCtrl = TextEditingController(text: "0");
    String type = "DEALER";
    bool isStandardDebt = true; // True = Normal (I owe Dealer, Customer owes Me)
    const primaryColor = Color(0xFF2B3A67);
    const secondaryColor = Color(0xFFECA400);

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
                title: const Text("Add New Contact"),
                content: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(controller: nameCtrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: "NAME", prefixIcon: Icon(Icons.person, color: primaryColor))),
                          const SizedBox(height: 10),
                          TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "PHONE", prefixIcon: Icon(Icons.phone, color: primaryColor))),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                              value: type,
                              decoration: const InputDecoration(labelText: "TYPE"),
                              items: const [DropdownMenuItem(value: "DEALER", child: Text("DEALER")), DropdownMenuItem(value: "CUSTOMER", child: Text("CUSTOMER"))],
                              onChanged: (val) => setState(() { type = val!; isStandardDebt = true; })
                          ),
                          const SizedBox(height: 10),
                          TextField(controller: balanceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "OPENING BALANCE (Rs)")),
                          const Divider(),
                          RadioListTile(
                              activeColor: primaryColor,
                              title: Text(type == "DEALER" ? "I Owe Him (Payable)" : "He Owes Me (Receivable)"),
                              value: true,
                              groupValue: isStandardDebt,
                              onChanged: (v) => setState(() => isStandardDebt = v!)
                          ),
                          RadioListTile(
                              activeColor: primaryColor,
                              title: Text(type == "DEALER" ? "He Owes Me (Advance)" : "I Owe Him (Advance)"),
                              value: false,
                              groupValue: isStandardDebt,
                              onChanged: (v) => setState(() => isStandardDebt = v!)
                          )
                        ]
                    )
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: secondaryColor),
                      onPressed: () {
                        if (nameCtrl.text.isNotEmpty) {
                          // --- FIX: CALCULATE SIGNED BALANCE ---
                          double rawAmount = double.tryParse(balanceCtrl.text) ?? 0.0;
                          double finalAmount = rawAmount.abs();

                          // Ledger Logic:
                          // Dealer Payable = Negative
                          // Customer Receivable = Positive
                          if (type == "DEALER") {
                            if (isStandardDebt) finalAmount = -finalAmount; // I Owe Dealer -> Negative
                          } else {
                            if (!isStandardDebt) finalAmount = -finalAmount; // I Owe Customer (Advance) -> Negative
                          }

                          Provider.of<DbService>(context, listen: false).addParty(
                              nameCtrl.text.toUpperCase(),
                              phoneCtrl.text,
                              type,
                              openingBalance: finalAmount // Pass Signed Amount
                          );
                          Navigator.pop(ctx);
                          _showModernSnackBar(context, "Party Added Successfully!", type: "SUCCESS");
                        }
                      },
                      child: const Text("Save")
                  )
                ]
            )
        )
    );
  }
}

class PartyList extends StatelessWidget {
  final String type;
  final Function(BuildContext, String, {String type}) showSnackBar;
  const PartyList({super.key, required this.type, required this.showSnackBar});

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<DbService>(context);
    bool isDesktop = MediaQuery.of(context).size.width > 800; int crossAxisCount = isDesktop ? 2 : 1; double childAspectRatio = isDesktop ? 4.0 : 3.0;
    return StreamBuilder<List<Party>>(stream: db.listenToParties(type), builder: (context, snapshot) { if (!snapshot.hasData) return const Center(child: CircularProgressIndicator()); var list = snapshot.data!; if (type == "CUSTOMER") list = list.where((p) => p.balance != 0).toList(); if (list.isEmpty) return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.folder_open, size: 60, color: Colors.grey), SizedBox(height: 10), Text("No Records")])); return GridView.builder(padding: const EdgeInsets.all(16), itemCount: list.length, gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: childAspectRatio), itemBuilder: (context, index) { final p = list[index]; return _buildPartyCard(context, p, db); }); });
  }

  Widget _buildPartyCard(BuildContext context, Party p, DbService db) {
    const primaryColor = Color(0xFF2B3A67);

    // --- UPDATED DISPLAY LOGIC ---
    // Dealer: Negative = Payable (RED), Positive = Advance (GREEN)
    // Customer: Positive = Receivable (GREEN), Negative = Advance (RED)

    Color balanceColor;
    String statusText;

    if (p.type == "DEALER") {
      if (p.balance < 0) {
        balanceColor = Colors.red;
        statusText = "Payable (You Owe)";
      } else if (p.balance > 0) {
        balanceColor = Colors.green;
        statusText = "Advance (Owes You)";
      } else {
        balanceColor = Colors.grey;
        statusText = "Settled";
      }
    } else {
      if (p.balance > 0) {
        balanceColor = Colors.green;
        statusText = "Receivable (Owes You)";
      } else if (p.balance < 0) {
        balanceColor = Colors.red;
        statusText = "Advance (You Owe)";
      } else {
        balanceColor = Colors.grey;
        statusText = "Settled";
      }
    }

    return Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 3))]), child: Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(12), onTap: () => _showPartyHistory(context, p, db), child: Padding(padding: const EdgeInsets.all(16.0), child: Row(children: [CircleAvatar(radius: 24, backgroundColor: const Color(0xFFE0E0E0), child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : "?", style: const TextStyle(color: Color(0xFF424242), fontWeight: FontWeight.bold, fontSize: 18))), const SizedBox(width: 16), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(p.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: primaryColor)), const SizedBox(height: 4), Text(p.phone.isEmpty ? "No Phone" : p.phone, style: TextStyle(fontSize: 12, color: Colors.grey[600]))])), Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text("Rs ${p.balance.abs().toInt()}", style: TextStyle(color: balanceColor, fontWeight: FontWeight.bold, fontSize: 18)), Text(statusText, style: TextStyle(color: balanceColor, fontSize: 11, fontWeight: FontWeight.w500))])])))));
  }

  void _showPartyHistory(BuildContext context, Party party, DbService db) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (ctx) => StatefulBuilder(builder: (context, setState) {
      return Container(height: MediaQuery.of(context).size.height * 0.9, decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))), child: Column(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), decoration: const BoxDecoration(color: Color(0xFF2B3A67), borderRadius: BorderRadius.vertical(top: Radius.circular(20))), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(party.name.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text("Balance: Rs ${party.balance.toInt()}", style: const TextStyle(color: Color(0xFFECA400), fontWeight: FontWeight.bold, fontSize: 16))]), Row(children: [IconButton(onPressed: () async { final history = await db.getTransactionsForParty(party.id); final pdfData = await generateLedgerPdf(party, history); await Printing.layoutPdf(onLayout: (format) => pdfData); }, icon: const Icon(Icons.download, color: Colors.white), tooltip: "Download Ledger"), IconButton(onPressed: () => _confirmDeleteParty(context, party, db), icon: const Icon(Icons.delete, color: Colors.redAccent), tooltip: "Delete Party"), IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: Colors.white))])])])),
        Expanded(child: FutureBuilder<List<Transaction>>(future: db.getTransactionsForParty(party.id), builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator()); final history = snapshot.data!; if (history.isEmpty) return const Center(child: Text("No transactions yet.", style: TextStyle(color: Colors.grey)));
          return ListView.separated(padding: const EdgeInsets.all(16), itemCount: history.length, separatorBuilder: (_,__) => const Divider(height: 1), itemBuilder: (context, index) {
            final t = history[index];
            if(t.amount == 0) return const SizedBox.shrink();

            bool isCashPurchase = (t.type == "PURCHASE" || t.type == "SALE_CASH" || t.type == "SALE_BANK");
            bool isDealer = party.type == "DEALER";
            bool isCredit = false;

            // Logic matching the DB convention
            if (isDealer) {
              if (t.type == "PURCHASE_CREDIT") isCredit = false; // Negative (Debt)
              else isCredit = true; // Payment (Positive)
            } else {
              if (t.type.contains("PAYMENT_IN") || t.type == "RETURN_CREDIT") isCredit = true;
              else isCredit = false;
            }

            Color color = isCashPurchase ? Colors.grey : (isCredit ? Colors.green : Colors.red);
            String sign = isCashPurchase ? "" : (isCredit ? "+" : "-");

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(Icons.receipt, color: color, size: 20)),
              title: Text(t.description?.toUpperCase() ?? "TRANSACTION", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text("${DateFormat('dd-MMM').format(t.date)} • ${t.paymentSource?.toUpperCase() ?? 'CASH'}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
              trailing: Text("$sign Rs ${t.amount.toInt()}", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
            );
          });
        })),
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -5))]), child: Row(children: [Expanded(child: ElevatedButton.icon(onPressed: () => _showTransactionDialog(context, party, db, isCredit: false), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), icon: const Icon(Icons.remove_circle_outline), label: const Text("GAVE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))), const SizedBox(width: 16), Expanded(child: ElevatedButton.icon(onPressed: () => _showTransactionDialog(context, party, db, isCredit: true), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF43A047), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), icon: const Icon(Icons.add_circle_outline), label: const Text("GOT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))))]))
      ]));
    }),
    );
  }

  void _showTransactionDialog(BuildContext context, Party party, DbService db, {required bool isCredit}) {
    final amtCtrl = TextEditingController(); final descCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(isCredit ? "Received Payment (GOT)" : "Made Payment (GAVE)", style: TextStyle(color: isCredit ? Colors.green : Colors.red)), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: amtCtrl, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: "AMOUNT (RS)")), const SizedBox(height: 10), TextField(controller: descCtrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: "NOTE (OPTIONAL)", prefixIcon: Icon(Icons.edit)))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: isCredit ? Colors.green : Colors.red, foregroundColor: Colors.white), onPressed: () { if (amtCtrl.text.isNotEmpty) { double amt = double.parse(amtCtrl.text); db.updatePartyBalance(party.id, amt, isCredit, descCtrl.text.isEmpty ? (isCredit ? "RECEIVED" : "PAID") : descCtrl.text.toUpperCase()); Navigator.pop(ctx); showSnackBar(context, "Transaction Updated!", type: "SUCCESS"); } }, child: const Text("Save"))]));
  }

  void _confirmDeleteParty(BuildContext context, Party party, DbService db) {
    if (party.balance != 0) { showDialog(context: context, builder: (ctx) => AlertDialog(title: const Row(children: [Icon(Icons.error_outline, color: Colors.red), SizedBox(width: 10), Text("Action Denied")]), content: Text("Cannot delete ${party.name} because the balance is not zero (Rs ${party.balance.toInt()}).\n\nPlease settle the amount before deleting."), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK", style: TextStyle(color: Colors.red)))])); return; }
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("Delete Account?"), content: Text("Are you sure you want to remove ${party.name}? This action cannot be undone."), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), onPressed: () { db.deleteParty(party.id); Navigator.pop(ctx); Navigator.pop(context); showSnackBar(context, "${party.name} deleted successfully.", type: "SUCCESS"); }, child: const Text("Delete"))]));
  }
}