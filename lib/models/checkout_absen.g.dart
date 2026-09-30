// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checkout_absen.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CheckoutAbsen _$CheckoutAbsenFromJson(Map<String, dynamic> json) =>
    CheckoutAbsen(
      message: json['message'] as String?,
      data: json['data'] == null
          ? null
          : AbsenData.fromJson(json['data'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$CheckoutAbsenToJson(CheckoutAbsen instance) =>
    <String, dynamic>{
      'message': instance.message,
      'data': instance.data?.toJson(),
    };

AbsenData _$AbsenDataFromJson(Map<String, dynamic> json) => AbsenData(
      id: (json['id'] as num?)?.toInt(),
      userId: (json['user_id'] as num?)?.toInt(),
      checkIn: json['check_in'] as String?,
      checkInLocation: json['check_in_location'] as String?,
      checkInAddress: json['check_in_address'] as String?,
      checkOut: json['check_out'] as String?,
      checkOutLocation: json['check_out_location'] as String?,
      checkOutAddress: json['check_out_address'] as String?,
      status: json['status'] as String?,
      alasanIzin: json['alasan_izin'] as String?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      checkInLat: json['check_in_lat'],
      checkInLng: json['check_in_lng'],
      checkOutLat: json['check_out_lat'],
      checkOutLng: json['check_out_lng'],
    );

Map<String, dynamic> _$AbsenDataToJson(AbsenData instance) => <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'check_in': instance.checkIn,
      'check_in_location': instance.checkInLocation,
      'check_in_address': instance.checkInAddress,
      'check_out': instance.checkOut,
      'check_out_location': instance.checkOutLocation,
      'check_out_address': instance.checkOutAddress,
      'status': instance.status,
      'alasan_izin': instance.alasanIzin,
      'created_at': instance.createdAt,
      'updated_at': instance.updatedAt,
      'check_in_lat': instance.checkInLat,
      'check_in_lng': instance.checkInLng,
      'check_out_lat': instance.checkOutLat,
      'check_out_lng': instance.checkOutLng,
    };
