import 'package:flutter/foundation.dart';

class AuthService extends ChangeNotifier {
  bool _isAdmin = false;
  bool get isAdmin => _isAdmin;

  Future<bool> loginAnonymously(bool asAdmin) async {
    _isAdmin = asAdmin;
    notifyListeners();
    return true;
  }

  Future<bool> login(String email, String password) async {
    // Disabled in Local Mode
    return false;
  }

  void logout() {
    _isAdmin = false;
    notifyListeners();
  }
}