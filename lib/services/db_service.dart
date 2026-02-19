import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/schema.dart';
import 'cart_service.dart';

class DbService extends ChangeNotifier {
  late Isar isar;
  bool isInitialized = false;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    isar = await Isar.open(
      [ProductSchema, MobileItemSchema, PartySchema, InvoiceSchema, TransactionSchema, AppSettingsSchema, PaymentAccountSchema],
      directory: dir.path,
    );

    if (await isar.appSettings.count() == 0) {
      await isar.writeTxn(() async { await isar.appSettings.put(AppSettings()..adminPin = "0000"..staffPin = "1111"); });
    }
    if (await isar.paymentAccounts.count() == 0) {
      await isar.writeTxn(() async { await isar.paymentAccounts.put(PaymentAccount()..name="Cash Drawer"..type="CASH"..isDefault=true); });
    }

    isInitialized = true;
    notifyListeners();
  }

  // --- HELPER: CHECK FUNDS ---
  Future<void> _checkFunds(String source, double amountNeeded) async {
    Map<String, double> balances = await getCashFlowBalances();
    double current = balances[source] ?? 0.0;
    if (current < amountNeeded) {
      throw Exception("Insufficient funds in $source. Current: ${current.toInt()}, Needed: ${amountNeeded.toInt()}");
    }
  }

  // --- HELPER: LOW STOCK ACCESSORIES ---
  Future<List<Product>> getLowStockAccessories() async {
    return await isar.products
        .filter()
        .categoryEqualTo("Accessory")
        .and()
        .quantityLessThan(5)
        .and()
        .quantityGreaterThan(0)
        .and()
        .isDeletedEqualTo(false)
        .findAll();
  }

  // --- HELPER: AUTOCOMPLETE NAMES ---
  Future<List<String>> getProductNames(String query) async {
    final products = await isar.products
        .filter()
        .nameContains(query, caseSensitive: false)
        .findAll();
    return products.map((e) => e.name).toSet().toList();
  }

  // ==============================================================================
  // 1. PARTIES & LEDGER MANAGEMENT
  // ==============================================================================
  Future<List<Party>> getAllParties() async { return await isar.partys.where().findAll(); }

  Future<List<Party>> getSuppliers() async {
    return await isar.partys.filter().typeEqualTo("DEALER").findAll();
  }

  Stream<List<Party>> listenToParties(String type) { return isar.partys.filter().typeEqualTo(type).watch(fireImmediately: true); }

  Future<List<Party>> searchParties(String query) async {
    if (query.isEmpty) return [];
    return await isar.partys.filter().nameContains(query, caseSensitive: false).findAll();
  }

  // Add a new Party (Customer/Dealer) with Opening Balance
  Future<void> addParty(String name, String phone, String type, {double openingBalance = 0}) async {
    if (await isar.partys.filter().nameEqualTo(name, caseSensitive: false).count() == 0) {
      await isar.writeTxn(() async {
        final newParty = Party()
          ..name = name
          ..phone = phone
          ..type = type
          ..balance = openingBalance // Positive = Receivable, Negative = Payable
          ..lastActionTime = DateTime.now();

        await isar.partys.put(newParty);

        if (openingBalance != 0) {
          await isar.transactions.put(Transaction()
            ..date = DateTime.now()
            ..type = "OPENING_BALANCE"
            ..amount = openingBalance.abs()
            ..partyId = newParty.id
            ..partyName = name
            ..description = "Opening Balance"
            ..paymentSource = "Ledger"
          );
        }
      });
      notifyListeners();
    }
  }

  Future<void> updatePartyBalance(int id, double amt, bool isCredit, String note) async {
    if (!isCredit) await _checkFunds("Cash Drawer", amt);
    await isar.writeTxn(() async {
      final p = await isar.partys.get(id);
      if (p != null) {
        // Dealer: Credit = Payment Made (Debt Reduces)
        // Customer: Credit = Payment Recv (Receivable Reduces)
        p.balance += isCredit ? amt : -amt;
        p.lastActionTime = DateTime.now();
        await isar.partys.put(p);
        await isar.transactions.put(Transaction()
          ..date = DateTime.now()
          ..type = isCredit ? "CREDIT_ADDED" : (p.type == "DEALER" ? "PAYMENT_OUT" : "PAYMENT_IN")
          ..amount = amt
          ..partyId = id
          ..partyName = p.name
          ..description = note
          ..paymentSource = "Cash Drawer"
        );
      }
    });
    notifyListeners();
  }

  Future<void> deleteParty(int id) async { await isar.writeTxn(() async => await isar.partys.delete(id)); notifyListeners(); }

  // ==============================================================================
  // 2. PRODUCTS & INVENTORY
  // ==============================================================================
  Stream<List<Product>> listenToProducts() { return isar.products.filter().quantityGreaterThan(0).and().isDeletedEqualTo(false).watch(fireImmediately: true); }

  Future<void> deleteProduct(int id, {String? refundAccount}) async {
    final p = await isar.products.get(id);
    if (p != null) {
      double reversalAmount = p.costPrice * p.quantity;
      String sourceName = p.sourceContact ?? "Walk-In";
      await isar.writeTxn(() async {
        final party = await isar.partys.filter().nameEqualTo(sourceName, caseSensitive: false).findFirst();
        if (party != null && party.type == 'DEALER') {
          party.balance += reversalAmount;
          party.lastActionTime = DateTime.now();
          await isar.partys.put(party);
          await isar.transactions.put(Transaction()..date = DateTime.now()..type = "STOCK_CORRECTION"..amount = reversalAmount..partyId = party.id..partyName = party.name..description = "Correction: Stock Deleted (${p.name})"..paymentSource = "Ledger");
        } else {
          await isar.transactions.put(Transaction()..date = DateTime.now()..type = "STOCK_CORRECTION"..amount = reversalAmount..partyName = sourceName..description = "Refund: Mistakenly added ${p.name} deleted"..paymentSource = refundAccount ?? "Cash Drawer");
        }
        p.isDeleted = true; p.quantity = 0; p.lastAction = 'DELETE'; p.lastActionTime = DateTime.now();
        await isar.products.put(p);
        final units = await isar.mobileItems.filter().productIdEqualTo(id).findAll();
        for (var unit in units) { unit.status = 'DELETED'; await isar.mobileItems.put(unit); }
      });
      notifyListeners();
    }
  }

  Future<bool> addProduct(Product product, {int? partyId, String? partyName, String? paymentMode, String? paymentSource, double? costTotal}) async {
    bool success = false;
    if (costTotal != null && costTotal > 0 && paymentMode == 'Cash') await _checkFunds(paymentSource ?? "Cash Drawer", costTotal);

    await isar.writeTxn(() async {
      product.lastAction = 'ADD'; product.lastActionTime = DateTime.now();
      bool isBlocked = false;

      if(product.isMobile && product.imei != null) {
        final existing = await isar.products.filter().imeiEqualTo(product.imei).findFirst();
        if (existing != null) {
          final mobileUnit = await isar.mobileItems.filter().imeiEqualTo(product.imei!).findFirst();
          bool isArchivable = (existing.isDeleted || existing.quantity == 0 || (mobileUnit != null && (mobileUnit.status == 'SOLD' || mobileUnit.status == 'RETURNED_TO_DEALER')));
          if (isArchivable) {
            String suffix = "_OLD_${DateTime.now().millisecondsSinceEpoch}";
            existing.imei = "${existing.imei}$suffix"; existing.isDeleted = true; existing.lastAction = 'ARCHIVED'; existing.lastActionTime = DateTime.now();
            await isar.products.put(existing);
            if (mobileUnit != null) { mobileUnit.imei = "${mobileUnit.imei}$suffix"; mobileUnit.status = 'ARCHIVED'; await isar.mobileItems.put(mobileUnit); }
          } else { isBlocked = true; }
        }
        if (!isBlocked) await isar.products.put(product);
      } else if (!product.isMobile) {
        final existing = await isar.products.filter().nameEqualTo(product.name, caseSensitive: false).and().brandEqualTo(product.brand, caseSensitive: false).and().isMobileEqualTo(false).findFirst();
        if (existing != null) { existing.quantity += product.quantity; existing.costPrice = product.costPrice; existing.sellPrice = product.sellPrice; existing.isDeleted = false; existing.lastAction = 'UPDATE_STOCK'; existing.lastActionTime = DateTime.now(); await isar.products.put(existing); product = existing; }
        else { await isar.products.put(product); }
      }

      if (!isBlocked) {
        success = true;
        String details = product.name;
        if(product.isMobile && product.imei != null) details += " (IMEI: ${product.imei})";
        if (costTotal != null && costTotal > 0) {
          if (partyId != null) {
            final s = await isar.partys.get(partyId);
            if (s != null) {
              if (paymentMode == 'Credit') {
                s.balance -= costTotal; s.lastActionTime = DateTime.now();
                await isar.partys.put(s);
                await isar.transactions.put(Transaction()..date=DateTime.now()..type="PURCHASE_CREDIT"..amount=costTotal..partyId=s.id..partyName=s.name..description="Stock Credit: $details");
              } else {
                await isar.transactions.put(Transaction()..date=DateTime.now()..type="PURCHASE"..amount=costTotal..partyId=s.id..partyName=s.name..description="Purchase: $details"..paymentSource=paymentSource??"Cash Drawer");
              }
            }
          } else if (paymentMode == 'Cash') {
            await isar.transactions.put(Transaction()..date = DateTime.now()..type = "PURCHASE"..amount = costTotal..partyName = partyName ?? "Walk-In / Outside"..description = "Purchase: $details"..paymentSource = paymentSource ?? "Cash Drawer");
          }
        }
      }
    });
    notifyListeners();
    return success;
  }

  Future<void> updateProduct(Product p) async { await isar.writeTxn(() async { p.lastAction = 'UPDATE_DETAILS'; p.lastActionTime = DateTime.now(); await isar.products.put(p); }); notifyListeners(); }
  Future<void> addMobileUnits(List<MobileItem> u) async { await isar.writeTxn(() async => await isar.mobileItems.putAll(u)); notifyListeners(); }
  Future<List<MobileItem>> getProductUnits(int id) async { return await isar.mobileItems.filter().productIdEqualTo(id).and().statusEqualTo("IN_STOCK").findAll(); }
  Stream<List<Product>> searchProducts(String query) {
    if (query.isEmpty) return isar.products.filter().quantityGreaterThan(0).and().isDeletedEqualTo(false).watch(fireImmediately: true);
    return isar.products.filter().quantityGreaterThan(0).and().isDeletedEqualTo(false).and().group((q) => q.nameContains(query, caseSensitive: false).or().imeiContains(query).or().brandContains(query, caseSensitive: false)).watch(fireImmediately: true);
  }
  Future<String?> verifyStockAvailability(List<CartItem> items) async { return null; }

  // ==============================================================================
  // 3. SALES & RETURNS (CORE LOGIC)
  // ==============================================================================

  Future<void> processSale(
      List<CartItem> cartItems,
      double totalAmount,
      double discount,
      double cashPaid,
      double bankPaid,
      String? bankAccountName,
      String customerName,
      {
        double tradeInAmount = 0.0,
        String? tradeInDetail,
        Product? tradeInProduct,
        MobileItem? tradeInItem
      }) async {

    double totalPaid = cashPaid + bankPaid;
    double netTotal = totalAmount - totalPaid - tradeInAmount;
    if (netTotal < 0) await _checkFunds("Cash Drawer", netTotal.abs());

    await isar.writeTxn(() async {
      // --- SMART TRADE-IN LOGIC ---
      if (tradeInProduct != null) {
        int pId;
        // MOBILE: Always Create New Product (To preserve unique IMEI/Condition)
        if (tradeInProduct.isMobile) {
          await isar.products.put(tradeInProduct);
          pId = tradeInProduct.id;
        }
        // ACCESSORY: Merge if name matches
        else {
          final existing = await isar.products.filter()
              .nameEqualTo(tradeInProduct.name, caseSensitive: false)
              .and().isMobileEqualTo(false)
              .findFirst();

          if (existing != null) {
            existing.quantity += 1; existing.lastAction = 'TRADE_IN_ADD'; existing.lastActionTime = DateTime.now();
            await isar.products.put(existing); pId = existing.id;
          } else {
            await isar.products.put(tradeInProduct); pId = tradeInProduct.id;
          }
        }
        if (tradeInItem != null) { tradeInItem.productId = pId; await isar.mobileItems.put(tradeInItem); }
      }

      // --- 2. BUILD DESCRIPTION ---
      String receiptDesc = "ITEMS SOLD:\n";
      double totalCostOfSale = 0.0;

      for (var item in cartItems) {
        final product = await isar.products.get(item.product.id);
        if (product != null) {
          int newQty = product.quantity - item.quantity;
          product.quantity = newQty < 0 ? 0 : newQty;
          product.lastAction = 'SALE'; product.lastActionTime = DateTime.now();
          await isar.products.put(product);
          totalCostOfSale += (item.product.costPrice * item.quantity);

          String itemLine = "${product.name}";
          if (product.isMobile && product.imei != null) {
            final mobileUnit = await isar.mobileItems.filter().imeiEqualTo(product.imei!).findFirst();
            if (mobileUnit != null) { mobileUnit.status = 'SOLD'; await isar.mobileItems.put(mobileUnit); }
            itemLine += " [${product.imei}]";
          } else {
            itemLine += " x${item.quantity}";
          }
          if(item.isGift) itemLine += " (GIFT - FREE)";
          receiptDesc += "- $itemLine\n";
        }
      }

      if (tradeInAmount > 0) {
        receiptDesc += "\nTRADE-IN RECV:\n- $tradeInDetail (Val: Rs ${tradeInAmount.toInt()})\n";
        if (tradeInProduct?.ptaStatus != null) receiptDesc += "  PTA: ${tradeInProduct!.ptaStatus}\n";
      }

      if (discount > 0) receiptDesc += "\nDISCOUNT GIVEN: Rs ${discount.toInt()}";

      // --- 3. INVOICE & LEDGER ---
      double balanceDue = totalAmount - (totalPaid + tradeInAmount);
      String normName = customerName.isEmpty ? "Walk-in" : (customerName.toUpperCase());

      Party? party;
      if (normName != "WALK-IN") {
        party = await isar.partys.filter().nameEqualTo(normName, caseSensitive: false).findFirst();
        if (party == null && balanceDue > 0) {
          party = Party()..name = normName..type = 'CUSTOMER'..phone = ""..balance = balanceDue..lastActionTime=DateTime.now();
          await isar.partys.put(party!);
        } else if (party != null && balanceDue > 0) {
          party.balance += balanceDue; party.lastActionTime = DateTime.now();
          await isar.partys.put(party);
        }
      }

      await isar.invoices.put(Invoice()..date = DateTime.now()..invoiceNumber = "${DateTime.now().millisecondsSinceEpoch}"..customerName = normName..totalAmount = totalAmount + discount..discount = discount..finalAmount = totalAmount..paymentMode = balanceDue > 0 ? 'PARTIAL/CREDIT' : 'CASH'..totalCost = totalCostOfSale);

      if (totalPaid > 0) {
        String source = "Cash Drawer";
        String type = "SALE_CASH";
        if(cashPaid > 0 && bankPaid > 0) source = "Split";
        else if (bankPaid > 0) { source = bankAccountName ?? "Bank"; type = "SALE_BANK"; }

        await isar.transactions.put(Transaction()..date = DateTime.now()..type = type..amount = totalPaid..description = receiptDesc..partyName = normName..partyId = party?.id..paymentSource = source);
      } else if (balanceDue < 0) {
        await isar.transactions.put(Transaction()..date = DateTime.now()..type = "PURCHASE"..amount = balanceDue.abs()..description = "Paid Customer (Exchange Balance)\n$receiptDesc"..partyName = normName..partyId = party?.id..paymentSource = "Cash Drawer");
      }

      if (balanceDue > 0) {
        await isar.transactions.put(Transaction()..date = DateTime.now()..type = "SALE_CREDIT"..amount = balanceDue..description = "CREDIT SALE:\n$receiptDesc"..partyName = normName..partyId = party?.id..paymentSource = "Ledger");
      }
    });
    notifyListeners();
  }

  // --- PROCESS RETURN ---
  Future<void> processReturn({required String productName, required double refundAmount, required double originalCost, required String customerName, int? productId, String? imei, int? partyId, bool isDealerReturn = false, String? refundAccount}) async {
    bool isCashRefund = !isDealerReturn;
    Party? partyRecord;
    if (partyId != null) partyRecord = await isar.partys.get(partyId);
    else if (customerName.isNotEmpty) partyRecord = await isar.partys.filter().nameEqualTo(customerName, caseSensitive: false).findFirst();

    if (!isDealerReturn && partyRecord != null && partyRecord.balance > 0) isCashRefund = false;
    if (isCashRefund && refundAmount > 0) await _checkFunds(refundAccount ?? "Cash Drawer", refundAmount);

    await isar.writeTxn(() async {
      if (partyRecord == null && partyId != null) partyRecord = await isar.partys.get(partyId);
      if (partyRecord == null && customerName.isNotEmpty) partyRecord = await isar.partys.filter().nameEqualTo(customerName, caseSensitive: false).findFirst();

      if (productId == null && imei != null && imei.isNotEmpty) {
        final mobileUnit = await isar.mobileItems.filter().imeiEqualTo(imei).findFirst();
        if (mobileUnit != null) { productId = mobileUnit.productId; if(productName.isEmpty) productName = mobileUnit.productName; }
        else { final p = await isar.products.filter().imeiEqualTo(imei).findFirst(); if (p != null) { productId = p.id; if(productName.isEmpty) productName = p.name; } }
      }
      if (productId == null && productName.isNotEmpty) { final p = await isar.products.filter().nameEqualTo(productName).findFirst(); if (p != null) productId = p.id; }

      if (productId == null && !isDealerReturn) {
        Product newP = Product()..name = productName.isEmpty ? "Returned Item" : productName..costPrice = refundAmount..sellPrice = refundAmount..quantity = 0..isMobile = (imei != null && imei.isNotEmpty)..imei = imei..brand = "Return"..category = (imei != null && imei.isNotEmpty) ? "Android" : "Accessory";
        await isar.products.put(newP); productId = newP.id;
      }

      if (isDealerReturn) {
        if (productId != null) {
          Product? product = await isar.products.get(productId!);
          if (product != null && product.quantity > 0) { product.quantity -= 1; product.lastAction = 'RETURN_DEALER'; product.lastActionTime = DateTime.now(); await isar.products.put(product); }
        }
        if (imei != null && imei.isNotEmpty) { final mobileUnit = await isar.mobileItems.filter().imeiEqualTo(imei).findFirst(); if (mobileUnit != null) { mobileUnit.status = 'RETURNED_TO_DEALER'; await isar.mobileItems.put(mobileUnit); } }

        if (partyRecord != null) {
          partyRecord!.balance += refundAmount;
          partyRecord!.lastActionTime = DateTime.now();
          await isar.partys.put(partyRecord!);
        }
        await isar.transactions.put(Transaction()..date = DateTime.now()..type = "DEALER_RETURN"..amount = refundAmount..description = "Return to Dealer: $productName ${imei!=null?'($imei)':''}"..partyName = customerName..partyId = partyId ?? partyRecord?.id..paymentSource = "Ledger");
      } else {
        if (productId != null) {
          Product? product = await isar.products.get(productId!);
          if (product != null) { product.quantity += 1; product.isDeleted = false; product.lastAction = 'RETURN_CUSTOMER'; product.lastActionTime = DateTime.now(); await isar.products.put(product); }
        }
        if (imei != null && imei.isNotEmpty) {
          final mobileUnit = await isar.mobileItems.filter().imeiEqualTo(imei).findFirst();
          if (mobileUnit != null) { mobileUnit.status = 'IN_STOCK'; await isar.mobileItems.put(mobileUnit); }
          else if (productId != null) { await isar.mobileItems.put(MobileItem()..imei = imei..productName = productName..productId = productId!..status = 'IN_STOCK'..specificCostPrice = refundAmount); }
        }

        if (partyRecord != null && !isCashRefund) {
          partyRecord!.balance -= refundAmount;
          partyRecord!.lastActionTime = DateTime.now();
          await isar.partys.put(partyRecord!);
        }

        if (!isDealerReturn) { await isar.invoices.put(Invoice()..date = DateTime.now()..invoiceNumber = "RET-${DateTime.now().millisecondsSinceEpoch}"..customerName = customerName..finalAmount = -refundAmount..totalAmount = -refundAmount..discount = 0.0..totalCost = -originalCost..paymentMode = "REFUND"); }
        await isar.transactions.put(Transaction()..date = DateTime.now()..type = isCashRefund ? "REFUND" : "RETURN_CREDIT"..amount = refundAmount..description = "Return from Customer: $productName ${imei!=null?'($imei)':''}"..partyName = customerName..partyId = partyId ?? partyRecord?.id..paymentSource = isCashRefund ? (refundAccount ?? "Cash Drawer") : "Ledger");
      }
    });
    notifyListeners();
  }

  Future<List<Transaction>> getPartyHistory(int id) async { return await isar.transactions.filter().partyIdEqualTo(id).sortByDateDesc().findAll(); }
  Future<List<Transaction>> getTransactionsForParty(int id) async { return await isar.transactions.filter().partyIdEqualTo(id).sortByDateDesc().findAll(); }

  Future<void> deleteTransaction(int id) async {
    await isar.writeTxn(() async {
      final t = await isar.transactions.get(id);
      if (t != null) {
        if (t.partyId != null) {
          final p = await isar.partys.get(t.partyId!);
          if (p != null) {
            if (t.type == "DEALER_RETURN" || t.type == "REFUND" || t.type == "RETURN_CREDIT") { p.balance += t.amount; }
            else { bool credit = t.type.contains("CREDIT") || t.type == "PURCHASE"; p.balance = credit ? (p.balance - t.amount) : (p.balance + t.amount); }
            p.lastActionTime = DateTime.now(); await isar.partys.put(p);
          }
        }
        t.isDeleted = true; await isar.transactions.put(t);
      }
    });
    notifyListeners();
  }

  Future<List<PaymentAccount>> getPaymentAccounts() async { return await isar.paymentAccounts.filter().isDeletedEqualTo(false).findAll(); }
  Future<bool> addPaymentAccount(String name, String type, {double initialBalance = 0.0}) async {
    final existing = await isar.paymentAccounts.filter().nameEqualTo(name).findFirst();
    await isar.writeTxn(() async {
      if (existing != null && existing.isDeleted) { existing.isDeleted = false; existing.type = type; await isar.paymentAccounts.put(existing); }
      else if (await isar.paymentAccounts.filter().isDeletedEqualTo(false).count() < 4) { await isar.paymentAccounts.put(PaymentAccount()..name = name..type = type); }
      if (initialBalance > 0) await isar.transactions.put(Transaction()..date = DateTime.now()..type = "OPENING_BALANCE"..amount = initialBalance..description = "Opening Balance"..paymentSource = name);
    });
    notifyListeners();
    return true;
  }
  Future<void> deletePaymentAccount(int id) async { await isar.writeTxn(() async { final acc = await isar.paymentAccounts.get(id); if (acc != null && !acc.isDefault) { acc.isDeleted = true; await isar.paymentAccounts.put(acc); } }); notifyListeners(); }

  Future<void> addExpense(double a, String d, String s) async { await _checkFunds(s, a); await isar.writeTxn(() async => await isar.transactions.put(Transaction()..date=DateTime.now()..type="EXPENSE"..amount=a..description=d..paymentSource=s)); notifyListeners(); }
  Future<void> addIncome(double a, String d, String s) async { await isar.writeTxn(() async => await isar.transactions.put(Transaction()..date=DateTime.now()..type="PAYMENT_IN"..amount=a..description=d..paymentSource=s)); notifyListeners(); }
  Future<void> addCapital(double a, String d, String s) async { await isar.writeTxn(() async => await isar.transactions.put(Transaction()..date = DateTime.now()..type = "OPENING_BALANCE"..amount = a..description = "Investment: $d"..paymentSource = s)); notifyListeners(); }

  Future<Map<String, double>> getCashFlowBalances() async {
    final t = await isar.transactions.filter().isDeletedEqualTo(false).findAll();
    final a = await isar.paymentAccounts.filter().isDeletedEqualTo(false).findAll();
    Map<String,double> b = {for(var acc in a) acc.name:0.0}; if(!b.containsKey("Cash Drawer")) b["Cash Drawer"]=0.0;
    for(var txn in t) {
      double v = txn.amount; String s = txn.paymentSource ?? "Cash Drawer";
      bool isIncome = txn.type.contains("SALE") || txn.type == "PAYMENT_IN" || txn.type == "OPENING_BALANCE" || txn.type == "PAYMENT" || txn.type == "STOCK_CORRECTION";
      bool isExpense = txn.type == "EXPENSE" || txn.type == "PAYMENT_OUT" || txn.type == "REFUND" || txn.type == "PURCHASE" || txn.type == "DEALER_RETURN" || txn.type == "RETURN_CREDIT";
      if (s == "Split" && isIncome && txn.description != null) {
        String desc = txn.description!;
        var cashMatch = RegExp(r'Cash: (\d+)').firstMatch(desc); if (cashMatch != null) b["Cash Drawer"] = (b["Cash Drawer"] ?? 0) + (double.tryParse(cashMatch.group(1)!) ?? 0);
        var bankMatch = RegExp(r'Bank: (\d+) \((.*?)\)').firstMatch(desc); if (bankMatch != null) { String bn = bankMatch.group(2) ?? ""; if (b.containsKey(bn)) b[bn] = (b[bn] ?? 0) + (double.tryParse(bankMatch.group(1)!) ?? 0); }
      } else { if (!b.containsKey(s)) continue; if(isIncome) b[s] = (b[s] ?? 0) + v; else if(isExpense) b[s] = (b[s] ?? 0) - v; }
    }
    return b;
  }

  Future<List<Transaction>> getTransactionsByDate(DateTime s, DateTime e) async { return await isar.transactions.filter().dateBetween(s,e).and().isDeletedEqualTo(false).sortByDateDesc().findAll(); }
  Future<double> getStockValue() async { final p=await isar.products.where().findAll(); double t=0; for(var i in p) t+=(i.costPrice*i.quantity); return t; }
  Future<double> getRevenueTotal(DateTime s, DateTime e) async { final t = await isar.transactions.filter().dateBetween(s,e).and().isDeletedEqualTo(false).findAll(); double tot = 0; for (var i in t) { if(i.type.contains("SALE") || i.type == "PAYMENT_IN") tot += i.amount; else if (i.type == "REFUND") tot -= i.amount; } return tot; }
  Future<double> getExpenseTotal(DateTime s, DateTime e) async { final t = await isar.transactions.filter().dateBetween(s, e).and().isDeletedEqualTo(false).findAll(); double tot = 0; for (var i in t) { if (i.type == "EXPENSE") tot += i.amount; } return tot; }
  Future<double> getNetProfit(DateTime s, DateTime e) async { double totalSalesValue = 0; double cogs = 0; final invoices = await isar.invoices.filter().dateBetween(s, e).findAll(); for (var inv in invoices) { totalSalesValue += inv.finalAmount; cogs += inv.totalCost; } double operatingExpenses = await getExpenseTotal(s, e); return totalSalesValue - cogs - operatingExpenses; }
  Stream<List<Invoice>> listenToInvoices() { return isar.invoices.where().sortByDateDesc().watch(fireImmediately: true); }

  Future<void> factoryResetLocal() async { await isar.writeTxn(() async { await isar.clear(); await isar.appSettings.put(AppSettings()..adminPin = "0000"..staffPin = "1111"); await isar.paymentAccounts.put(PaymentAccount()..name="Cash Drawer"..type="CASH"..isDefault=true); }); notifyListeners(); }
  Future<bool> verifyPin(String p) async { final s = await isar.appSettings.where().findFirst(); return p == (s?.adminPin ?? "0000") || p == (s?.staffPin ?? "1111"); }
  Future<bool> verifyAdminPin(String p) async { final s = await isar.appSettings.where().findFirst(); return p == (s?.adminPin ?? "0000"); }
  Future<void> changeAdminPin(String n) async { await isar.writeTxn(() async { var s = await isar.appSettings.where().findFirst(); if (s == null) s = AppSettings()..staffPin = "1111"; s.adminPin = n; await isar.appSettings.put(s); }); notifyListeners(); }

  // ==============================================================================
  // 4. BACKUP & RESTORE
  // ==============================================================================

  Future<String> createBackup() async {
    final dir = await getApplicationDocumentsDirectory();
    final backupPath = '${dir.path}/hassan_backup_${DateTime.now().millisecondsSinceEpoch}.isar';
    await isar.copyToFile(backupPath);
    return backupPath;
  }

  Future<void> restoreBackup(String backupPath) async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = dir.path;

    // 1. Close current connection
    await isar.close();

    // 2. Overwrite files
    final dbFile = File('$dbPath/default.isar');
    final backupFile = File(backupPath);

    if (await backupFile.exists()) {
      await backupFile.copy(dbFile.path);
    }

    // 3. Re-open
    isar = await Isar.open(
      [ProductSchema, MobileItemSchema, PartySchema, InvoiceSchema, TransactionSchema, AppSettingsSchema, PaymentAccountSchema],
      directory: dir.path,
    );
    notifyListeners();
  }
}