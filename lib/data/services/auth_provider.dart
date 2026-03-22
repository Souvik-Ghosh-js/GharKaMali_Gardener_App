import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  Map<String, dynamic>? _user;
  String? _token;
  bool _loading = true;

  Map<String, dynamic>? get user    => _user;
  String?              get token    => _token;
  bool                 get isAuthed => _token != null && _user != null;
  bool                 get isLoading => _loading;

  AuthProvider() { _hydrate(); }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(kTokenKey);
    final raw = prefs.getString(kUserKey);
    if (_token != null && raw != null) {
      try { _user = jsonDecode(raw); } catch (_) { _user = null; _token = null; }
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> login(Map<String, dynamic> user, String token) async {
    _user = user; _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kTokenKey, token);
    await prefs.setString(kUserKey, jsonEncode(user));
    notifyListeners();
  }

  Future<void> updateUser(Map<String, dynamic> updates) async {
    if (_user == null) return;
    _user = {..._user!, ...updates};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kUserKey, jsonEncode(_user!));
    notifyListeners();
  }

  Future<void> logout() async {
    _user = null; _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kTokenKey);
    await prefs.remove(kUserKey);
    notifyListeners();
  }
}
