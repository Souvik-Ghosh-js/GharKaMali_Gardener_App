import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;

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

    if (kDebugMode && path.contains('/gardener/profile')) print('🚀 [API] $method $path | Body: $body | Query: $query');
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

    if (kDebugMode && path.contains('/gardener/profile')) print('✅ [RES] $path | Status: ${res.statusCode}\n${_prettyJson(res.body)}');

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
    Map<String, XFile>? files,
  }) async {
    final headers = await _headers(auth: true, multipart: true);
    final request = http.MultipartRequest(method, Uri.parse('$kApiBase$path'))
      ..headers.addAll(headers)
      ..fields.addAll(fields);

    if (files != null) {
      for (final e in files.entries) {
        if (kIsWeb) {
          final bytes = await e.value.readAsBytes();
          request.files.add(http.MultipartFile.fromBytes(e.key, bytes, filename: e.value.name));
        } else {
          request.files.add(await http.MultipartFile.fromPath(e.key, e.value.path));
        }
      }
    }
    if (kDebugMode && path.contains('/gardener/profile')) print('🚀 [API MULTIPART] $method $path | Fields: $fields | Files: ${files?.keys}');
    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final res = await http.Response.fromStream(streamed);
    if (kDebugMode && path.contains('/gardener/profile')) print('✅ [RES MULTIPART] $path | Status: ${res.statusCode}\n${_prettyJson(res.body)}');
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

  Future<void> updateFcmToken(String token) async =>
      await _req('POST', '/auth/update-fcm-token', body: {'fcm_token': token});

  Future<Map<String,dynamic>> registerGardener({
    required String name, required String phone,
    String? email, String? bio, int? experienceYears,
    List<int>? serviceZoneIds, XFile? profileImage, XFile? idProof,
  }) async {
    final fields = <String, String>{'name': name, 'phone': phone};
    if (email != null) fields['email'] = email;
    if (bio != null) fields['bio'] = bio;
    if (experienceYears != null) fields['experience_years'] = '$experienceYears';
    if (serviceZoneIds != null && serviceZoneIds.isNotEmpty)
      fields['service_zone_ids'] = jsonEncode(serviceZoneIds);
    final files = <String, XFile>{};
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

  // ── ZONES / GEOFENCES ────────────────────────────────────────────────────
  Future<List<dynamic>> getZones() async =>
      await _req('GET', '/geofences', auth: false);

  // ── JOBS ──────────────────────────────────────────────────────────────────
  Future<dynamic> getJobs({String? status, String? date, int page = 1, int limit = 20}) async =>
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
    XFile? beforeImage, XFile? afterImage,
    List<String>? checklistDone,
    double? latitude, double? longitude,
  }) async {
    final fields = <String,String>{'booking_id': '$bookingId', 'status': status};
    if (notes != null && notes.isNotEmpty) fields['gardener_notes'] = notes;
    if (extraPlants != null && extraPlants > 0) fields['extra_plants'] = '$extraPlants';
    if (checklistDone != null && checklistDone.isNotEmpty) fields['checklist_done'] = jsonEncode(checklistDone);
    if (latitude != null) fields['latitude'] = '$latitude';
    if (longitude != null) fields['longitude'] = '$longitude';
    final files = <String,XFile>{};
    if (beforeImage != null) files['before_image'] = beforeImage;
    if (afterImage != null) files['after_image'] = afterImage;
    return await _multipart('PUT', '/bookings/status', fields: fields, files: files.isEmpty ? null : files);
  }

  Future<void> updateLocation(double lat, double lng, {int? bookingId}) async =>
      await _req('POST', '/bookings/location', body: {
        'latitude': lat, 'longitude': lng,
        if (bookingId != null) 'booking_id': bookingId,
      });

  // ── DOCUMENTS ─────────────────────────────────────────────────────────────
  Future<List<dynamic>> getGardenerDocuments() async =>
      await _req('GET', '/gardener/documents');

  Future<dynamic> uploadGardenerDocument(String docType, XFile file) async =>
      await _multipart('POST', '/gardener/documents',
          fields: {'doc_type': docType}, files: {'document': file});

  Future<void> deleteGardenerDocument(int id) async =>
      await _req('DELETE', '/gardener/documents/$id');

  // ── EARNINGS ──────────────────────────────────────────────────────────────
  Future<Map<String,dynamic>> getEarnings(String period) async =>
      await _req('GET', '/bookings/gardener/earnings', query: {'period': period});

  Future<dynamic> getRewards({int limit = 20}) async =>
      await _req('GET', '/gardener/rewards', query: {'limit': '$limit'});

  // ── VISIT REPORT (checklist / photos / health / materials) ────────────────
  /// Zone-agnostic task checklist. [serviceType] is 'ondemand' or 'subscription'.
  /// Handles both { items: [...] } and a bare array response defensively.
  Future<List<Map<String,dynamic>>> getChecklist(String serviceType) async {
    final res = await _req('GET', '/gardener/checklist', query: {'service_type': serviceType});
    final list = res is List ? res : (res is Map ? (res['items'] ?? []) : []);
    return list is List
        ? list.whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList()
        : <Map<String,dynamic>>[];
  }

  /// Uploads one visit photo. [type] is 'before' | 'after' | 'problem' | 'health'.
  Future<Map<String,dynamic>> uploadVisitPhoto({
    required int bookingId, required XFile photo, required String type,
    double? latitude, double? longitude,
  }) async {
    final fields = <String,String>{'type': type};
    if (latitude != null) fields['latitude'] = '$latitude';
    if (longitude != null) fields['longitude'] = '$longitude';
    final res = await _multipart('POST', '/gardener/visits/$bookingId/photos',
        fields: fields, files: {'photo': photo});
    return res is Map<String,dynamic> ? res : {};
  }

  Future<Map<String,dynamic>> getVisitReport(int bookingId) async {
    final res = await _req('GET', '/gardener/visits/$bookingId/report');
    return res is Map<String,dynamic> ? res : {};
  }

  Future<dynamic> submitHealthReport(int bookingId, {
    required List<String> conditions, String? remarks, String? photoUrl,
  }) async =>
      await _req('POST', '/gardener/visits/$bookingId/health', body: {
        'conditions': conditions,
        if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photo_url': photoUrl,
      });

  Future<dynamic> submitMaterials(int bookingId, List<Map<String,dynamic>> items) async =>
      await _req('POST', '/gardener/visits/$bookingId/materials', body: {'items': items});

  // ── LEADS / ESCALATIONS ───────────────────────────────────────────────────
  Future<dynamic> createLead({int? bookingId, required String type, required String note}) async =>
      await _req('POST', '/gardener/leads', body: {
        if (bookingId != null) 'booking_id': bookingId,
        'type': type, 'note': note,
      });

  Future<List<dynamic>> getLeads() async {
    final res = await _req('GET', '/gardener/leads');
    final list = res is List ? res : (res is Map ? (res['items'] ?? res['leads'] ?? []) : []);
    return list is List ? list : [];
  }

  Future<dynamic> createEscalation({
    int? bookingId, required String type, required String note, XFile? photo,
  }) async {
    final fields = <String,String>{'type': type, 'note': note};
    if (bookingId != null) fields['booking_id'] = '$bookingId';
    return await _multipart('POST', '/gardener/escalations',
        fields: fields, files: photo != null ? {'photo': photo} : null);
  }

  // ── ATTENDANCE / LEAVES ───────────────────────────────────────────────────
  Future<dynamic> attendanceCheckIn({double? latitude, double? longitude}) async =>
      await _req('POST', '/gardener/attendance/checkin', body: {
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      });

  Future<dynamic> attendanceCheckOut() async =>
      await _req('POST', '/gardener/attendance/checkout', body: {});

  Future<dynamic> getAttendanceToday() async =>
      await _req('GET', '/gardener/attendance/today');

  /// [month] is 'YYYY-MM'. Returns { rows, summary: {days_present, total_hours} }.
  Future<Map<String,dynamic>> getAttendanceMonth(String month) async {
    final res = await _req('GET', '/gardener/attendance', query: {'month': month});
    return res is Map<String,dynamic> ? res : {};
  }

  Future<dynamic> requestLeave({required String fromDate, required String toDate, required String reason}) async =>
      await _req('POST', '/gardener/leaves', body: {
        'from_date': fromDate, 'to_date': toDate, 'reason': reason,
      });

  Future<List<dynamic>> getLeaves() async {
    final res = await _req('GET', '/gardener/leaves');
    final list = res is List ? res : (res is Map ? (res['items'] ?? res['leaves'] ?? []) : []);
    return list is List ? list : [];
  }

  // ── SUPERVISOR / NOTIFICATIONS ────────────────────────────────────────────
  /// Returns { name, phone } or null when no supervisor is assigned.
  Future<Map<String,dynamic>?> getSupervisor() async {
    final res = await _req('GET', '/gardener/supervisor');
    if (res is Map<String,dynamic> && (res['phone'] != null || res['name'] != null)) return res;
    return null;
  }

  Future<List<dynamic>> getNotifications() async {
    final res = await _req('GET', '/notifications');
    final list = res is List ? res : (res is Map ? (res['items'] ?? res['notifications'] ?? []) : []);
    return list is List ? list : [];
  }

  String _prettyJson(String body) {
    try {
      final object = jsonDecode(body);
      return const JsonEncoder.withIndent('  ').convert(object);
    } catch (_) {
      return body;
    }
  }
}
