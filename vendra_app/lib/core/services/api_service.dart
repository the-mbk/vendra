// ══════════════════════════════════════════════════════════════
// Vendra App - API Service
// Dio-based HTTP client with JWT interceptor and error handling
// ══════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import '../../config/api_config.dart';
import 'storage_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;

  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
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
        onError: (error, handler) {
          // Log errors for debugging
          print('API Error: ${error.requestOptions.path} → ${error.response?.statusCode}');
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
}
