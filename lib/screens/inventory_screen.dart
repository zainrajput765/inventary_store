import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/db_service.dart';
import '../models/schema.dart';
import 'scanner_screen.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();

  // --- CONTROLLERS ---
  final nameCtrl = TextEditingController();
  final brandCtrl = TextEditingController();
  final costCtrl = TextEditingController();
  final sellCtrl = TextEditingController();

  final colorCtrl = TextEditingController();
  final storageCtrl = TextEditingController();
  final ramCtrl = TextEditingController();
  final batteryHealthCtrl = TextEditingController();
  final conditionCtrl = TextEditingController();
  final imeiInputCtrl = TextEditingController();

  final qtyCtrl = TextEditingController(text: "1");

  List<String> scannedImeis = [];
  String ptaStatus = "PTA Approved";
  String? selectedParty;
  String paymentMode = "Cash";
  String? paymentSource = "Cash Drawer";
  String manualSourceContact = "";
  bool isSaving = false;
  bool autoAddImei = true;

  // --- COLOR SCHEME ---
  final Color primaryColor = const Color(0xFF2B3A67); // Royal Navy
  final Color accentColor = const Color(0xFFECA400); // Gold
  final Color bgColor = const Color(0xFFF3F4F6); // Soft Gray

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1) {
        brandCtrl.text = "APPLE";
      } else {
        brandCtrl.clear();
      }
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isDesktop = MediaQuery.of(context).size.width > 900;
    bool isAccessory = _tabController.index == 2;
    bool isIphone = _tabController.index == 1;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_box, color: accentColor, size: 24),
            const SizedBox(width: 10),
            const Text("Stock Entry", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        backgroundColor: primaryColor,
        centerTitle: true,
        elevation: 4,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: accentColor,
          indicatorWeight: 4,
          labelColor: accentColor,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.phone_android), text: "ANDROID"),
            Tab(icon: Icon(Icons.phone_iphone), text: "IPHONE"),
            Tab(icon: Icon(Icons.headphones), text: "ACCESSORY"),
          ],
        ),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LEFT SIDE (FORM)
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isDesktop) ...[
                      _buildStockCounterCard(),
                      const SizedBox(height: 20),
                    ],
                    _buildSectionHeader("Product Information"),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: _buildBasicDetailsForm(isIphone),
                      ),
                    ),
                    const SizedBox(height: 25),

                    if (!isAccessory) ...[
                      _buildSectionHeader(isIphone ? "iPhone Specifications" : "Android Specifications"),
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: _buildMobileSpecificForm(),
                        ),
                      ),
                      const SizedBox(height: 25),
                      _buildSectionHeader("Identification (IMEI)"),
                      Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: _buildBulkImeiSection()
                      ),
                    ] else
                      Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(padding: const EdgeInsets.all(20), child: _buildAccessoryForm())
                      ),

                    const SizedBox(height: 25),
                    _buildSectionHeader("Cost & Sourcing"),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: _buildPricingAndSourceForm(),
                      ),
                    ),

                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: accentColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 4,
                        ),
                        onPressed: isSaving ? null : _saveInventory,
                        icon: const Icon(Icons.check_circle),
                        label: isSaving
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text("CONFIRM & SAVE STOCK", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ),
                    ),
                    const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
          ),

          // RIGHT SIDE (DESKTOP ONLY - SCANNED LIST)
          if (isDesktop && !isAccessory)
            Expanded(
              flex: 2,
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStockCounterCard(),
                    const Divider(height: 40),
                    Text("Scanned Units", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: primaryColor)),
                    const SizedBox(height: 10),
                    Expanded(
                      child: scannedImeis.isEmpty
                          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.qr_code_2, size: 60, color: Colors.grey), const SizedBox(height: 10), Text("Ready to scan", style: TextStyle(color: Colors.grey[400]))]))
                          : ListView.separated(
                        itemCount: scannedImeis.length,
                        separatorBuilder: (_,__) => const Divider(),
                        itemBuilder: (ctx, i) => ListTile(
                          leading: const Icon(Icons.check_circle, color: Colors.green),
                          title: Text(scannedImeis[i], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: scannedImeis[i].contains("/") ? const Text("Dual SIM", style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)) : null,
                          trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () => setState(() => scannedImeis.removeAt(i))),
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),

        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryColor)),
    );
  }

  Widget _buildStockCounterCard() {
    int count = _tabController.index == 2 ? (int.tryParse(qtyCtrl.text) ?? 1) : scannedImeis.length;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor, const Color(0xFF512DA8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("New Units", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                Text("Adding Stock", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))
              ]
          ),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(12)),
              child: Text("$count", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))
          )
        ],
      ),
    );
  }

  Widget _buildBasicDetailsForm(bool isIphone) {
    return Column(children: [
      Consumer<DbService>(
          builder: (context, db, _) {
            return Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) async {
                if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
                final products = await db.searchProducts(textEditingValue.text).first;
                return products.map((e) => e.name).toSet().toList();
              },
              onSelected: (String selection) { nameCtrl.text = selection; },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                if(controller.text != nameCtrl.text) controller.text = nameCtrl.text;
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: "MODEL NAME", hintText: "e.g. 15 PRO MAX", prefixIcon: Icon(Icons.phone_android)),
                  validator: (v) => v!.isEmpty ? "Required" : null,
                  onChanged: (val) => nameCtrl.text = val,
                );
              },
            );
          }
      ),
      const SizedBox(height: 15),
      if (!isIphone)
        TextFormField(controller: brandCtrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: "BRAND NAME", hintText: "e.g. SAMSUNG", prefixIcon: Icon(Icons.branding_watermark)), validator: (v) => v!.isEmpty ? "Required" : null)
      else
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
          child: const Text("BRAND: APPLE", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
        )
    ]);
  }

  Widget _buildMobileSpecificForm() {
    return Column(
      children: [
        Row(children: [
          Expanded(child: TextFormField(controller: colorCtrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: "COLOR", prefixIcon: Icon(Icons.color_lens)))),
          const SizedBox(width: 15),
          Expanded(child: TextFormField(controller: storageCtrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: "STORAGE (GB)", prefixIcon: Icon(Icons.sd_storage))))
        ]),
        const SizedBox(height: 15),
        Row(children: [
          Expanded(child: TextFormField(controller: conditionCtrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: "CONDITION (10/10)", prefixIcon: Icon(Icons.star)))),
          const SizedBox(width: 15),
          Expanded(
              child: DropdownButtonFormField<String>(
                  value: ptaStatus,
                  isExpanded: true, // Fix for Overflow
                  decoration: const InputDecoration(labelText: "PTA STATUS", prefixIcon: Icon(Icons.verified_user)),
                  items: const ["PTA Approved", "Non-PTA", "JV / Locked"].map((e) => DropdownMenuItem(value: e, child: Text(e.toUpperCase(), overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setState(() => ptaStatus = v!)
              )
          )
        ]),
        const SizedBox(height: 15),
        if (_tabController.index == 1)
          TextFormField(controller: batteryHealthCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "BATTERY HEALTH %", prefixIcon: Icon(Icons.battery_std)))
        else
          TextFormField(controller: ramCtrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: "RAM", prefixIcon: Icon(Icons.memory))),
      ],
    );
  }

  Widget _buildBulkImeiSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("SCAN OR TYPE IMEI", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700])),
              Row(
                children: [
                  const Text("AUTO-ADD", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  Switch(value: autoAddImei, onChanged: (val) => setState(() => autoAddImei = val), activeColor: primaryColor),
                ],
              )
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: imeiInputCtrl,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9/\- ]'))],
                  decoration: const InputDecoration(hintText: "ENTER IMEI...", prefixIcon: Icon(Icons.qr_code)),
                  onSubmitted: (val) {
                    if (autoAddImei && val.isNotEmpty && !scannedImeis.contains(val)) {
                      setState(() { scannedImeis.add(val); imeiInputCtrl.clear(); });
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(style: IconButton.styleFrom(backgroundColor: primaryColor), icon: Icon(Icons.add, color: accentColor), onPressed: () { final val = imeiInputCtrl.text; if (val.isNotEmpty && !scannedImeis.contains(val)) { setState(() { scannedImeis.add(val); imeiInputCtrl.clear(); }); } }),
              const SizedBox(width: 5),
              IconButton.filledTonal(
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: () async {
                  final code = await Navigator.push(context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
                  if (code != null) {
                    if (!autoAddImei) {
                      imeiInputCtrl.text = imeiInputCtrl.text.isEmpty ? code : "${imeiInputCtrl.text} / $code";
                    } else if (!scannedImeis.contains(code)) {
                      setState(() => scannedImeis.add(code));
                    }
                  }
                },
              )
            ],
          ),
          if (scannedImeis.isNotEmpty) ...[const SizedBox(height: 15), Wrap(spacing: 8, runSpacing: 8, children: scannedImeis.map((imei) => Chip(label: Text(imei), deleteIcon: const Icon(Icons.close, size: 16), onDeleted: () => setState(() => scannedImeis.remove(imei)))).toList())]
        ],
      ),
    );
  }

  Widget _buildAccessoryForm() { return TextFormField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "TOTAL QUANTITY", prefixIcon: Icon(Icons.inventory_2))); }

  Widget _buildPricingAndSourceForm() {
    return Column(
      children: [
        Row(children: [
          Expanded(child: TextFormField(controller: costCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "COST PRICE (BUY)", prefixText: "Rs ", prefixIcon: Icon(Icons.arrow_downward)), validator: (v) => (v == null || v.isEmpty) ? "Required" : null)),
          const SizedBox(width: 15),
          Expanded(child: TextFormField(controller: sellCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "SELL PRICE", prefixText: "Rs ", prefixIcon: Icon(Icons.arrow_upward)), validator: (v) => (v == null || v.isEmpty) ? "Required" : null))
        ]),
        const SizedBox(height: 15),
        FutureBuilder<List<Party>>(
          future: Provider.of<DbService>(context, listen: false).getSuppliers(),
          builder: (context, snapshot) {
            return DropdownButtonFormField<String>(
                value: selectedParty,
                isExpanded: true,
                decoration: const InputDecoration(labelText: "PURCHASED FROM (DEALER)", prefixIcon: Icon(Icons.store)),
                items: (snapshot.data ?? []).map((s) => DropdownMenuItem(value: s.id.toString(), child: Text(s.name.toUpperCase(), overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (val) => setState(() => selectedParty = val)
            );
          },
        ),
        if (selectedParty == null) ...[const SizedBox(height: 15), TextFormField(initialValue: manualSourceContact, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: "MANUAL SOURCE NAME", prefixIcon: Icon(Icons.person_outline)), onChanged: (v) => manualSourceContact = v)],
        const SizedBox(height: 15),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(value: paymentMode, decoration: const InputDecoration(labelText: "PAYMENT MODE", prefixIcon: Icon(Icons.payment)), items: const ["Cash", "Credit"].map((e) => DropdownMenuItem(value: e, child: Text(e.toUpperCase()))).toList(), onChanged: (val) => setState(() => paymentMode = val!))),
          const SizedBox(width: 15),
          if (paymentMode == 'Cash') Expanded(child: FutureBuilder<List<PaymentAccount>>(future: Provider.of<DbService>(context, listen: false).getPaymentAccounts(), builder: (context, snapshot) { return DropdownButtonFormField<String>(value: paymentSource, isExpanded: true, decoration: const InputDecoration(labelText: "PAID FROM", prefixIcon: Icon(Icons.account_balance_wallet)), items: (snapshot.data ?? []).map((a) => DropdownMenuItem(value: a.name, child: Text(a.name.toUpperCase(), overflow: TextOverflow.ellipsis))).toList(), onChanged: (val) => paymentSource = val); })) else const Spacer()
        ]),
      ],
    );
  }

  void _saveInventory() async {
    if (!_formKey.currentState!.validate()) return;
    if (paymentMode == "Credit" && selectedParty == null) { _showErrorPopup("For Credit Purchases, please select a registered Supplier."); return; }
    if (_tabController.index != 2 && scannedImeis.isEmpty) { _showErrorPopup("Please scan at least one IMEI."); return; }

    setState(() => isSaving = true);
    final db = Provider.of<DbService>(context, listen: false);

    double cost = double.tryParse(costCtrl.text.replaceAll(',', '')) ?? 0;
    double sell = double.tryParse(sellCtrl.text.replaceAll(',', '')) ?? 0;
    int qty = int.tryParse(qtyCtrl.text) ?? 1;

    String category = _tabController.index == 0 ? "Android" : (_tabController.index == 1 ? "iPhone" : "Accessory");
    int? partyId = selectedParty != null ? int.parse(selectedParty!) : null;
    String sourceName = "Walk-In";

    if (partyId != null) {
      var suppliers = await db.getSuppliers();
      sourceName = suppliers.firstWhere((s) => s.id == partyId, orElse: () => Party()..name="Dealer").name;
    } else if (manualSourceContact.isNotEmpty) sourceName = manualSourceContact;

    List<Product> productsToAdd = [];
    String brand = _tabController.index == 1 ? "APPLE" : brandCtrl.text.toUpperCase();

    if (category == "Accessory") {
      productsToAdd.add(Product()..name = nameCtrl.text.toUpperCase()..brand = brand..category = "Accessory"..quantity = qty..costPrice = cost..sellPrice = sell..isMobile = false..sourceContact = sourceName);
    } else {
      for (String imei in scannedImeis) {
        final p = Product()..name = nameCtrl.text.toUpperCase()..brand = brand..category = category..quantity = 1..costPrice = cost..sellPrice = sell..isMobile = true..sourceContact = sourceName..imei = imei..ptaStatus = ptaStatus..color = colorCtrl.text.toUpperCase()..memory = storageCtrl.text.toUpperCase()..condition = conditionCtrl.text.toUpperCase();
        if (category == "iPhone") p.batteryHealth = batteryHealthCtrl.text; else p.ram = ramCtrl.text.toUpperCase();
        productsToAdd.add(p);
      }
    }

    try {
      for (var p in productsToAdd) {
        await db.addProduct(p, partyId: partyId, partyName: sourceName, paymentMode: paymentMode, paymentSource: paymentSource, costTotal: p.costPrice * p.quantity);
      }
      if (mounted) { setState(() => isSaving = false); _showSuccessPopup(productsToAdd.length); }
    } catch (e) {
      if (mounted) { setState(() => isSaving = false); _showErrorPopup("Error: ${e.toString()}"); }
    }
  }

  void _showSuccessPopup(int count) { showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(content: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.check_circle, color: Colors.green, size: 60), const SizedBox(height: 20), Text("Success!", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primaryColor)), Text("$count items added."), const SizedBox(height: 20), ElevatedButton(onPressed: () { Navigator.pop(ctx); _resetForm(); }, child: const Text("OK"))]))); }
  void _showErrorPopup(String msg) { showDialog(context: context, builder: (ctx) => AlertDialog(content: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.error, color: Colors.red, size: 60), const SizedBox(height: 10), Text(msg, textAlign: TextAlign.center), const SizedBox(height: 20), ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))]))); }
  void _resetForm() { setState(() { scannedImeis.clear(); imeiInputCtrl.clear(); nameCtrl.clear(); brandCtrl.clear(); costCtrl.clear(); sellCtrl.clear(); colorCtrl.clear(); storageCtrl.clear(); conditionCtrl.clear(); ramCtrl.clear(); batteryHealthCtrl.clear(); qtyCtrl.text = "1"; }); }
}