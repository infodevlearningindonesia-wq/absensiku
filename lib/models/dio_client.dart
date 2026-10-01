import 'package:dio/dio.dart';

class DioClient {
  final Dio _dio;

  DioClient([Dio? dio]) : _dio = dio ?? Dio();

  Future<dynamic> get(String path) async {
    try {
      final response = await _dio.get(path);
      return response.data;
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  Future<dynamic> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }
}
