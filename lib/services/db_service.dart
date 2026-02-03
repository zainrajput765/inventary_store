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

  // ==============================================================================
  // 1. PARTIES & LEDGER
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

  // --- UPDATED ADD PARTY FUNCTION ---
  Future<void> addParty(String name, String phone, String type, {double openingBalance = 0}) async {
    if (await isar.partys.filter().nameEqualTo(name, caseSensitive: false).count() == 0) {
      await isar.writeTxn(() async {
        final newParty = Party()
          ..name = name
          ..phone = phone
          ..type = type
          ..balance = openingBalance // Set Correct Signed Balance
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
    if (!isCredit) {
      await _checkFunds("Cash Drawer", amt);
    }

    await isar.writeTxn(() async {
      final p = await isar.partys.get(id);
      if (p != null) {
        // Dealer: Credit = Payment Made (Debt Reduces/Increases Positive)
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

  Future<void> deleteParty(int id) async {
    await isar.writeTxn(() async => await isar.partys.delete(id));
    notifyListeners();
  }

  // ==============================================================================
  // 2. PRODUCTS & SMART DELETION
  // ==============================================================================

  Stream<List<Product>> listenToProducts() {
    return isar.products.filter().quantityGreaterThan(0).and().isDeletedEqualTo(false).watch(fireImmediately: true);
  }

  Future<void> deleteProduct(int id, {String? refundAccount}) async {
    final p = await isar.products.get(id);
    if (p != null) {
      double reversalAmount = p.costPrice * p.quantity;
      String sourceName = p.sourceContact ?? "Walk-In";

      await isar.writeTxn(() async {
        final party = await isar.partys.filter().nameEqualTo(sourceName, caseSensitive: false).findFirst();

        if (party != null && party.type == 'DEALER') {
          // Deleting stock means returning it essentially
          party.balance += reversalAmount; // Debt reduces (moves positive)
          party.lastActionTime = DateTime.now();
          await isar.partys.put(party);
          await isar.transactions.put(Transaction()..date = DateTime.now()..type = "STOCK_CORRECTION"..amount = reversalAmount..partyId = party.id..partyName = party.name..description = "Correction: Stock Deleted (${p.name})"..paymentSource = "Ledger");
        } else {
          await isar.transactions.put(Transaction()..date = DateTime.now()..type = "STOCK_CORRECTION"..amount = reversalAmount..partyName = sourceName..description = "Refund: Mistakenly added ${p.name} deleted"..paymentSource = refundAccount ?? "Cash Drawer");
        }

        p.isDeleted = true;
        p.quantity = 0;
        p.lastAction = 'DELETE';
        p.lastActionTime = DateTime.now();
        await isar.products.put(p);

        final units = await isar.mobileItems.filter().productIdEqualTo(id).findAll();
        for (var unit in units) {
          unit.status = 'DELETED';
          await isar.mobileItems.put(unit);
        }
      });
      notifyListeners();
    }
  }

  Future<bool> addProduct(Product product, {int? partyId, String? partyName, String? paymentMode, String? paymentSource, double? costTotal}) async {
    bool success = false;

    if (costTotal != null && costTotal > 0 && paymentMode == 'Cash') {
      await _checkFunds(paymentSource ?? "Cash Drawer", costTotal);
    }

    await isar.writeTxn(() async {
      product.lastAction = 'ADD';
      product.lastActionTime = DateTime.now();
      bool isBlocked = false;

      if(product.isMobile && product.imei != null) {
        final existing = await isar.products.filter().imeiEqualTo(product.imei).findFirst();

        if (existing != null) {
          final mobileUnit = await isar.mobileItems.filter().imeiEqualTo(product.imei!).findFirst();
          bool isArchivable = false;
          if (existing.isDeleted) {
            isArchivable = true;
          } else if (existing.quantity == 0) {
            isArchivable = true;
          } else if (mobileUnit != null && (mobileUnit.status == 'SOLD' || mobileUnit.status == 'RETURNED_TO_DEALER')) {
            isArchivable = true;
          }

          if (isArchivable) {
            String suffix = "_OLD_${DateTime.now().millisecondsSinceEpoch}";
            existing.imei = "${existing.imei}$suffix";
            existing.isDeleted = true;
            existing.lastAction = 'ARCHIVED';
            existing.lastActionTime = DateTime.now();
            await isar.products.put(existing);

            if (mobileUnit != null) {
              mobileUnit.imei = "${mobileUnit.imei}$suffix";
              mobileUnit.status = 'ARCHIVED';
              await isar.mobileItems.put(mobileUnit);
            }
          } else {
            isBlocked = true;
          }
        }

        if (!isBlocked) {
          await isar.products.put(product);
        }
      }
      else if (!product.isMobile) {
        final existing = await isar.products.filter()
            .nameEqualTo(product.name, caseSensitive: false)
            .and().brandEqualTo(product.brand, caseSensitive: false)
            .and().isMobileEqualTo(false)
            .findFirst();

        if (existing != null) {
          existing.quantity += product.quantity;
          existing.costPrice = product.costPrice;
          existing.sellPrice = product.sellPrice;
          existing.isDeleted = false;
          existing.lastAction = 'UPDATE_STOCK';
          existing.lastActionTime = DateTime.now();
          await isar.products.put(existing);
          product = existing;
        } else {
          await isar.products.put(product);
        }
      }

      if (!isBlocked) {
        success = true;
        String details = product.name;
        if(product.isMobile && product.imei != null) details += " (IMEI: ${product.imei})";

        if (costTotal != null && costTotal > 0) {
          String finalPartyName = partyName ?? "Walk-In / Outside";
          if (partyId != null) {
            final s = await isar.partys.get(partyId);
            if (s != null) {
              if (paymentMode == 'Credit') {
                // --- FIX: Credit Purchase REDUCES balance (Increases Debt) ---
                s.balance -= costTotal; // e.g. -500 - 100 = -600
                s.lastActionTime = DateTime.now();
                await isar.partys.put(s);
                await isar.transactions.put(Transaction()..date=DateTime.now()..type="PURCHASE_CREDIT"..amount=costTotal..partyId=s.id..partyName=s.name..description="Stock Credit: $details");
              } else {
                await isar.transactions.put(Transaction()..date=DateTime.now()..type="PURCHASE"..amount=costTotal..partyId=s.id..partyName=s.name..description="Purchase: $details"..paymentSource=paymentSource??"Cash Drawer");
              }
            }
          } else {
            if (paymentMode == 'Cash') {
              await isar.transactions.put(Transaction()..date = DateTime.now()..type = "PURCHASE"..amount = costTotal..partyName = finalPartyName..description = "Purchase: $details"..paymentSource = paymentSource ?? "Cash Drawer");
            }
          }
        }
      }
    });
    notifyListeners();
    return success;
  }

  Future<void> updateProduct(Product p) async {
    await isar.writeTxn(() async {
      p.lastAction = 'UPDATE_DETAILS';
      p.lastActionTime = DateTime.now();
      await isar.products.put(p);
    });
    notifyListeners();
  }

  Future<void> addMobileUnits(List<MobileItem> u) async { await isar.writeTxn(() async => await isar.mobileItems.putAll(u)); notifyListeners(); }
  Future<List<MobileItem>> getProductUnits(int id) async { return await isar.mobileItems.filter().productIdEqualTo(id).and().statusEqualTo("IN_STOCK").findAll(); }

  Stream<List<Product>> searchProducts(String query) {
    if (query.isEmpty) return isar.products.filter().quantityGreaterThan(0).and().isDeletedEqualTo(false).watch(fireImmediately: true);
    return isar.products.filter().quantityGreaterThan(0).and().isDeletedEqualTo(false).and().group((q) => q.nameContains(query, caseSensitive: false).or().imeiContains(query).or().brandContains(query, caseSensitive: false)).watch(fireImmediately: true);
  }

  Future<String?> verifyStockAvailability(List<CartItem> items) async { return null; }

  // ==============================================================================
  // 3. SALES & RETURNS
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

    if (netTotal < 0) {
      await _checkFunds("Cash Drawer", netTotal.abs());
    }

    await isar.writeTxn(() async {
      if (tradeInProduct != null) {
        final d = await isar.products.filter().imeiEqualTo(tradeInProduct.imei).findFirst();
        if (d == null) {
          await isar.products.put(tradeInProduct);
          if (tradeInItem != null) {
            tradeInItem.productId = tradeInProduct.id;
            await isar.mobileItems.put(tradeInItem);
          }
        }
      }

      double totalCostOfSale = 0.0;
      for (var item in cartItems) totalCostOfSale += (item.product.costPrice * item.quantity);

      double balanceDue = totalAmount - (totalPaid + tradeInAmount);
      String normName = customerName.isEmpty ? "Walk-in" : (customerName[0].toUpperCase() + customerName.substring(1));

      Party? party;
      if (normName != "Walk-in") {
        party = await isar.partys.filter().nameEqualTo(normName, caseSensitive: false).findFirst();
        if (party == null && balanceDue > 0) {
          party = Party()..name = normName..type = 'CUSTOMER'..phone = ""..balance = balanceDue..lastActionTime=DateTime.now();
          await isar.partys.put(party);
        } else if (party != null && balanceDue > 0) {
          party.balance += balanceDue;
          party.lastActionTime = DateTime.now();
          await isar.partys.put(party);
        }
      }

      await isar.invoices.put(Invoice()..date = DateTime.now()..invoiceNumber = "${DateTime.now().millisecondsSinceEpoch}"..customerName = normName..totalAmount = totalAmount + discount..discount = discount..finalAmount = totalAmount..paymentMode = balanceDue > 0 ? 'PARTIAL/CREDIT' : 'CASH'..totalCost = totalCostOfSale);

      String itemsDesc = "";
      for (var item in cartItems) {
        final product = await isar.products.get(item.product.id);
        if (product != null) {
          int newQty = product.quantity - item.quantity;
          product.quantity = newQty < 0 ? 0 : newQty;

          product.lastAction = 'SALE';
          product.lastActionTime = DateTime.now();

          await isar.products.put(product);

          if (product.isMobile && product.imei != null) {
            final mobileUnit = await isar.mobileItems.filter().imeiEqualTo(product.imei!).findFirst();
            if (mobileUnit != null) { mobileUnit.status = 'SOLD'; await isar.mobileItems.put(mobileUnit); }
            itemsDesc += "${product.name} [${product.imei}]\n";
          } else {
            itemsDesc += "${product.name} (x${item.quantity})\n";
          }
        }
      }

      String fullDesc = "Sold:\n$itemsDesc";
      if (tradeInDetail != null && tradeInDetail.isNotEmpty) fullDesc += "Trade-In: $tradeInDetail\n";
      if (discount > 0) fullDesc += "Discount: Rs ${discount.toInt()}\n";

      String paymentDetails = "";
      if (cashPaid > 0) paymentDetails += "Cash: ${cashPaid.toInt()} ";
      if (bankPaid > 0) paymentDetails += "Bank: ${bankPaid.toInt()} (${bankAccountName ?? 'Bank'})";
      if (paymentDetails.isNotEmpty) fullDesc += "Paid: $paymentDetails";

      if (totalPaid > 0) {
        String source = "Cash Drawer";
        String type = "SALE_CASH";

        if(cashPaid > 0 && bankPaid > 0) {
          source = "Split";
        } else if (bankPaid > 0) {
          source = bankAccountName ?? "Bank";
          type = "SALE_BANK";
        }

        await isar.transactions.put(Transaction()..date = DateTime.now()..type = type..amount = totalPaid..description = fullDesc..partyName = normName..partyId = party?.id..paymentSource = source);
      }
      else if (balanceDue < 0) {
        await isar.transactions.put(Transaction()..date = DateTime.now()..type = "PURCHASE"..amount = balanceDue.abs()..description = "Paid Customer (Exchange Balance)\n$fullDesc"..partyName = normName..partyId = party?.id..paymentSource = "Cash Drawer");
      }

      if (balanceDue > 0) {
        await isar.transactions.put(Transaction()..date = DateTime.now()..type = "SALE_CREDIT"..amount = balanceDue..description = "Credit Sale:\n$itemsDesc"..partyName = normName..partyId = party?.id..paymentSource = "Ledger");
      }
    });
    notifyListeners();
  }

  // --- PROCESS RETURN ---
  Future<void> processReturn({required String productName, required double refundAmount, required double originalCost, required String customerName, int? productId, String? imei, int? partyId, bool isDealerReturn = false}) async {

    bool isCashRefund = !isDealerReturn;
    Party? partyRecord;

    if (partyId != null) {
      partyRecord = await isar.partys.get(partyId);
    } else if (customerName.isNotEmpty) {
      partyRecord = await isar.partys.filter().nameEqualTo(customerName, caseSensitive: false).findFirst();
    }

    if (!isDealerReturn && partyRecord != null && partyRecord.balance > 0) {
      isCashRefund = false;
    }

    if (isCashRefund && refundAmount > 0) {
      await _checkFunds("Cash Drawer", refundAmount);
    }

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

      double actualCost = originalCost;

      if (isDealerReturn) {
        if (productId != null) {
          Product? product = await isar.products.get(productId!);
          if (product != null) {
            actualCost = product.costPrice;
            if (product.quantity > 0) {
              product.quantity -= 1;
              product.lastAction = 'RETURN_DEALER';
              product.lastActionTime = DateTime.now();
              await isar.products.put(product);
            }
          }
        }
        if (imei != null && imei.isNotEmpty) {
          final mobileUnit = await isar.mobileItems.filter().imeiEqualTo(imei).findFirst();
          if (mobileUnit != null) {
            mobileUnit.status = 'RETURNED_TO_DEALER';
            await isar.mobileItems.put(mobileUnit);
          }
        }
        if (partyRecord != null) {
          // --- FIX: DEALER RETURN INCREASES BALANCE (Reduces Debt) ---
          partyRecord!.balance += refundAmount; // e.g. -600 + 100 = -500
          partyRecord!.lastActionTime = DateTime.now();
          await isar.partys.put(partyRecord!);
        }
        await isar.transactions.put(Transaction()..date = DateTime.now()..type = "DEALER_RETURN"..amount = refundAmount..description = "Return to Dealer: $productName ${imei!=null?'($imei)':''}"..partyName = customerName..partyId = partyId ?? partyRecord?.id..paymentSource = "Ledger");

      } else {
        // ... (Customer Return Logic) ...
        if (productId != null) {
          Product? product = await isar.products.get(productId!);
          if (product != null) {
            actualCost = product.costPrice;
            product.quantity += 1;
            product.isDeleted = false;
            product.lastAction = 'RETURN_CUSTOMER';
            product.lastActionTime = DateTime.now();
            await isar.products.put(product);
          }
        }
        if (imei != null && imei.isNotEmpty) {
          final mobileUnit = await isar.mobileItems.filter().imeiEqualTo(imei).findFirst();
          if (mobileUnit != null) {
            mobileUnit.status = 'IN_STOCK';
            await isar.mobileItems.put(mobileUnit);
          } else if (productId != null) {
            await isar.mobileItems.put(MobileItem()..imei = imei..productName = productName..productId = productId!..status = 'IN_STOCK'..specificCostPrice = refundAmount);
          }
        }
        if (partyRecord != null && !isCashRefund) {
          partyRecord!.balance -= refundAmount;
          partyRecord!.lastActionTime = DateTime.now();
          await isar.partys.put(partyRecord!);
        }
        if (!isDealerReturn) {
          await isar.invoices.put(Invoice()..date = DateTime.now()..invoiceNumber = "RET-${DateTime.now().millisecondsSinceEpoch}"..customerName = customerName..finalAmount = -refundAmount..totalAmount = -refundAmount..discount = 0.0..totalCost = -actualCost..paymentMode = "REFUND");
        }

        String paymentSource = isCashRefund ? "Cash Drawer" : "Ledger";
        String type = isCashRefund ? "REFUND" : "RETURN_CREDIT";

        await isar.transactions.put(Transaction()..date = DateTime.now()..type = type..amount = refundAmount..description = "Return from Customer: $productName ${imei!=null?'($imei)':''}"..partyName = customerName..partyId = partyId ?? partyRecord?.id..paymentSource = paymentSource);
      }
    });
    notifyListeners();
  }

  Future<List<Transaction>> getPartyHistory(int id) async { return await isar.transactions.filter().partyIdEqualTo(id).sortByDateDesc().findAll(); }

  // --- ADDED FUNCTION: Get Transactions for Party (Alias for consistency) ---
  Future<List<Transaction>> getTransactionsForParty(int id) async { return await isar.transactions.filter().partyIdEqualTo(id).sortByDateDesc().findAll(); }

  Future<void> deleteTransaction(int id) async {
    await isar.writeTxn(() async {
      final t = await isar.transactions.get(id);
      if (t != null) {
        if (t.partyId != null) {
          final p = await isar.partys.get(t.partyId!);
          if (p != null) {
            if (t.type == "DEALER_RETURN" || t.type == "REFUND" || t.type == "RETURN_CREDIT") {
              p.balance += t.amount;
            } else {
              bool credit = t.type.contains("CREDIT") || t.type == "PURCHASE";
              p.balance = credit ? (p.balance - t.amount) : (p.balance + t.amount);
            }
            p.lastActionTime = DateTime.now();
            await isar.partys.put(p);
          }
        }
        t.isDeleted = true;
        await isar.transactions.put(t);
      }
    });
    notifyListeners();
  }

  // Accounts
  Future<List<PaymentAccount>> getPaymentAccounts() async { return await isar.paymentAccounts.filter().isDeletedEqualTo(false).findAll(); }

  Future<bool> addPaymentAccount(String name, String type, {double initialBalance = 0.0}) async {
    final existing = await isar.paymentAccounts.filter().nameEqualTo(name).findFirst();
    await isar.writeTxn(() async {
      if (existing != null && existing.isDeleted) {
        existing.isDeleted = false;
        existing.type = type;
        await isar.paymentAccounts.put(existing);
      } else {
        if (await isar.paymentAccounts.filter().isDeletedEqualTo(false).count() < 4) {
          await isar.paymentAccounts.put(PaymentAccount()..name = name..type = type);
        }
      }
      if (initialBalance > 0) {
        await isar.transactions.put(Transaction()..date = DateTime.now()..type = "OPENING_BALANCE"..amount = initialBalance..description = "Opening Balance"..paymentSource = name);
      }
    });
    notifyListeners();
    return true;
  }

  Future<void> deletePaymentAccount(int id) async {
    await isar.writeTxn(() async {
      final acc = await isar.paymentAccounts.get(id);
      if (acc != null && !acc.isDefault) {
        acc.isDeleted = true;
        await isar.paymentAccounts.put(acc);
      }
    });
    notifyListeners();
  }

  Future<void> addExpense(double a, String d, String s) async {
    await _checkFunds(s, a);
    await isar.writeTxn(() async => await isar.transactions.put(Transaction()..date=DateTime.now()..type="EXPENSE"..amount=a..description=d..paymentSource=s));
    notifyListeners();
  }

  Future<void> addIncome(double a, String d, String s) async { await isar.writeTxn(() async => await isar.transactions.put(Transaction()..date=DateTime.now()..type="PAYMENT_IN"..amount=a..description=d..paymentSource=s)); notifyListeners(); }
  Future<void> addCapital(double a, String d, String s) async { await isar.writeTxn(() async => await isar.transactions.put(Transaction()..date = DateTime.now()..type = "OPENING_BALANCE"..amount = a..description = "Investment: $d"..paymentSource = s)); notifyListeners(); }

  Future<Map<String, double>> getCashFlowBalances() async {
    final t = await isar.transactions.filter().isDeletedEqualTo(false).findAll();
    final a = await isar.paymentAccounts.filter().isDeletedEqualTo(false).findAll();
    Map<String,double> b = {for(var acc in a) acc.name:0.0};
    if(!b.containsKey("Cash Drawer")) b["Cash Drawer"]=0.0;

    for(var txn in t) {
      double v = txn.amount;
      String s = txn.paymentSource ?? "Cash Drawer";
      bool isIncome = txn.type.contains("SALE") || txn.type == "PAYMENT_IN" || txn.type == "OPENING_BALANCE" || txn.type == "PAYMENT" || txn.type == "STOCK_CORRECTION";
      bool isExpense = txn.type == "EXPENSE" || txn.type == "PAYMENT_OUT" || txn.type == "REFUND" || txn.type == "PURCHASE" || txn.type == "DEALER_RETURN" || txn.type == "RETURN_CREDIT";

      if (s == "Split" && isIncome && txn.description != null) {
        String desc = txn.description!;
        RegExp cashRegex = RegExp(r'Cash: (\d+)');
        var cashMatch = cashRegex.firstMatch(desc);
        if (cashMatch != null) {
          double cashAmt = double.tryParse(cashMatch.group(1)!) ?? 0;
          b["Cash Drawer"] = (b["Cash Drawer"] ?? 0) + cashAmt;
        }
        RegExp bankRegex = RegExp(r'Bank: (\d+) \((.*?)\)');
        var bankMatch = bankRegex.firstMatch(desc);
        if (bankMatch != null) {
          double bankAmt = double.tryParse(bankMatch.group(1)!) ?? 0;
          String bankName = bankMatch.group(2) ?? "";
          if (b.containsKey(bankName)) b[bankName] = (b[bankName] ?? 0) + bankAmt;
        }
      } else {
        if (!b.containsKey(s)) continue;
        if(isIncome) b[s] = (b[s] ?? 0) + v;
        else if(isExpense) b[s] = (b[s] ?? 0) - v;
      }
    }
    return b;
  }

  Future<List<Transaction>> getTransactionsByDate(DateTime s, DateTime e) async { return await isar.transactions.filter().dateBetween(s,e).and().isDeletedEqualTo(false).sortByDateDesc().findAll(); }
  Future<double> getStockValue() async { final p=await isar.products.where().findAll(); double t=0; for(var i in p) t+=(i.costPrice*i.quantity); return t; }

  Future<double> getRevenueTotal(DateTime s, DateTime e) async {
    final t = await isar.transactions.filter().dateBetween(s,e).and().isDeletedEqualTo(false).findAll();
    double tot = 0;
    for (var i in t) {
      if(i.type == "SALE_CASH" || i.type == "SALE_BANK" || i.type == "PAYMENT_IN") {
        tot += i.amount;
      } else if (i.type == "REFUND") {
        tot -= i.amount;
      }
    }
    return tot;
  }

  Future<double> getExpenseTotal(DateTime s, DateTime e) async {
    final t = await isar.transactions.filter().dateBetween(s, e).and().isDeletedEqualTo(false).findAll();
    double tot = 0;
    for (var i in t) {
      if (i.type == "EXPENSE") tot += i.amount;
    }
    return tot;
  }

  Future<double> getNetProfit(DateTime s, DateTime e) async {
    double totalSalesValue = 0;
    double cogs = 0;
    final invoices = await isar.invoices.filter().dateBetween(s, e).findAll();
    for (var inv in invoices) { totalSalesValue += inv.finalAmount; cogs += inv.totalCost; }

    double operatingExpenses = await getExpenseTotal(s, e);
    return totalSalesValue - cogs - operatingExpenses;
  }

  Stream<List<Invoice>> listenToInvoices() { return isar.invoices.where().sortByDateDesc().watch(fireImmediately: true); }

  // Wipe
  Future<void> factoryResetLocal() async { await isar.writeTxn(() async { await isar.clear(); await isar.appSettings.put(AppSettings()..adminPin = "0000"..staffPin = "1111"); await isar.paymentAccounts.put(PaymentAccount()..name="Cash Drawer"..type="CASH"..isDefault=true); }); notifyListeners(); }

  Future<bool> verifyPin(String p) async { final s = await isar.appSettings.where().findFirst(); return p == (s?.adminPin ?? "0000") || p == (s?.staffPin ?? "1111"); }
  Future<bool> verifyAdminPin(String p) async { final s = await isar.appSettings.where().findFirst(); return p == (s?.adminPin ?? "0000"); }
  Future<void> changeAdminPin(String n) async { await isar.writeTxn(() async { var s = await isar.appSettings.where().findFirst(); if (s == null) s = AppSettings()..staffPin = "1111"; s.adminPin = n; await isar.appSettings.put(s); }); notifyListeners(); }
}