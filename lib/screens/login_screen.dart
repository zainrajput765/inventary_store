import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/db_service.dart';
import '../services/auth_service.dart';
import '../main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final pinCtrl = TextEditingController();
  String error = "";
  bool _isLoading = false;
  bool _isObscure = true;

  void _login() async {
    final pin = pinCtrl.text.trim();
    if (pin.isEmpty) return;

    setState(() { _isLoading = true; error = ""; });

    final auth = Provider.of<AuthService>(context, listen: false);
    final db = Provider.of<DbService>(context, listen: false);

    bool isAdmin = await db.verifyAdminPin(pin);
    bool isStaff = await db.verifyPin(pin);

    if (isAdmin || isStaff) {
      await auth.loginAnonymously(isAdmin);
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainLayoutScreen()));
      }
    } else {
      setState(() {
        error = "Invalid PIN";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- COLOR SCHEME ---
    const primaryColor = Color(0xFF2B3A67); // Royal Navy
    const secondaryColor = Color(0xFFECA400); // Gold

    return Scaffold(
      backgroundColor: primaryColor,
      body: Center(
        // SingleChildScrollView ensures the screen is scrollable if the keyboard covers the input
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            // ConstrainedBox ensures the card doesn't stretch too wide on tablets/desktop
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // --- LOGO SECTION ---
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))]
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: Image.asset(
                        'assets/logo.jpg',
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => const Icon(Icons.store, size: 50, color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "HAMII MOBILES",
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.2),
                  ),
                  const Text(
                    "Inventory System",
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 35),

                  // --- LOGIN CARD ---
                  Card(
                    elevation: 8,
                    shadowColor: Colors.black26,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 30),
                      child: Column(
                        children: [
                          const Text("Welcome Back", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primaryColor)),
                          const SizedBox(height: 8),
                          const Text("Enter PIN to access", style: TextStyle(color: Colors.grey, fontSize: 13)),
                          const SizedBox(height: 30),

                          // PIN INPUT
                          TextField(
                            controller: pinCtrl,
                            keyboardType: TextInputType.number,
                            obscureText: _isObscure,
                            maxLength: 6,
                            style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold, color: Colors.black87),
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              hintText: "••••",
                              hintStyle: TextStyle(color: Colors.grey[300]),
                              counterText: "",
                              filled: true,
                              fillColor: const Color(0xFFF3F4F6),
                              contentPadding: const EdgeInsets.symmetric(vertical: 16),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              suffixIcon: IconButton(
                                icon: Icon(_isObscure ? Icons.visibility : Icons.visibility_off, color: Colors.grey),
                                onPressed: () => setState(() => _isObscure = !_isObscure),
                              ),
                            ),
                            onSubmitted: (_) => _login(),
                          ),

                          if (error.isNotEmpty) ...[
                            const SizedBox(height: 15),
                            Text(error, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],

                          const SizedBox(height: 35),

                          // LOGIN BUTTON
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: secondaryColor,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: _isLoading
                                  ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: secondaryColor, strokeWidth: 2.5))
                                  : const Text("LOGIN", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}