import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/db_service.dart';
import 'services/cart_service.dart';
import 'services/auth_service.dart';
import 'screens/inventory_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/ledgers_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/login_screen.dart';
import 'screens/stock_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dbService = DbService();
  await dbService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: dbService),
        ChangeNotifierProvider(create: (_) => CartService()),
        ChangeNotifierProvider(create: (_) => AuthService()),
      ],
      child: const MobileMartApp(),
    ),
  );
}

class MobileMartApp extends StatelessWidget {
  const MobileMartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HAMII Mobiles',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const LoginScreen(),
    );
  }

  ThemeData _buildTheme() {
    final base = ThemeData.light();
    const primaryColor = Color(0xFF2B3A67);
    const secondaryColor = Color(0xFFECA400);
    const bgColor = Color(0xFFF3F4F6);

    return base.copyWith(
      scaffoldBackgroundColor: bgColor,
      colorScheme: ColorScheme.fromSeed(seedColor: primaryColor, primary: primaryColor, secondary: secondaryColor, surface: Colors.white, background: bgColor),
      appBarTheme: const AppBarTheme(backgroundColor: primaryColor, foregroundColor: Colors.white, elevation: 0, centerTitle: true, iconTheme: IconThemeData(color: Colors.white), titleTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 0.5, color: Colors.white)),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: primaryColor, width: 2)), contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), labelStyle: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: secondaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), elevation: 3, textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: secondaryColor, foregroundColor: Colors.white),
    );
  }
}

