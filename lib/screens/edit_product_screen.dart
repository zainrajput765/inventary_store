import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/db_service.dart';
import '../models/schema.dart';

class EditProductScreen extends StatefulWidget {
  final Product product;
  const EditProductScreen({super.key, required this.product});

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  final _formKey = GlobalKey<FormState>();

  final nameCtrl = TextEditingController();
  final brandCtrl = TextEditingController();
  final costCtrl = TextEditingController();
  final sellCtrl = TextEditingController();
  final qtyCtrl = TextEditingController();

  final colorCtrl = TextEditingController();
  final storageCtrl = TextEditingController();
  final ramCtrl = TextEditingController();
  final batteryHealthCtrl = TextEditingController();
  final conditionCtrl = TextEditingController();
  final imeiCtrl = TextEditingController();

  String _ptaStatus = 'PTA Approved';
  late bool isMobile;
  late String category;

  // MAIN APP COLORS
  final Color primaryColor = const Color(0xFF2B3A67);
  final Color secondaryColor = const Color(0xFFECA400);
  final Color bgColor = const Color(0xFFF3F4F6);

  @override
  void initState() {
    super.initState();
    _loadCurrentData();
  }

  void _loadCurrentData() {
    final p = widget.product;
    isMobile = p.isMobile;
    category = p.category;

    nameCtrl.text = p.name;
    brandCtrl.text = p.brand;
    costCtrl.text = p.costPrice.toInt().toString();
    sellCtrl.text = p.sellPrice.toInt().toString();
    qtyCtrl.text = p.quantity.toString();

    if (isMobile) {
      imeiCtrl.text = p.imei ?? "";
      colorCtrl.text = p.color ?? "";
      storageCtrl.text = p.memory ?? "";
      ramCtrl.text = p.ram ?? "";
      conditionCtrl.text = p.condition ?? "";
      batteryHealthCtrl.text = p.batteryHealth ?? "";
      _ptaStatus = p.ptaStatus ?? "PTA Approved";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text("Edit Details"),
        backgroundColor: primaryColor,
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildCard(
                child: Column(
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryColor),
                      decoration: _inputDec("Product Name", Icons.edit),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(child: _field(brandCtrl, "Brand", Icons.branding_watermark)),
                        const SizedBox(width: 15),
                        Expanded(child: _field(qtyCtrl, "Quantity", Icons.inventory_2, isNumber: true)),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 20),

              _buildCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Pricing", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600], fontSize: 12)),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: costCtrl,
                            readOnly: true,
                            style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                            decoration: _inputDec("Cost (Locked)", Icons.lock_outline, color: Colors.grey),
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(child: _field(sellCtrl, "Sell Price", Icons.attach_money, isNumber: true, color: Colors.green)),
                      ],
                    ),
                  ],
                ),
              ),

              if (isMobile) ...[
                const SizedBox(height: 20),
                _buildCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Specifications", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600], fontSize: 12)),
                      const SizedBox(height: 15),
                      TextFormField(
                        controller: imeiCtrl,
                        readOnly: true,
                        style: const TextStyle(color: Colors.grey, letterSpacing: 1),
                        decoration: _inputDec("IMEI (Locked)", Icons.qr_code, color: Colors.grey),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(child: _field(colorCtrl, "Color", Icons.color_lens)),
                          const SizedBox(width: 15),
                          Expanded(child: _field(storageCtrl, "Storage", Icons.sd_storage)),
                        ],
                      ),
                      const SizedBox(height: 15),

                      Row(
                        children: [
                          Expanded(child: _field(conditionCtrl, "Condition", Icons.star)),
                          const SizedBox(width: 15),

                          // --- ATTRACTIVE DROPDOWN ---
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                                boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _ptaStatus,
                                  isExpanded: true,
                                  icon: Icon(Icons.keyboard_arrow_down, color: primaryColor),
                                  style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 14),
                                  items: const ["PTA Approved", "Non-PTA", "JV / Locked"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                  onChanged: (v) => setState(() => _ptaStatus = v!),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 15),
                      if (category == 'iPhone')
                        _field(batteryHealthCtrl, "Battery Health %", Icons.battery_std)
                      else
                        _field(ramCtrl, "RAM", Icons.memory),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 5,
                    shadowColor: primaryColor.withOpacity(0.3),
                  ),
                  onPressed: _saveChanges,
                  icon: const Icon(Icons.save_as),
                  label: const Text("SAVE CHANGES", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: child,
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon, {bool isNumber = false, bool isReadOnly = false, Color? color}) {
    return TextFormField(
      controller: ctrl,
      readOnly: isReadOnly,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: isReadOnly ? Colors.grey : Colors.black87),
      decoration: _inputDec(label, icon, color: color),
    );
  }

  InputDecoration _inputDec(String label, IconData icon, {Color? color}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: color ?? primaryColor),
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: primaryColor, width: 2)),
      filled: true,
      fillColor: Colors.white,
      isDense: true,
    );
  }

  void _saveChanges() {
    if (!_formKey.currentState!.validate()) return;
    final db = Provider.of<DbService>(context, listen: false);

    widget.product.name = nameCtrl.text.toUpperCase();
    widget.product.brand = brandCtrl.text.toUpperCase();
    widget.product.sellPrice = double.tryParse(sellCtrl.text) ?? 0;
    widget.product.quantity = int.tryParse(qtyCtrl.text) ?? 0;

    if (isMobile) {
      widget.product.color = colorCtrl.text.toUpperCase();
      widget.product.memory = storageCtrl.text.toUpperCase();
      widget.product.ram = ramCtrl.text.toUpperCase();
      widget.product.condition = conditionCtrl.text.toUpperCase();
      widget.product.batteryHealth = batteryHealthCtrl.text;
      widget.product.ptaStatus = _ptaStatus;
    }

    db.updateProduct(widget.product).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Product Updated Successfully!")));
      Navigator.pop(context);
    });
  }
}