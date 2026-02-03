import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/db_service.dart';
import '../models/schema.dart';
import 'edit_product_screen.dart';
import 'scanner_screen.dart';

class StockListScreen extends StatefulWidget {
  final int initialIndex;
  const StockListScreen({super.key, this.initialIndex = 0});

  @override
  State<StockListScreen> createState() => _StockListScreenState();
}

class _StockListScreenState extends State<StockListScreen> {
  final searchCtrl = TextEditingController();
  String searchQuery = "";

  // COLOR SCHEME
  final Color primaryColor = const Color(0xFF2B3A67);
  final Color accentColor = const Color(0xFFECA400);
  final Color bgColor = const Color(0xFFF3F4F6);

  void _showModernSnackBar(String message, {String type = "SUCCESS"}) {
    Color bg;
    Color textColor;
    IconData icon;
    String title;

    switch (type) {
      case "ERROR":
        bg = const Color(0xFFF2DEDE);
        textColor = const Color(0xFFA94442);
        icon = Icons.cancel;
        title = "Error!";
        break;
      case "WARNING":
        bg = const Color(0xFFFCF8E3);
        textColor = const Color(0xFF8A6D3B);
        icon = Icons.warning_amber_rounded;
        title = "Warning!";
        break;
      case "INFO":
        bg = const Color(0xFFD9EDF7);
        textColor = const Color(0xFF31708F);
        icon = Icons.info;
        title = "Info!";
        break;
      default:
        bg = const Color(0xFFDFF0D8);
        textColor = const Color(0xFF3C763D);
        icon = Icons.check_circle;
        title = "Success!";
    }

    bool isDesktop = MediaQuery.of(context).size.width > 800;

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
        width: isDesktop ? 400 : null,
        margin: isDesktop ? null : const EdgeInsets.only(bottom: 20, left: 20, right: 20),
        elevation: 0,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialIndex,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: primaryColor,
          elevation: 4,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2, color: accentColor, size: 24),
              const SizedBox(width: 10),
              const Text("Stock Inventory", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5, color: Colors.white)),
            ],
          ),
          centerTitle: true,
          bottom: TabBar(
            indicatorColor: accentColor,
            indicatorWeight: 4,
            labelColor: accentColor,
            unselectedLabelColor: Colors.white60,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: const [
              Tab(text: "ANDROID", icon: Icon(Icons.phone_android)),
              Tab(text: "IPHONE", icon: Icon(Icons.phone_iphone)),
              Tab(text: "ACCESSORY", icon: Icon(Icons.headphones)),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.qr_code_scanner, color: accentColor),
              onPressed: () async {
                final code = await Navigator.push(context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
                if (code != null) {
                  searchCtrl.text = code;
                  setState(() => searchQuery = code);
                  _showModernSnackBar("Scanned: $code", type: "INFO");
                }
              },
            )
          ],
        ),
        body: Column(
          children: [
            const SizedBox(height: 15),
            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: TextField(
                  controller: searchCtrl,
                  style: const TextStyle(color: Colors.black87),
                  decoration: InputDecoration(
                    hintText: "Search Name, IMEI, Brand...",
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    prefixIcon: Icon(Icons.search, color: primaryColor),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear, color: Colors.grey), onPressed: () { searchCtrl.clear(); setState(() => searchQuery = ""); })
                        : null,
                  ),
                  onChanged: (val) => setState(() => searchQuery = val),
                ),
              ),
            ),
            const SizedBox(height: 15),

            // Stock Grid - Using AutomaticKeepAlive to fix reloading issue
            Expanded(
              child: TabBarView(
                children: [
                  StockTab(category: "Android", searchQuery: searchQuery, parent: this),
                  StockTab(category: "iPhone", searchQuery: searchQuery, parent: this),
                  StockTab(category: "Accessory", searchQuery: searchQuery, parent: this),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- NEW WIDGET: SEPARATED TAB TO HANDLE KEEP ALIVE STATE ---
class StockTab extends StatefulWidget {
  final String category;
  final String searchQuery;
  final _StockListScreenState parent; // To access parent methods like _showModernSnackBar

  const StockTab({super.key, required this.category, required this.searchQuery, required this.parent});

  @override
  State<StockTab> createState() => _StockTabState();
}

class _StockTabState extends State<StockTab> with AutomaticKeepAliveClientMixin {
  // This boolean ensures the tab state is preserved when switching tabs
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for KeepAlive

    final db = Provider.of<DbService>(context);
    double screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = screenWidth > 800 ? 2 : 1;
    double childAspectRatio = screenWidth > 800 ? 3.5 : 2.5;

    return StreamBuilder<List<Product>>(
      // Removed .asBroadcastStream() to potentially fix initial load flicker, Isar streams are robust.
      stream: db.searchProducts(widget.searchQuery),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final allList = snapshot.data!;

        final filteredList = allList.where((p) {
          if (widget.category == "Accessory") return p.category == "Accessory";
          if (widget.category == "iPhone") return p.category == "iPhone";
          return p.category == "Android";
        }).toList();

        final stockList = filteredList.where((p) => p.quantity > 0).toList();

        if (stockList.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inventory_2_outlined, size: 60, color: Colors.grey[300]),
                const SizedBox(height: 15),
                Text("No Items Found", style: TextStyle(color: Colors.grey[500], fontSize: 16, fontWeight: FontWeight.w500)),
              ],
            ),
          );
        }

        // --- GRID/LIST CONFIGURATION ---
        if (widget.category == "Accessory") {
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: stockList.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: childAspectRatio,
            ),
            itemBuilder: (context, index) {
              final p = stockList[index];
              return _buildUnifiedCard(
                  name: p.name,
                  subtitle: "Rs ${p.sellPrice.toInt()}",
                  qty: p.quantity,
                  icon: Icons.headphones,
                  isLowStock: p.quantity < 5,
                  onTap: () => _showProductDetail(p)
              );
            },
          );
        } else {
          // Phone Grouping Logic
          Map<String, List<Product>> grouped = {};
          for (var p in stockList) {
            grouped.putIfAbsent(p.name, () => []).add(p);
          }
          final groupKeys = grouped.keys.toList();

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: groupKeys.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: childAspectRatio,
            ),
            itemBuilder: (context, index) {
              String name = groupKeys[index];
              List<Product> items = grouped[name]!;
              int totalQty = items.fold(0, (sum, item) => sum + item.quantity);

              return _buildUnifiedCard(
                  name: name,
                  subtitle: items.first.brand, // Brand as subtitle
                  qty: totalQty,
                  icon: Icons.phone_android,
                  isLowStock: false,
                  onTap: () => _showGroupDetails(name, items)
              );
            },
          );
        }
      },
    );
  }

  // --- WIDGETS COPIED FOR THE NEW CLASS ---

  Widget _buildUnifiedCard({
    required String name,
    required String subtitle,
    required int qty,
    required IconData icon,
    required bool isLowStock,
    required VoidCallback onTap
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 3))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: widget.parent.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)
                  ),
                  child: Icon(icon, color: widget.parent.primaryColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: widget.parent.primaryColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: isLowStock ? Colors.redAccent.withOpacity(0.1) : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(20)
                  ),
                  child: Text(
                    isLowStock ? "Low: $qty" : "Qty: $qty",
                    style: TextStyle(
                        color: isLowStock ? Colors.red : widget.parent.primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Colors.grey, size: 20)
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showGroupDetails(String name, List<Product> items) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          children: [
            Text("$name - Available Units", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: widget.parent.primaryColor)),
            const Divider(),
            Expanded(
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_,__) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final p = items[index];
                  return ListTile(
                    leading: const Icon(Icons.qr_code, color: Colors.grey),
                    title: Text("IMEI: ${p.imei ?? 'N/A'}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("${p.color} | ${p.memory} | ${p.condition}"),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showProductDetail(p);
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

  void _showProductDetail(Product p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: widget.parent.primaryColor.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(p.isMobile ? Icons.phone_android : Icons.headphones, color: widget.parent.primaryColor, size: 30),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: widget.parent.primaryColor)),
                      Text(p.brand, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 40),
            Row(children: [Expanded(child: _detailItem("Category", p.category)), Expanded(child: _detailItem("Stock", "${p.quantity}", isPositive: p.quantity > 0))]),
            const SizedBox(height: 15),
            if (p.isMobile) ...[
              Row(children: [Expanded(child: _detailItem("Color", p.color ?? "-")), Expanded(child: _detailItem("Storage", p.memory ?? "-"))]),
              const SizedBox(height: 15),
              Row(children: [Expanded(child: _detailItem("IMEI", p.imei ?? "-")), Expanded(child: _detailItem("PTA", p.ptaStatus ?? "-"))]),
              const SizedBox(height: 15),
            ],
            const Divider(height: 30),
            Row(
              children: [
                Expanded(child: _priceBox("Cost (Locked)", p.costPrice, Colors.grey)),
                const SizedBox(width: 15),
                Expanded(child: _priceBox("Selling Price", p.sellPrice, widget.parent.accentColor)),
              ],
            ),
            const SizedBox(height: 30),
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmDelete(p),
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        label: const Text("Delete"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          side: BorderSide(color: Colors.red.withOpacity(0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(context, MaterialPageRoute(builder: (_) => EditProductScreen(product: p)));
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text("Edit Details"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.parent.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showReturnToDealerDialog(p);
                    },
                    icon: const Icon(Icons.undo, color: Colors.orange),
                    label: const Text("Return to Dealer"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      side: BorderSide(color: Colors.orange.withOpacity(0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // --- HELPER DIALOGS ---
  void _showReturnToDealerDialog(Product p) {
    final qtyCtrl = TextEditingController(text: "1");
    final refundCtrl = TextEditingController(text: p.costPrice.toInt().toString());
    final dealerNameCtrl = TextEditingController(text: p.sourceContact ?? "");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Return to Dealer"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("This will remove stock and adjust dealer balance.", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 15),
            if (!p.isMobile)
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Quantity to Return"),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: refundCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Refund Amount (Cost)"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: dealerNameCtrl,
              decoration: const InputDecoration(labelText: "Dealer Name"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            onPressed: () {
              double refund = double.tryParse(refundCtrl.text) ?? 0;
              int qty = int.tryParse(qtyCtrl.text) ?? 1;
              String dealer = dealerNameCtrl.text;

              if (dealer.isEmpty) {
                widget.parent._showModernSnackBar("Please enter Dealer Name", type: "ERROR");
                return;
              }

              final db = Provider.of<DbService>(context, listen: false);
              for(int i=0; i<qty; i++) {
                db.processReturn(
                    productName: p.name,
                    refundAmount: refund / qty,
                    originalCost: p.costPrice,
                    customerName: dealer,
                    productId: p.id,
                    imei: p.imei,
                    isDealerReturn: true
                );
              }

              Navigator.pop(ctx);
              widget.parent._showModernSnackBar("Returned to $dealer successfully", type: "SUCCESS");
            },
            child: const Text("Confirm Return"),
          )
        ],
      ),
    );
  }

  Widget _detailItem(String label, String value, {bool? isPositive}) {
    Color valColor = Colors.black87;
    if (isPositive != null) valColor = isPositive ? Colors.green : Colors.red;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: valColor)),
    ]);
  }

  Widget _priceBox(String label, double price, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
          Text("Rs ${price.toInt()}", style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _confirmDelete(Product p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Delete"),
        content: Text("Are you sure you want to remove ${p.name}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Provider.of<DbService>(context, listen: false).deleteProduct(p.id);
              Navigator.pop(ctx);
              Navigator.pop(context);
              widget.parent._showModernSnackBar("${p.name} has been deleted.", type: "SUCCESS");
            },
            child: const Text("Delete"),
          )
        ],
      ),
    );
  }
}