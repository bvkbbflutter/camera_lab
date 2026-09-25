import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../../core/settings_service.dart';
import '../metadata/image_format.dart';

/// Spec §25/§26: Base64 JSON and multipart upload, with the actual image
/// as the payload's primary content — never GPS/lat/lon as freestanding
/// JSON fields the server would have to trust blindly.
class UploadResult {
  final bool success;
  final String? fileId;
  final int statusCode;
  final String? errorCode;
  final String? errorMessage;
  final int requestPayloadBytes;
  final int uploadTimeMs;

  const UploadResult({
    required this.success,
    this.fileId,
    required this.statusCode,
    this.errorCode,
    this.errorMessage,
    required this.requestPayloadBytes,
    required this.uploadTimeMs,
  });
}

/// Spec §38/§39: configurable connect/send/receive timeouts, and support
/// for the server's X-Simulate header so the Network Tests screen can
/// exercise 400/401/413/500/timeout without needing a real flaky network.
class UploadService {
  final SettingsService settings;
  Dio? _dio;

  UploadService(this.settings);

  Dio _client() {
    _dio ??= Dio();
    _dio!.options
      ..baseUrl = settings.serverBaseUrl
      ..connectTimeout = Duration(seconds: settings.connectTimeoutSeconds)
      ..sendTimeout = Duration(seconds: settings.sendTimeoutSeconds)
      ..receiveTimeout = Duration(seconds: settings.receiveTimeoutSeconds);
    return _dio!;
  }

  Map<String, dynamic> _headers({String? simulate}) {
    final h = <String, dynamic>{};
    if (settings.apiToken.isNotEmpty) h['Authorization'] = 'Bearer ${settings.apiToken}';
    if (simulate != null) h['X-Simulate'] = simulate;
    return h;
  }

  Future<UploadResult> uploadBase64({
    required List<int> imageBytes,
    required String fileName,
    required ImageFormat format,
    String? uploadId,
    String? userId,
    String? simulateHeader,
    void Function(int sent, int total)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    final base64Str = base64Encode(imageBytes);
    final body = jsonEncode({
      'fileName': fileName,
      'mimeType': format.mimeType,
      'imageBase64': base64Str,
      if (uploadId != null) 'uploadId': uploadId,
      if (userId != null) 'userId': userId,
    });
    try {
      final res = await _client().post<Map<String, dynamic>>(
        '/api/images/base64',
        data: body,
        options: Options(contentType: 'application/json', headers: _headers(simulate: simulateHeader)),
        onSendProgress: onProgress,
      );
      stopwatch.stop();
      return UploadResult(
        success: res.data?['success'] == true,
        fileId: res.data?['fileId'] as String?,
        statusCode: res.statusCode ?? 0,
        requestPayloadBytes: utf8.encode(body).length,
        uploadTimeMs: stopwatch.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      stopwatch.stop();
      return _errorResult(e, utf8.encode(body).length, stopwatch.elapsedMilliseconds);
    }
  }

  Future<UploadResult> uploadMultipart({
    required List<int> imageBytes,
    required String fileName,
    required ImageFormat format,
    String? uploadId,
    String? userId,
    String? simulateHeader,
    void Function(int sent, int total)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(imageBytes, filename: fileName, contentType: MediaType.parse(format.mimeType)),
      if (uploadId != null) 'uploadId': uploadId,
      if (userId != null) 'userId': userId,
    });
    try {
      final res = await _client().post<Map<String, dynamic>>(
        '/api/images/multipart',
        data: form,
        options: Options(headers: _headers(simulate: simulateHeader)),
        onSendProgress: onProgress,
      );
      stopwatch.stop();
      return UploadResult(
        success: res.data?['success'] == true,
        fileId: res.data?['fileId'] as String?,
        statusCode: res.statusCode ?? 0,
        requestPayloadBytes: imageBytes.length, // ~payload; multipart framing overhead is small vs image bytes
        uploadTimeMs: stopwatch.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      stopwatch.stop();
      return _errorResult(e, imageBytes.length, stopwatch.elapsedMilliseconds);
    }
  }

  Future<bool> checkHealth() async {
    try {
      final res = await _client().get('/api/health', options: Options(sendTimeout: const Duration(seconds: 5)));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  UploadResult _errorResult(DioException e, int payloadBytes, int elapsedMs) {
    String code;
    String message;
    final status = e.response?.statusCode ?? 0;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        code = 'CONNECT_TIMEOUT';
        message = 'Could not connect to the server in time';
        break;
      case DioExceptionType.sendTimeout:
        code = 'SEND_TIMEOUT';
        message = 'Upload timed out while sending data';
        break;
      case DioExceptionType.receiveTimeout:
        code = 'RECEIVE_TIMEOUT';
        message = 'Server did not respond in time';
        break;
      case DioExceptionType.connectionError:
        code = 'CONNECTION_ERROR';
        message = e.message ?? 'Network connection error (server unreachable / offline)';
        break;
      case DioExceptionType.badResponse:
        code = (e.response?.data is Map) ? (e.response?.data['error']?['code'] as String? ?? 'HTTP_$status') : 'HTTP_$status';
        message = (e.response?.data is Map) ? (e.response?.data['error']?['message'] as String? ?? 'HTTP $status') : 'HTTP $status';
        break;
      default:
        code = 'UNKNOWN';
        message = e.message ?? 'Upload failed';
    }
    return UploadResult(
      success: false,
      statusCode: status,
      errorCode: code,
      errorMessage: message,
      requestPayloadBytes: payloadBytes,
      uploadTimeMs: elapsedMs,
    );
  }
}
