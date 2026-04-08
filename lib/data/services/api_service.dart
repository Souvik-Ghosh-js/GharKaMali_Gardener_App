import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String kApiBase = 'https://gkm.gobt.in/api';
const String kTokenKey = 'gkm_gardener_token';
const String kUserKey  = 'gkm_gardener_user';

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final Map<String, dynamic>? data;
  ApiException(this.message, this.statusCode, [this.data]);
  @override String toString() => message;
}

class ApiService {
  static final ApiService _i = ApiService._();
  factory ApiService() => _i;
  ApiService._();

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kTokenKey);
  }

  Future<Map<String, String>> _headers({bool auth = true, bool multipart = false}) async {
    final h = <String, String>{};
    if (!multipart) h['Content-Type'] = 'application/json';
    if (auth) {
      final t = await getToken();
      if (t != null) h['Authorization'] = 'Bearer $t';
    }
    return h;
  }

  Future<dynamic> _req(
    String method, String path, {
    bool auth = true,
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    var uri = Uri.parse('$kApiBase$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }
    final headers = await _headers(auth: auth);

    http.Response res;
    try {
      switch (method) {
        case 'GET':    res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20)); break;
        case 'POST':   res = await http.post(uri, headers: headers, body: body != null ? jsonEncode(body) : null).timeout(const Duration(seconds: 20)); break;
        case 'PUT':    res = await http.put(uri, headers: headers, body: body != null ? jsonEncode(body) : null).timeout(const Duration(seconds: 20)); break;
        case 'PATCH':  res = await http.patch(uri, headers: headers, body: body != null ? jsonEncode(body) : null).timeout(const Duration(seconds: 20)); break;
        case 'DELETE': res = await http.delete(uri, headers: headers).timeout(const Duration(seconds: 20)); break;
        default: throw ApiException('Unknown method', 0);
      }
    } on SocketException {
      throw ApiException('No internet connection. Please check your network.', 0);
    } on HttpException {
      throw ApiException('Connection failed. Please try again.', 0);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Request timed out. Please try again.', 0);
    }

    Map<String, dynamic> json = {};
    try { json = jsonDecode(res.body); } catch (_) {}

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return json['data'] ?? json;
    }
    final msg = json['message'] as String? ?? 'Error ${res.statusCode}';
    throw ApiException(msg, res.statusCode, json);
  }

  Future<dynamic> _multipart(
    String method, String path, {
    required Map<String, String> fields,
    Map<String, File>? files,
  }) async {
    final headers = await _headers(auth: true, multipart: true);
    final request = http.MultipartRequest(method, Uri.parse('$kApiBase$path'))
      ..headers.addAll(headers)
      ..fields.addAll(fields);

    if (files != null) {
      for (final e in files.entries) {
        request.files.add(await http.MultipartFile.fromPath(e.key, e.value.path));
      }
    }
    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final res = await http.Response.fromStream(streamed);
    Map<String, dynamic> json = {};
    try { json = jsonDecode(res.body); } catch (_) {}
    if (res.statusCode >= 200 && res.statusCode < 300) return json['data'] ?? json;
    throw ApiException(json['message'] as String? ?? 'Error ${res.statusCode}', res.statusCode, json);
  }

  // ── AUTH ──────────────────────────────────────────────────────────────────
  Future<Map<String,dynamic>> sendOtp(String phone) async =>
      await _req('POST', '/auth/send-otp', auth: false, body: {'phone': phone});

  Future<Map<String,dynamic>> gardenerLogin(String phone, String otp, {String? fcmToken}) async =>
      await _req('POST', '/auth/gardener-login', auth: false, body: {
        'phone': phone, 
        'otp': otp,
        if (fcmToken != null) 'fcm_token': fcmToken,
      });

  Future<Map<String,dynamic>> registerGardener({
    required String name, required String phone,
    String? email, String? bio, int? experienceYears,
    List<int>? serviceZoneIds, File? profileImage, File? idProof,
  }) async {
    final fields = <String, String>{'name': name, 'phone': phone};
    if (email != null) fields['email'] = email;
    if (bio != null) fields['bio'] = bio;
    if (experienceYears != null) fields['experience_years'] = '$experienceYears';
    if (serviceZoneIds != null && serviceZoneIds.isNotEmpty)
      fields['service_zone_ids'] = jsonEncode(serviceZoneIds);
    final files = <String, File>{};
    if (profileImage != null) files['profile_image'] = profileImage;
    if (idProof != null) files['id_proof'] = idProof;
    return await _multipart('POST', '/auth/gardener-register', fields: fields, files: files.isEmpty ? null : files);
  }

  // ── PROFILE ───────────────────────────────────────────────────────────────
  Future<Map<String,dynamic>> getGardenerProfile() async =>
      await _req('GET', '/gardener/profile');

  Future<Map<String,dynamic>> updateGardenerProfile(Map<String,dynamic> data) async =>
      await _req('PUT', '/gardener/profile', body: data);

  Future<Map<String,dynamic>> setAvailability(bool isAvailable) async =>
      await _req('PATCH', '/gardener/availability', body: {'is_available': isAvailable});

  // ── ZONES ─────────────────────────────────────────────────────────────────
  Future<List<dynamic>> getZones() async =>
      await _req('GET', '/zones', auth: false);

  // ── JOBS ──────────────────────────────────────────────────────────────────
  Future<Map<String,dynamic>> getJobs({String? status, String? date, int page = 1, int limit = 20}) async =>
      await _req('GET', '/bookings/gardener/jobs', query: {
        if (status != null) 'status': status,
        if (date != null) 'date': date,
        'page': '$page', 'limit': '$limit',
      });

  Future<Map<String,dynamic>> getJobDetail(int id) async =>
      await _req('GET', '/bookings/$id');

  Future<Map<String,dynamic>> verifyVisitOtp(int bookingId, String otp) async =>
      await _req('POST', '/bookings/verify-otp', body: {'booking_id': bookingId, 'otp': otp});

  Future<Map<String,dynamic>> updateBookingStatus({
    required int bookingId, required String status,
    String? notes, int? extraPlants,
    File? beforeImage, File? afterImage,
  }) async {
    final fields = <String,String>{'booking_id': '$bookingId', 'status': status};
    if (notes != null && notes.isNotEmpty) fields['gardener_notes'] = notes;
    if (extraPlants != null && extraPlants > 0) fields['extra_plants'] = '$extraPlants';
    final files = <String,File>{};
    if (beforeImage != null) files['before_image'] = beforeImage;
    if (afterImage != null) files['after_image'] = afterImage;
    return await _multipart('PUT', '/bookings/status', fields: fields, files: files.isEmpty ? null : files);
  }

  Future<void> updateLocation(double lat, double lng, {int? bookingId}) async =>
      await _req('POST', '/bookings/location', body: {
        'latitude': lat, 'longitude': lng,
        if (bookingId != null) 'booking_id': bookingId,
      });

  // ── EARNINGS ──────────────────────────────────────────────────────────────
  Future<Map<String,dynamic>> getEarnings(String period) async =>
      await _req('GET', '/bookings/gardener/earnings', query: {'period': period});

  Future<Map<String,dynamic>> getRewards({int limit = 20}) async =>
      await _req('GET', '/gardener/rewards', query: {'limit': '$limit'});
}