class MainLayoutScreen extends StatefulWidget {
  const MainLayoutScreen({super.key});
  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  int _selectedIndex = 0;
  // --- ADDED: Track the specific stock tab (0=Android, 1=iPhone, 2=Accessory)
  int _stockTabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLowStock();
    });
  }

  // --- HELPER: Web-Style "Toast" Snackbar ---
  void _showModernSnackBar(String message, {String type = "SUCCESS", String? actionLabel, VoidCallback? onAction}) {
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
      case "ALERT":
        bg = const Color(0xFFFCF8E3); // Pale Yellow
        textColor = const Color(0xFF8A6D3B); // Dark Yellow
        icon = Icons.warning_amber_rounded;
        title = "ALERT!";
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

    // Responsive width check
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
            if (actionLabel != null && onAction != null)
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  onAction();
                },
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Text(actionLabel, style: TextStyle(fontWeight: FontWeight.bold, color: textColor, decoration: TextDecoration.underline)),
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
        // Limit width on desktop
        width: isDesktop ? 450 : null,
        margin: isDesktop ? null : const EdgeInsets.only(bottom: 20, left: 20, right: 20),
        elevation: 0,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _checkLowStock() async {
    final db = Provider.of<DbService>(context, listen: false);
    final lowStockItems = await db.getLowStockAccessories();

    if (lowStockItems.isNotEmpty && mounted) {
      _showModernSnackBar(
        "${lowStockItems.length} Accessories are running low (< 5)!",
        type: "ALERT",
        actionLabel: "VIEW",
        onAction: () {
          setState(() {
            _selectedIndex = 0; // 1. Switch to Stock Screen
            _stockTabIndex = 2; // 2. Switch to "Accessories" Tab
          });
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    bool isWideScreen = MediaQuery.of(context).size.width > 800;

    List<Widget> screens = [
      // --- FIXED: Pass the key and index to ensure tab switching works
      StockListScreen(key: ValueKey(_stockTabIndex), initialIndex: _stockTabIndex),
      const AddProductScreen(),
      const PosScreen(),
      const LedgersScreen(),
    ];
    if (auth.isAdmin) {
      screens.add(const ReportsScreen());
      screens.add(const SettingsScreen());
    }

    return Scaffold(
      body: Row(
        children: [
          if (isWideScreen)
            NavigationRail(
              extended: true,
              minExtendedWidth: 240,
              selectedIndex: _selectedIndex,
              onDestinationSelected: (int index) => setState(() => _selectedIndex = index),
              backgroundColor: const Color(0xFF2B3A67),
              indicatorColor: Colors.white.withOpacity(0.1),
              selectedIconTheme: const IconThemeData(color: Color(0xFFECA400)),
              unselectedIconTheme: const IconThemeData(color: Colors.white70),
              selectedLabelTextStyle: const TextStyle(color: Color(0xFFECA400), fontWeight: FontWeight.bold, letterSpacing: 0.5),
              unselectedLabelTextStyle: const TextStyle(color: Colors.white70),
              leading: Padding(
                padding: const EdgeInsets.only(bottom: 40, top: 30),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFECA400), width: 2)),
                      child: ClipRRect(borderRadius: BorderRadius.circular(50), child: Image.asset('assets/logo.jpg', width: 80, height: 80, fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(Icons.store, color: Colors.grey, size: 50))),
                    ),
                    const SizedBox(height: 15),
                    const Text("Hamii Mobiles", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))
                  ],
                ),
              ),
              destinations: _buildDestinations(auth.isAdmin),
              trailing: Expanded(child: Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: 20.0), child: TextButton.icon(onPressed: () { Provider.of<AuthService>(context, listen: false).logout(); Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())); }, icon: const Icon(Icons.logout, color: Colors.redAccent), label: const Text("Logout", style: TextStyle(color: Colors.redAccent)))))),
            ),
          Expanded(child: Scaffold(appBar: !isWideScreen ? AppBar(title: const Text("HAMII MOBILES")) : null, drawer: !isWideScreen ? _buildMobileDrawer(auth.isAdmin) : null, body: screens[_selectedIndex])),
        ],
      ),
    );
  }

  List<NavigationRailDestination> _buildDestinations(bool isAdmin) {
    List<NavigationRailDestination> dests = [
      const NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('Inventory')),
      const NavigationRailDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle), label: Text('Add Stock')),
      const NavigationRailDestination(icon: Icon(Icons.shopping_cart_outlined), selectedIcon: Icon(Icons.shopping_cart), label: Text('POS')),
      const NavigationRailDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: Text('Ledgers')),
    ];
    if (isAdmin) {
      dests.add(const NavigationRailDestination(icon: Icon(Icons.analytics_outlined), selectedIcon: Icon(Icons.analytics), label: Text('Reports')));
      dests.add(const NavigationRailDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('Settings')));
    }
    return dests;
  }

  Widget _buildMobileDrawer(bool isAdmin) {
    const primary = Color(0xFF2B3A67);
    const secondary = Color(0xFFECA400);
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: primary),
            // --- UPDATED: Display Logo Image in Mobile Drawer ---
            currentAccountPicture: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: secondary, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: Image.asset(
                  'assets/logo.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.store, color: primary),
                ),
              ),
            ),
            accountName: const Text("HAMII Mobiles", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: secondary)),
            accountEmail: const Text("Inventory System"),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _drawerItem(0, Icons.dashboard, "Inventory"),
                _drawerItem(1, Icons.add_box, "Add Stock"),
                _drawerItem(2, Icons.shopping_cart, "Point of Sale"),
                _drawerItem(3, Icons.account_balance_wallet, "Ledgers"),
                if (isAdmin) _drawerItem(4, Icons.analytics, "Reports"),
                if (isAdmin) _drawerItem(5, Icons.settings, "Settings"),
              ],
            ),
          ),
          const Divider(),
          ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text("Logout", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)), onTap: () { Provider.of<AuthService>(context, listen: false).logout(); Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())); }),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _drawerItem(int index, IconData icon, String title) {
    bool isSelected = _selectedIndex == index;
    const primary = Color(0xFF2B3A67);
    const secondary = Color(0xFFECA400);
    return ListTile(
        leading: Icon(icon, color: isSelected ? secondary : Colors.grey),
        title: Text(title, style: TextStyle(color: isSelected ? primary : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        selected: isSelected,
        tileColor: isSelected ? primary.withOpacity(0.05) : null,
        onTap: () { setState(() => _selectedIndex = index); Navigator.pop(context); }
    );
  }
}