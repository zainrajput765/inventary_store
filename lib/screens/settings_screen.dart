import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:isar/isar.dart';
import '../services/db_service.dart';
import '../models/schema.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  // --- HELPER: Web-Style "Toast" Snackbar ---
  void _showModernSnackBar(BuildContext context, String message, {String type = "SUCCESS"}) {
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
  Widget build(BuildContext context) {
    final db = Provider.of<DbService>(context);

    // --- REQUESTED COLOR SCHEME ---
    const primaryColor = Color(0xFF2B3A67); // Royal Navy
    const secondaryColor = Color(0xFFECA400); // Gold
    const bgColor = Color(0xFFF3F4F6); // Soft Gray

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text("Settings", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 4,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 10),
          _buildSectionHeader(context, "Financial Management", primaryColor),
          _buildSettingsCard(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.teal.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.account_balance, color: Colors.teal),
                ),
                title: const Text("Payment Accounts", style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("Manage Banks, Wallets & Cash Sources"),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () => _showPaymentAccountsDialog(context, db, primaryColor, secondaryColor),
              ),
            ],
          ),

          const SizedBox(height: 25),
          _buildSectionHeader(context, "Security & Access", primaryColor),
          _buildSettingsCard(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.lock, color: primaryColor),
                ),
                title: const Text("Change Admin PIN", style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("Default: 0000"),
                onTap: () => _showChangePinDialog(context, db, true, primaryColor, secondaryColor),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.badge, color: primaryColor),
                ),
                title: const Text("Change Staff PIN", style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("Default: 1111"),
                onTap: () => _showChangePinDialog(context, db, false, primaryColor, secondaryColor),
              ),
            ],
          ),

          const SizedBox(height: 25),
          _buildSectionHeader(context, "Data Management", primaryColor),
          _buildSettingsCard(
            children: [
              // --- UPDATED BACKUP BUTTON (SAVE TO LOCAL) ---
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.save_alt, color: Colors.blue), // Icon changed to Save
                ),
                title: const Text("Save Backup Locally", style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("Save database file to your device"),
                onTap: () async {
                  try {
                    // 1. Create the backup file internally
                    String internalPath = await db.createBackup();

                    // 2. Open "Save As" dialog for the user to pick location
                    String? outputFile = await FilePicker.platform.saveFile(
                      dialogTitle: 'Select Location to Save Backup',
                      fileName: 'hassan_backup_${DateTime.now().millisecondsSinceEpoch}.isar',
                    );

                    // 3. If user picked a location, copy the file there
                    if (outputFile != null) {
                      await File(internalPath).copy(outputFile);
                      if (context.mounted) {
                        _showModernSnackBar(context, "Backup Saved Successfully!", type: "SUCCESS");
                      }
                    } else {
                      // User cancelled the picker
                    }
                  } catch (e) {
                    if (context.mounted) _showModernSnackBar(context, "Backup Failed: $e", type: "ERROR");
                  }
                },
              ),
              const Divider(height: 1),

              // --- RESTORE BUTTON (UNCHANGED) ---
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.cloud_download, color: Colors.orange),
                ),
                title: const Text("Restore Data", style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("Import database from file"),
                onTap: () async {
                  FilePickerResult? result = await FilePicker.platform.pickFiles();
                  if (result != null) {
                    try {
                      await db.restoreBackup(result.files.single.path!);
                      if (context.mounted) _showModernSnackBar(context, "Data Restored Successfully!", type: "SUCCESS");
                    } catch (e) {
                      if (context.mounted) _showModernSnackBar(context, "Restore Failed: $e", type: "ERROR");
                    }
                  }
                },
              ),
              const Divider(height: 1),

              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.delete_forever, color: Colors.redAccent),
                ),
                title: const Text("Factory Reset", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                subtitle: const Text("Wipe all data permanently"),
                onTap: () => _confirmReset(context, db),
              ),
            ],
          ),

          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                const Text("HASSAN MOBILES", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.grey)),
                const SizedBox(height: 5),
                Text("Version 2.0 (Local Offline)", style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                const SizedBox(height: 15),
                // --- YOUR BRANDING HERE ---
                const Text(
                    "Manufactured by Zedech",
                    style: TextStyle(
                        color: Color(0xFF2B3A67), // Use your primary color
                        fontWeight: FontWeight.bold,
                        fontSize: 13
                    )
                ),
                const SizedBox(height: 20),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5)),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Column(children: children),
    );
  }

  // --- COMPACT DIALOGS ---

  void _showPaymentAccountsDialog(BuildContext context, DbService db, Color primary, Color secondary) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Payment Accounts", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))
                  ],
                ),
                const Divider(),
                Expanded(
                  child: FutureBuilder<List<PaymentAccount>>(
                    future: db.getPaymentAccounts(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      final accounts = snapshot.data!;
                      return ListView.separated(
                        itemCount: accounts.length + 1,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          if (index == accounts.length) {
                            return ListTile(
                              leading: const Icon(Icons.add_circle, color: Colors.green),
                              title: const Text("Add New Account", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                              onTap: () {
                                Navigator.pop(context);
                                _showAddAccountDialog(context, db, primary, secondary);
                              },
                            );
                          }
                          final acc = accounts[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(acc.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(acc.type, style: const TextStyle(fontSize: 12)),
                            trailing: acc.isDefault
                                ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                child: const Text("Default", style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold))
                            )
                                : IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => db.deletePaymentAccount(acc.id)),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddAccountDialog(BuildContext context, DbService db, Color primary, Color secondary) async {
    final currentAccounts = await db.getPaymentAccounts();
    if (currentAccounts.length >= 4) {
      if (context.mounted) _showModernSnackBar(context, "Maximum 4 Accounts Allowed!", type: "WARNING");
      return;
    }

    final nameCtrl = TextEditingController();
    String type = "BANK";

    if(!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 350),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Add Account", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                          labelText: "Account Name",
                          hintText: "e.g. HBL, JazzCash",
                          prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
                      )
                  ),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    value: type,
                    items: const ["BANK", "WALLET", "CASH"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setState(() => type = v!),
                    decoration: InputDecoration(
                        labelText: "Type",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
                    ),
                  ),
                  const SizedBox(height: 25),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: secondary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          if (nameCtrl.text.isNotEmpty) {
                            db.addPaymentAccount(nameCtrl.text, type);
                            Navigator.pop(ctx);
                            _showModernSnackBar(context, "Account '${nameCtrl.text}' added!", type: "SUCCESS");
                          }
                        },
                        child: const Text("Save Account"),
                      )
                    ],
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showChangePinDialog(BuildContext context, DbService db, bool isAdmin, Color primary, Color secondary) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 350),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isAdmin ? "Change Admin PIN" : "Change Staff PIN", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, letterSpacing: 5, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: "••••",
                    counterText: "",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 25),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: secondary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        if (ctrl.text.length >= 4) {
                          db.isar.writeTxn(() async {
                            var s = await db.isar.appSettings.where().findFirst() ?? AppSettings();
                            if (isAdmin) s.adminPin = ctrl.text; else s.staffPin = ctrl.text;
                            await db.isar.appSettings.put(s);
                          });
                          Navigator.pop(ctx);
                          _showModernSnackBar(context, "PIN Updated Successfully", type: "SUCCESS");
                        } else {
                          _showModernSnackBar(context, "PIN must be at least 4 digits", type: "WARNING");
                        }
                      },
                      child: const Text("Update PIN"),
                    )
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmReset(BuildContext context, DbService db) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 350),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 50, color: Colors.red),
                const SizedBox(height: 10),
                const Text("Factory Reset", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                const SizedBox(height: 10),
                const Text("This will delete ALL data (Products, Sales, Parties). This cannot be undone.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 20),
                TextField(
                  controller: ctrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: "Enter Admin PIN",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
                  ),
                ),
                const SizedBox(height: 25),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      onPressed: () async {
                        if (await db.verifyAdminPin(ctrl.text)) {
                          await db.factoryResetLocal();
                          Navigator.pop(ctx);
                          _showModernSnackBar(context, "System Reset Complete", type: "SUCCESS");
                        } else {
                          _showModernSnackBar(context, "Incorrect PIN", type: "ERROR");
                        }
                      },
                      child: const Text("RESET ALL"),
                    )
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}