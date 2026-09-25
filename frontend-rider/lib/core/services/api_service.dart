// ══════════════════════════════════════════════════════════════
// Vendra App - API Service
// Dio-based HTTP client with JWT interceptor and error handling
// ══════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../config/api_config.dart';
import 'storage_service.dart';

class ApiService {
  /// Called when the server says the stored session is no longer valid
  /// (expired or invalid token). Each app sets this in main.dart to sign the
  /// user out and return to the login screen.
  static void Function()? onSessionExpired;
  static const _sessionCodes = {'TOKEN_EXPIRED', 'INVALID_TOKEN'};

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;

  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
        },
      ),
    );

    // Add JWT interceptor
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Attach token to every request if available
          final token = await StorageService.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (error, handler) async {
          debugPrint('API Error: ${error.requestOptions.path} → ${error.response?.statusCode}');
          if (error.response?.statusCode == 401 && _sessionCodes.contains(getErrorCode(error))) {
            // Only end the session if this request used the token that's stored now —
            // a late reply to a request sent before the user signed in again must not sign them out.
            final sent = (error.requestOptions.headers['Authorization'] as String?)?.replaceFirst('Bearer ', '');
            final current = await StorageService.getToken();
            if (sent != null && sent == current) onSessionExpired?.call();
          }
          return handler.next(error);
        },
      ),
    );
  }

  /// GET request
  Future<Response> get(String path, {Map<String, dynamic>? queryParams}) async {
    return await _dio.get(path, queryParameters: queryParams);
  }

  /// POST request
  Future<Response> post(String path, {dynamic data}) async {
    return await _dio.post(path, data: data);
  }

  /// PUT request
  Future<Response> put(String path, {dynamic data}) async {
    return await _dio.put(path, data: data);
  }

  /// DELETE request
  Future<Response> delete(String path) async {
    return await _dio.delete(path);
  }

  /// POST multipart/form-data (e.g. dispute evidence photos)
  Future<Response> postMultipart(String path, FormData data) async {
    return await _dio.post(
      path,
      data: data,
      options: Options(contentType: 'multipart/form-data', sendTimeout: const Duration(seconds: 60)),
    );
  }

  /// Extract error message from DioException
  static String getErrorMessage(dynamic error) {
    if (error is DioException) {
      if (error.response?.data != null && error.response?.data is Map) {
        return error.response?.data['message'] ?? 'An error occurred';
      }
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
          return 'Connection timeout. Please check your internet.';
        case DioExceptionType.receiveTimeout:
          return 'Server took too long to respond.';
        case DioExceptionType.connectionError:
          return 'Cannot connect to server. Is it running?';
        default:
          return 'Network error occurred.';
      }
    }
    return error.toString();
  }

  /// Machine-readable error code from the API (e.g. 'OUTSIDE_GEOFENCE', 'RESERVED_STOCK'), if any
  static String? getErrorCode(dynamic error) => getErrorData(error)?['code'] as String?;

  /// Full error body from the API, for codes that carry extra fields (distanceMeters, sellable…)
  static Map<String, dynamic>? getErrorData(dynamic error) {
    if (error is DioException && error.response?.data is Map) {
      return Map<String, dynamic>.from(error.response!.data as Map);
    }
    return null;
  }
}
