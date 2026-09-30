// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'delete_absen.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeleteAbsen _$DeleteAbsenFromJson(Map<String, dynamic> json) => DeleteAbsen(
      message: json['message'] as String?,
      data: json['data'] == null
          ? null
          : AbsenData.fromJson(json['data'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$DeleteAbsenToJson(DeleteAbsen instance) =>
    <String, dynamic>{
      'message': instance.message,
      'data': instance.data?.toJson(),
    };
