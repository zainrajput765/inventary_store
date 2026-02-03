import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math';
import 'package:isar/isar.dart';
import '../services/db_service.dart';
import '../services/cart_service.dart';
import '../models/schema.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'scanner_screen.dart';

// ==============================================================================
// === 1. CONFIGURATION & MODELS
// ==============================================================================

const String shopAddress = "Shop LG-30 Dpoint Plaza Gujranwala";
const String shopPhone = "0300-7444459";

class ReceiptData {
  final List<CartItem> items;
  final double total;
  final double subtotal;
  final double discount;
  final double tradeInAmount;
  final String tradeInModel;
  final String tradeInImei;
  final String paymentMethod;
  final String customerName;
  final DateTime date;
  final double paidAmount;
  final double cashPaid;
  final double bankPaid;
  final double balanceDue;
  final bool isReturn;

  ReceiptData({
    required this.items,
    required this.total,
    required this.subtotal,
    required this.discount,
    required this.tradeInAmount,
    this.tradeInModel = "",
    this.tradeInImei = "",
    required this.paymentMethod,
    required this.customerName,
    required this.date,
    required this.paidAmount,
    required this.cashPaid,
    required this.bankPaid,
    required this.balanceDue,
    this.isReturn = false,
  });
}

// ==============================================================================
// === 2. POS SCREEN
// ==============================================================================

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> with SingleTickerProviderStateMixin {
  // Logic Controllers
  final customerCtrl = TextEditingController();

  // Trade-In Controllers
  final tradeBrandCtrl = TextEditingController();
  final tradeNameCtrl = TextEditingController();
  final tradeImeiCtrl = TextEditingController();
  final tradeColorCtrl = TextEditingController();
  final tradeStorageCtrl = TextEditingController();
  final tradeConditionCtrl = TextEditingController();
  final tradePriceCtrl = TextEditingController();
  final tradeSellCtrl = TextEditingController();

  // Manual Return Controllers
  final retNameCtrl = TextEditingController();
  final retImeiCtrl = TextEditingController();
  final retPriceCtrl = TextEditingController();

  bool isProcessing = false;
  bool isTradeInExpanded = false;
  bool _isReturnMode = false; // Toggle for Refund Mode

  // --- COLOR SCHEME ---
  Color get primaryColor => _isReturnMode ? const Color(0xFFC62828) : const Color(0xFF2B3A67);
  Color get accentColor => const Color(0xFFECA400);
  final Color bgColor = const Color(0xFFF3F4F6);

  // --- HELPER: Web-Style "Toast" Notifications ---
  void _showModernSnackBar(String message, {String type = "SUCCESS"}) {
    Color bg;
    Color textColor;
    IconData icon;
    String title;

    switch (type) {
      case "ERROR":
        bg = const Color(0xFFF2DEDE); textColor = const Color(0xFFA94442); icon = Icons.cancel; title = "Error!"; break;
      case "WARNING":
        bg = const Color(0xFFFCF8E3); textColor = const Color(0xFF8A6D3B); icon = Icons.warning_amber_rounded; title = "Warning!"; break;
      case "INFO":
        bg = const Color(0xFFD9EDF7); textColor = const Color(0xFF31708F); icon = Icons.info; title = "Info!"; break;
      default:
        bg = const Color(0xFFDFF0D8); textColor = const Color(0xFF3C763D); icon = Icons.check_circle; title = "Success!";
    }

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [Icon(icon, color: textColor, size: 24), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor)), Text(message, style: TextStyle(fontSize: 12, color: textColor))])), InkWell(onTap: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(), child: Icon(Icons.close, color: textColor, size: 18))]),
        backgroundColor: bg, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: textColor.withOpacity(0.2))), margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20), elevation: 0, duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartService>(context);
    bool isSmallScreen = MediaQuery.of(context).size.width < 400; // Check for small mobile screens

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(_isReturnMode ? Icons.assignment_return : Icons.point_of_sale, color: accentColor),
            const SizedBox(width: 10),
            Text(_isReturnMode ? "Return" : "POS", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        backgroundColor: primaryColor,
        elevation: 4,
        centerTitle: false,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))),
        actions: [
          Row(
            children: [
              // Hide text on small screens
              if (!isSmallScreen)
                Text(_isReturnMode ? "REFUND" : "SALE", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70)),
              Switch(
                value: _isReturnMode,
                onChanged: (v) {
                  setState(() => _isReturnMode = v);
                  cart.clearCart();
                  _showModernSnackBar(v ? "Refund Mode Active: Search Sold items." : "Sale Mode Active", type: "INFO");
                },
                activeColor: Colors.white,
                activeTrackColor: Colors.redAccent.shade100,
                inactiveThumbColor: accentColor,
                inactiveTrackColor: Colors.white24,
              ),
            ],
          ),
          IconButton(
              onPressed: () => _showProductSearch(),
              icon: const Icon(Icons.search, color: Colors.white),
              tooltip: _isReturnMode ? "Search Sold Items" : "Search Stock"
          ),
          IconButton(onPressed: () async { String? code = await Navigator.push(context, MaterialPageRoute(builder: (_) => const ScannerScreen())); if (code != null && mounted) _handleScan(code); }, icon: Icon(Icons.qr_code_scanner, color: accentColor), tooltip: "Scan Barcode"),
          IconButton(onPressed: () => cart.clearCart(), icon: const Icon(Icons.delete_sweep, color: Colors.white), tooltip: "Clear Cart"),
          const SizedBox(width: 10),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isDesktop = constraints.maxWidth > 900;
          return isDesktop
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: _buildCartSection(cart, true)),
            Expanded(flex: 2, child: _buildControlSection(cart, true)),
          ])
              : Column(children: [
            Expanded(child: _buildCartSection(cart, false)),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -5))],
              ),
              constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.65), // Increased height slightly
              child: _buildControlSection(cart, false),
            ),
          ]);
        },
      ),
    );
  }

  // --- CART SECTION ---
  Widget _buildCartSection(CartService cart, bool isDesktop) {
    return Container(
      margin: EdgeInsets.fromLTRB(16, isDesktop ? 16 : 10, isDesktop ? 8 : 16, 16),
      child: cart.items.isEmpty
          ? _buildEmptyState()
          : ListView.separated(
        padding: const EdgeInsets.all(4),
        itemCount: cart.items.length,
        separatorBuilder: (c, i) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _buildCartItemCard(cart.items[index], cart),
      ),
    );
  }

  // --- CONTROL SECTION ---
  Widget _buildControlSection(CartService cart, bool isDesktop) {
    return Container(
      margin: isDesktop ? const EdgeInsets.fromLTRB(8, 16, 16, 16) : EdgeInsets.zero,
      decoration: isDesktop ? BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 5))]) : null,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader("Customer Info", Icons.person),
                  const SizedBox(height: 10),
                  TextField(controller: customerCtrl, decoration: _inputDecoration("Customer Name", Icons.account_circle)),

                  const SizedBox(height: 25),

                  // --- RETURN MODE: MANUAL ENTRY FORM ---
                  if (_isReturnMode) ...[
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [Icon(Icons.undo, color: Colors.red), SizedBox(width: 8), Text("Manual Return Entry", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800]))]),
                          const SizedBox(height: 5),
                          Text("Manually add item if scanner not available.", style: TextStyle(fontSize: 11, color: Colors.red[300])),
                          const SizedBox(height: 15),
                          TextField(controller: retNameCtrl, decoration: _inputDecoration("Product Name", Icons.shopping_bag)),
                          const SizedBox(height: 10),
                          TextField(controller: retImeiCtrl, decoration: _inputDecoration("IMEI (If Mobile)", Icons.qr_code)),
                          const SizedBox(height: 10),
                          TextField(controller: retPriceCtrl, keyboardType: TextInputType.number, decoration: _inputDecoration("Refund Amount", Icons.money_off)),
                          const SizedBox(height: 15),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                if (retNameCtrl.text.isNotEmpty && retPriceCtrl.text.isNotEmpty) {
                                  double price = double.tryParse(retPriceCtrl.text) ?? 0;

                                  // --- CRITICAL FIX: FORCE QTY 1 SO CART ACCEPTS IT ---
                                  Product p = Product()
                                    ..name = retNameCtrl.text
                                    ..sellPrice = price
                                    ..costPrice = price
                                    ..isMobile = retImeiCtrl.text.isNotEmpty
                                    ..imei = retImeiCtrl.text
                                    ..quantity = 1; // <--- FORCE QUANTITY TO 1

                                  Provider.of<CartService>(context, listen: false).addToCart(p);

                                  retNameCtrl.clear();
                                  retImeiCtrl.clear();
                                  retPriceCtrl.clear();
                                  _showModernSnackBar("Added to Return List", type: "INFO");
                                } else {
                                  _showModernSnackBar("Enter Name and Amount", type: "WARNING");
                                }
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                              icon: const Icon(Icons.add_shopping_cart),
                              label: const Text("Add to Return List"),
                            ),
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),
                  ],

                  // --- SALE MODE: TRADE-IN ---
                  if (!_isReturnMode) ...[
                    GestureDetector(
                      onTap: () => setState(() => isTradeInExpanded = !isTradeInExpanded),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: isTradeInExpanded ? primaryColor : Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Row(children: [Icon(Icons.swap_horizontal_circle, color: isTradeInExpanded ? accentColor : primaryColor), const SizedBox(width: 10), Text("Trade-In / Exchange", style: TextStyle(fontWeight: FontWeight.bold, color: isTradeInExpanded ? Colors.white : Colors.black87))]), Icon(isTradeInExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: isTradeInExpanded ? Colors.white : Colors.grey)]),
                      ),
                    ),
                    if (isTradeInExpanded) ...[const SizedBox(height: 15), _buildDetailedTradeInForm()],
                    const SizedBox(height: 25),
                  ],

                  _buildSectionHeader(_isReturnMode ? "Refund Summary" : "Payment Summary", Icons.receipt_long),
                  const SizedBox(height: 10),
                  _buildTotalsDisplay(cart),
                ],
              ),
            ),
          ),

          // Bottom Action
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)), boxShadow: isDesktop ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))] : null),
            child: SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: cart.items.isEmpty ? null : () => _isReturnMode ? _showReturnDialog(cart) : _showDetailedCheckoutDialog(cart),
                style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 5),
                icon: Icon(_isReturnMode ? Icons.undo : Icons.payment, size: 24),
                label: Text(_isReturnMode ? "PROCESS REFUND" : "CHECKOUT NOW", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
          )
        ],
      ),
    );
  }

  // --- SUB-WIDGETS ---
  Widget _buildSectionHeader(String title, IconData icon) { return Row(children: [Icon(icon, size: 20, color: primaryColor), const SizedBox(width: 8), Text(title, style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5))]); }
  InputDecoration _inputDecoration(String label, IconData icon) { return InputDecoration(labelText: label, prefixIcon: Icon(icon, color: Colors.grey[600], size: 20), filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: primaryColor, width: 2)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), isDense: true); }
  Widget _buildEmptyState() { return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(padding: const EdgeInsets.all(30), decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: Colors.grey.shade200)), child: Icon(_isReturnMode ? Icons.remove_shopping_cart : Icons.shopping_cart_outlined, size: 60, color: Colors.grey[300])), const SizedBox(height: 20), Text(_isReturnMode ? "Return List is Empty" : "Cart is Empty", style: TextStyle(fontSize: 18, color: Colors.grey[500], fontWeight: FontWeight.bold)), const SizedBox(height: 10), Text("Scan or enter items to ${_isReturnMode ? 'return' : 'add'}.", style: TextStyle(color: Colors.grey[400]))])); }

  Widget _buildCartItemCard(CartItem item, CartService cart) {
    return Card(elevation: 0, color: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Row(children: [
      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: primaryColor.withOpacity(0.05), borderRadius: BorderRadius.circular(10)), child: Icon(item.product.isMobile ? Icons.phone_android : Icons.headphones, color: primaryColor)), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), if (item.product.isMobile) Text("IMEI: ${item.product.imei ?? 'N/A'}", style: TextStyle(fontSize: 12, color: Colors.grey[600])) else Text("Price: ${item.price.toInt()}", style: TextStyle(fontSize: 12, color: Colors.grey[600]))])),
      if (!item.product.isMobile) ...[IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.grey), onPressed: () => _showModernSnackBar("Use + to add more units. Delete to remove.", type: "INFO"), constraints: const BoxConstraints()), Text("${item.quantity}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.green), onPressed: () => cart.addToCart(item.product), constraints: const BoxConstraints())] else ...[Text("x${item.quantity}", style: const TextStyle(fontWeight: FontWeight.bold))], const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text("Rs ${(item.price * item.quantity).toInt()}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: primaryColor)), InkWell(onTap: () => _showItemOptions(item, cart), child: const Padding(padding: EdgeInsets.all(4.0), child: Icon(Icons.more_horiz, size: 20, color: Colors.grey)))])
    ])));
  }

  Widget _buildDetailedTradeInForm() { return Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: primaryColor.withOpacity(0.2)), borderRadius: BorderRadius.circular(12)), child: Column(children: [TextField(controller: tradeBrandCtrl, decoration: _inputDecoration("Device Brand", Icons.branding_watermark)), const SizedBox(height: 10), TextField(controller: tradeNameCtrl, decoration: _inputDecoration("Device Name", Icons.phone_android)), const SizedBox(height: 10), TextField(controller: tradeImeiCtrl, decoration: _inputDecoration("IMEI / Serial", Icons.qr_code)), const SizedBox(height: 10), Row(children: [Expanded(child: TextField(controller: tradeColorCtrl, decoration: _inputDecoration("Color", Icons.color_lens))), const SizedBox(width: 10), Expanded(child: TextField(controller: tradeStorageCtrl, decoration: _inputDecoration("Storage", Icons.sd_storage)))]), const SizedBox(height: 10), TextField(controller: tradeConditionCtrl, decoration: _inputDecoration("Condition", Icons.star_half)), const Divider(height: 30), Text("Financials", style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.bold)), const SizedBox(height: 10), Row(children: [Expanded(child: TextField(controller: tradePriceCtrl, keyboardType: TextInputType.number, decoration: _inputDecoration("Buying Price", Icons.arrow_downward), onChanged: (v) => setState((){}))), const SizedBox(width: 10), Expanded(child: TextField(controller: tradeSellCtrl, keyboardType: TextInputType.number, decoration: _inputDecoration("Est. Resale", Icons.arrow_upward)))])])); }
  Widget _buildTotalsDisplay(CartService cart) { double tradeInVal = double.tryParse(tradePriceCtrl.text) ?? 0; double finalTotal = cart.total - tradeInVal; return Column(children: [_summaryRow("Subtotal", cart.subtotal), _summaryRow("Discount", -cart.discount, isLink: true, onTap: _showDiscountDialog), if (tradeInVal > 0) _summaryRow("Trade-In Credit", -tradeInVal, color: Colors.green), const Divider(height: 30), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("NET TOTAL", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)), Text("Rs ${finalTotal.toInt()}", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: primaryColor))])]); }
  Widget _summaryRow(String label, double val, {bool isLink = false, VoidCallback? onTap, Color? color}) { return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [InkWell(onTap: onTap, child: Text(label, style: TextStyle(color: isLink ? Colors.blue : Colors.grey[600], decoration: isLink ? TextDecoration.underline : null, fontWeight: FontWeight.w500))), Text("Rs ${val.toInt()}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color ?? Colors.black87))])); }

  // --- LOGIC METHODS ---
  void _showDiscountDialog() { final discountCtrl = TextEditingController(); showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("Apply Discount"), content: TextField(controller: discountCtrl, keyboardType: TextInputType.number, decoration: _inputDecoration("Amount (Rs)", Icons.money_off)), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")), ElevatedButton(onPressed: () { Provider.of<CartService>(context, listen: false).setDiscount(double.tryParse(discountCtrl.text) ?? 0); Navigator.pop(ctx); }, child: const Text("Apply"))])); }

  // --- RETURN LOGIC ---
  void _showReturnDialog(CartService cart) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Return", style: TextStyle(color: Colors.red)),
        content: Text("Refund Total: Rs ${cart.total.toInt()}\n\nItems will be added back to stock and amount will be deducted from Cash Drawer."),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), onPressed: () { Navigator.pop(ctx); _finalizeReturn(cart); }, child: const Text("Confirm Refund"))],
      ),
    );
  }

  void _finalizeReturn(CartService cart) async {
    setState(() => isProcessing = true);
    final db = Provider.of<DbService>(context, listen: false);
    double totalRefund = cart.total;

    try {
      for (var item in cart.items) {
        await db.processReturn(
            productName: item.product.name,
            refundAmount: item.price,
            originalCost: item.product.costPrice,
            customerName: customerCtrl.text.isEmpty ? "Walk-in Customer" : customerCtrl.text,
            productId: item.product.id,
            imei: item.product.imei,
            isDealerReturn: false
        );
      }
      final receipt = ReceiptData(items: List.from(cart.items), total: -totalRefund, subtotal: -cart.subtotal, discount: 0, tradeInAmount: 0, paymentMethod: "Refund (Cash)", customerName: customerCtrl.text.isEmpty ? "Walk-in Customer" : customerCtrl.text, date: DateTime.now(), paidAmount: -totalRefund, cashPaid: -totalRefund, bankPaid: 0, balanceDue: 0, isReturn: true);
      cart.clearCart(); _clearInputs(); setState(() => isProcessing = false); _showModernSnackBar("Return Processed Successfully", type: "SUCCESS"); _showReceiptPreview(receipt);
    } catch (e) { setState(() => isProcessing = false); _showModernSnackBar("Error: $e", type: "ERROR"); }
  }

  // --- SCANNER HANDLER (SMART LOGIC FOR RETURNS) ---
  void _handleScan(String code) async {
    final db = Provider.of<DbService>(context, listen: false);
    final cart = Provider.of<CartService>(context, listen: false);

    // IF IN RETURN MODE: Search specifically for items by IMEI
    if (_isReturnMode) {
      final allProducts = await db.isar.products.filter().imeiEqualTo(code).findAll();
      if (allProducts.isNotEmpty) {
        var p = allProducts.first;

        // --- NEW CHECK: PREVENT RETURNING IN-STOCK MOBILE ---
        if (p.isMobile && p.quantity > 0) {
          _showModernSnackBar("Cannot return In-Stock Mobile. Item must be Sold first.", type: "WARNING");
          return;
        }

        // --- CRITICAL FIX: FORCE QTY 1 FOR RETURN ---
        p.quantity = 1; // Trick the cart to accept it
        cart.addToCart(p);
        _showModernSnackBar("Item added to Refund list", type: "INFO");
        return;
      }
    }

    // Default Sale Search
    final products = await db.searchProducts(code).first;
    if (products.isNotEmpty) {
      cart.addToCart(products.first);
    } else {
      _showModernSnackBar("Product not found!", type: "WARNING");
    }
  }

  // --- SEARCH DIALOG (UPDATED FOR RETURNS) ---
  void _showProductSearch() {
    TextEditingController searchCtrl = TextEditingController();

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => StatefulBuilder(
            builder: (context, setState) {
              return Container(
                  height: MediaQuery.of(context).size.height * 0.85,
                  decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  child: Column(children: [
                    Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: primaryColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
                        child: TextField(
                            controller: searchCtrl,
                            autofocus: true,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                                hintText: _isReturnMode ? "Search SOLD Items..." : "Search Stock...",
                                hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                                prefixIcon: const Icon(Icons.search, color: Colors.white),
                                border: InputBorder.none,
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.1)
                            ),
                            onChanged: (val) => setState(() {})
                        )
                    ),
                    Expanded(
                        child: Consumer<DbService>(
                            builder: (context, db, _) {
                              Future<List<Product>> searchFuture;

                              if (_isReturnMode) {
                                if (searchCtrl.text.isEmpty) {
                                  searchFuture = Future.value([]);
                                } else {
                                  // --- FILTER: ONLY SOLD MOBILES (Qty 0) OR ACCESSORIES ---
                                  searchFuture = db.isar.products.filter()
                                      .group((q) => q
                                      .nameContains(searchCtrl.text, caseSensitive: false)
                                      .or()
                                      .imeiContains(searchCtrl.text)
                                  )
                                      .and()
                                      .group((q) => q
                                      .quantityEqualTo(0) // SOLD PHONES
                                      .or()
                                      .isMobileEqualTo(false) // ACCESSORIES (Can return anytime)
                                  )
                                      .findAll();
                                }
                              } else {
                                searchFuture = db.searchProducts(searchCtrl.text).first;
                              }

                              return FutureBuilder<List<Product>>(
                                  future: searchFuture,
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData) return const Center(child: Text("Start typing to search..."));
                                    var list = snapshot.data!;

                                    return ListView.separated(
                                        padding: const EdgeInsets.all(12),
                                        itemCount: list.length,
                                        separatorBuilder: (_, __) => const Divider(height: 1),
                                        itemBuilder: (ctx, i) {
                                          final p = list[i];
                                          return ListTile(
                                              leading: Icon(p.isMobile ? Icons.phone_android : Icons.headphones, color: _isReturnMode ? Colors.red : Colors.grey),
                                              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                              subtitle: Text("${p.brand} ${p.imei != null ? 'IMEI: ${p.imei}' : ''}\nQty: ${p.quantity}"),
                                              trailing: Text("Rs ${p.sellPrice.toInt()}", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                                              onTap: () {
                                                // --- CRITICAL FIX: FORCE QTY 1 IF RETURNING SOLD ITEM ---
                                                if (_isReturnMode && p.quantity == 0) {
                                                  p.quantity = 1;
                                                }
                                                Provider.of<CartService>(context, listen: false).addToCart(p);
                                                Navigator.pop(ctx);
                                              }
                                          );
                                        }
                                    );
                                  }
                              );
                            }
                        )
                    )
                  ])
              );
            }
        )
    );
  }

  // --- CHECKOUT LOGIC: HIDE BANK IF NO ACCOUNTS ---
  void _showDetailedCheckoutDialog(CartService cart) async {
    double tradeInVal = double.tryParse(tradePriceCtrl.text) ?? 0;
    double netPayable = cart.total - tradeInVal;

    final db = Provider.of<DbService>(context, listen: false);
    final accounts = await db.getPaymentAccounts();
    // Logic: Only show extra tabs if there's more than just "Cash Drawer"
    bool hasBankAccounts = accounts.length > 1;

    String paymentMode = "Cash";
    final cashCtrl = TextEditingController(text: netPayable.toInt().toString());
    final bankCtrl = TextEditingController(text: "0");
    final bankNameCtrl = TextEditingController();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          double cash = double.tryParse(cashCtrl.text) ?? 0;
          double bank = double.tryParse(bankCtrl.text) ?? 0;
          double totalPaid = (paymentMode == "Split") ? (cash + bank) : (paymentMode == "Cash" ? cash : bank);
          double balance = netPayable - totalPaid;

          return AlertDialog(
            title: const Text("Checkout Payment", style: TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // CONDITIONAL TABS
                if (hasBankAccounts)
                  Row(children: [_paymentModeTab("Cash", Icons.money, paymentMode, (v) => setDialogState(() => paymentMode = v)), const SizedBox(width: 8), _paymentModeTab("Bank", Icons.account_balance, paymentMode, (v) => setDialogState(() => paymentMode = v)), const SizedBox(width: 8), _paymentModeTab("Split", Icons.call_split, paymentMode, (v) => setDialogState(() => paymentMode = v))])
                else
                  const Padding(padding: EdgeInsets.only(bottom: 15), child: Text("Mode: Cash Only (Add Banks in Settings to enable Split)", style: TextStyle(color: Colors.grey, fontSize: 11, fontStyle: FontStyle.italic))),

                const SizedBox(height: 20),

                if (paymentMode == "Cash" || paymentMode == "Split") TextField(controller: cashCtrl, keyboardType: TextInputType.number, decoration: _inputDecoration("Cash Amount", Icons.money), onChanged: (v) => setDialogState((){})),

                if (paymentMode == "Split") const SizedBox(height: 10),

                if (paymentMode == "Bank" || paymentMode == "Split") ...[
                  TextField(controller: bankCtrl, keyboardType: TextInputType.number, decoration: _inputDecoration("Bank Amount", Icons.account_balance_wallet), onChanged: (v) => setDialogState((){})),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    decoration: _inputDecoration("Select Bank", Icons.account_balance),
                    items: accounts.where((a) => a.name != "Cash Drawer").map((a) => DropdownMenuItem(value: a.name, child: Text(a.name))).toList(),
                    onChanged: (v) => bankNameCtrl.text = v ?? "",
                  )
                ],
                const SizedBox(height: 20),
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: balance > 0 ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Row(children: [Icon(balance > 0 ? Icons.warning : Icons.check_circle, color: balance > 0 ? Colors.red : Colors.green), const SizedBox(width: 10), Expanded(child: Text(balance > 0 ? "Pending: Rs ${balance.toInt()} (To Ledger)" : (balance < 0 ? "Change: Rs ${balance.abs().toInt()}" : "Fully Paid"), style: TextStyle(color: balance > 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold)))]))
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
              ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white), onPressed: () { _validateAndSubmitSale(cart, netPayable, paymentMode == "Cash" ? cash : (paymentMode == "Split" ? cash : 0), paymentMode == "Bank" ? bank : (paymentMode == "Split" ? bank : 0), bankNameCtrl.text, balance); }, child: const Text("Finalize Sale"))
            ],
          );
        },
      ),
    );
  }

  Widget _paymentModeTab(String label, IconData icon, String currentMode, Function(String) onTap) { bool isSelected = currentMode == label; return Expanded(child: InkWell(onTap: () => onTap(label), child: Container(padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: isSelected ? primaryColor : Colors.grey[200], borderRadius: BorderRadius.circular(8), border: isSelected ? Border.all(color: accentColor, width: 2) : null), child: Column(children: [Icon(icon, color: isSelected ? Colors.white : Colors.grey[600], size: 20), const SizedBox(height: 4), Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey[600], fontWeight: FontWeight.bold, fontSize: 12))])))); }

  void _validateAndSubmitSale(CartService cart, double total, double cash, double bank, String bankName, double balance) async {
    if (balance > 0) {
      if (customerCtrl.text.isEmpty) { _showModernSnackBar("Customer Name is required for Credit/Ledger!", type: "ERROR"); return; }
      final db = Provider.of<DbService>(context, listen: false);
      final existingParties = await db.searchParties(customerCtrl.text);
      if (existingParties.isNotEmpty) {
        bool? useExisting = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text("Customer Exists"), content: Text("Name '${customerCtrl.text}' already exists in ledger. Add this balance to existing account?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("No, Change Name")), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Yes, Add to Account"))]));
        if (useExisting == null || !useExisting) return;
      }
    }
    Navigator.pop(context);
    _finalizeSale(cart, total, cash, bank, bankName, balance);
  }

  void _finalizeSale(CartService cart, double total, double cash, double bank, String bankName, double balance) async {
    setState(() => isProcessing = true);
    final db = Provider.of<DbService>(context, listen: false);
    Product? tradeProduct; MobileItem? tradeItem;
    double tradeVal = double.tryParse(tradePriceCtrl.text) ?? 0;

    if (tradeVal > 0) {
      String brand = tradeBrandCtrl.text.trim();
      String category = (brand.toLowerCase().contains("apple") || brand.toLowerCase().contains("iphone")) ? "iPhone" : "Android";
      tradeProduct = Product()..name = tradeNameCtrl.text..brand = brand..imei = tradeImeiCtrl.text..costPrice = tradeVal..sellPrice = double.tryParse(tradeSellCtrl.text) ?? tradeVal..quantity = 1..isMobile = true..color = tradeColorCtrl.text..memory = tradeStorageCtrl.text..condition = tradeConditionCtrl.text.isEmpty ? "Used" : tradeConditionCtrl.text..category = category;
      tradeItem = MobileItem()..imei = tradeImeiCtrl.text..productName = tradeNameCtrl.text..status = "IN_STOCK"..specificCostPrice = tradeVal;
    }

    try {
      await db.processSale(cart.items, cart.total, cart.discount, cash, bank, bankName.isEmpty ? null : bankName, customerCtrl.text, tradeInAmount: tradeVal, tradeInDetail: tradeVal > 0 ? "${tradeNameCtrl.text} (${tradeImeiCtrl.text})" : null, tradeInProduct: tradeProduct, tradeInItem: tradeItem);
      final receipt = ReceiptData(items: List.from(cart.items), total: total + tradeVal, subtotal: cart.subtotal, discount: cart.discount, tradeInAmount: tradeVal, tradeInModel: tradeNameCtrl.text, tradeInImei: tradeImeiCtrl.text, paymentMethod: balance > 0 ? "Credit/Split" : "Paid", customerName: customerCtrl.text.isEmpty ? "Walk-in Customer" : customerCtrl.text, date: DateTime.now(), paidAmount: cash + bank, cashPaid: cash, bankPaid: bank, balanceDue: balance > 0 ? balance : 0);
      cart.clearCart(); _clearInputs(); setState(() => isProcessing = false); _showReceiptPreview(receipt);
    } catch (e) { setState(() => isProcessing = false); _showModernSnackBar("Error: $e", type: "ERROR"); }
  }

  void _clearInputs() { customerCtrl.clear(); tradeBrandCtrl.clear(); tradeNameCtrl.clear(); tradeImeiCtrl.clear(); tradePriceCtrl.clear(); tradeSellCtrl.clear(); tradeColorCtrl.clear(); tradeStorageCtrl.clear(); tradeConditionCtrl.clear(); setState(() => isTradeInExpanded = false); }
  void _showItemOptions(CartItem item, CartService cart) { showModalBottomSheet(context: context, builder: (_) => Wrap(children: [ListTile(leading: const Icon(Icons.card_giftcard, color: Colors.purple), title: Text(item.isGift ? "Remove Gift Status" : "Mark as Gift (Free)"), onTap: () { cart.toggleGift(item); Navigator.pop(context); }), ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text("Remove from Cart"), onTap: () { cart.removeFromCart(item); Navigator.pop(context); })])); }

  void _showReceiptPreview(ReceiptData data) { showDialog(context: context, builder: (ctx) => Dialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), child: Container(width: 500, height: 700, child: PdfPreview(build: (format) => _generatePdf(data, format), canChangeOrientation: false, canChangePageFormat: false, actions: [PdfPreviewAction(icon: const Icon(Icons.close), onPressed: (context, build, pageFormat) => Navigator.pop(context))])))); }

  Future<Uint8List> _generatePdf(ReceiptData data, PdfPageFormat format) async {
    final doc = pw.Document();
    doc.addPage(pw.Page(pageFormat: PdfPageFormat.roll80, build: (pw.Context context) { return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
      pw.Text("HAMII MOBILES", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.Text(shopAddress, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
      pw.Text("Tel: $shopPhone", style: const pw.TextStyle(fontSize: 10)),
      pw.Divider(),
      pw.Text(data.isReturn ? "REFUND SLIP" : "SALE RECEIPT", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: data.isReturn ? PdfColors.red : PdfColors.black)),
      pw.Text("Date: ${DateFormat('dd-MM-yyyy hh:mm a').format(data.date)}", style: const pw.TextStyle(fontSize: 10)),
      pw.Text("Customer: ${data.customerName}", style: const pw.TextStyle(fontSize: 10)),
      pw.Divider(),
      pw.ListView(children: data.items.map((item) { String itemName = item.product.name; if (item.product.isMobile && item.product.imei != null) itemName += "\n(IMEI: ${item.product.imei})"; return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Expanded(child: pw.Text("$itemName x${item.quantity}", style: const pw.TextStyle(fontSize: 10))), pw.Text(item.isGift ? "FREE" : "${(item.price * item.quantity).toInt()}", style: const pw.TextStyle(fontSize: 10))]); }).toList()),
      pw.Divider(),
      _printRow("Subtotal", data.subtotal),
      if(data.discount > 0) _printRow("Discount", -data.discount),
      if(data.tradeInAmount > 0) ...[pw.Divider(borderStyle: pw.BorderStyle.dashed), pw.Text("Trade-In Device:", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)), pw.Text("${data.tradeInModel}", style: const pw.TextStyle(fontSize: 10)), pw.Text("IMEI: ${data.tradeInImei}", style: const pw.TextStyle(fontSize: 10)), _printRow("Trade-In Value", -data.tradeInAmount)],
      pw.Divider(thickness: 1.5),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text("TOTAL", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)), pw.Text("${data.total.toInt().abs()}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14))]), // Absolute for display
      pw.SizedBox(height: 5),
      if(data.paidAmount != 0) _printRow("Amount Paid", data.paidAmount),
      if(data.balanceDue > 0) _printRow("Balance Due", data.balanceDue),
      if(data.balanceDue < 0) _printRow("Change", data.balanceDue.abs()),
      pw.SizedBox(height: 10),
      pw.Text("Thank you for shopping!", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontStyle: pw.FontStyle.italic, fontSize: 10)),
    ]); }));
    return doc.save();
  }

  pw.Widget _printRow(String label, double value) { return pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(label, style: const pw.TextStyle(fontSize: 10)), pw.Text("${value.toInt()}", style: const pw.TextStyle(fontSize: 10))]); }
}