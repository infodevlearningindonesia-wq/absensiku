import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';

part 'checkout_absen.g.dart';

CheckoutAbsen checkoutAbsenFromJson(String str) =>
    CheckoutAbsen.fromJson(json.decode(str) as Map<String, dynamic>);

String checkoutAbsenToJson(CheckoutAbsen data) => json.encode(data.toJson());

@JsonSerializable()
class CheckoutAbsen {
  @JsonKey(name: "message")
  final String? message;
  @JsonKey(name: "data")
  final AbsenData? data;

  CheckoutAbsen({
    this.message,
    this.data,
  });

  factory CheckoutAbsen.fromJson(Map<String, dynamic> json) =>
      _$CheckoutAbsenFromJson(json);

  Map<String, dynamic> toJson() => _$CheckoutAbsenToJson(this);
}

@JsonSerializable()
class AbsenData {
  @JsonKey(name: "id")
  final int? id;
  @JsonKey(name: "user_id")
  final int? userId;
  @JsonKey(name: "check_in")
  final String? checkIn;
  @JsonKey(name: "check_in_location")
  final String? checkInLocation;
  @JsonKey(name: "check_in_address")
  final String? checkInAddress;
  @JsonKey(name: "check_out")
  final String? checkOut;
  @JsonKey(name: "check_out_location")
  final String? checkOutLocation;
  @JsonKey(name: "check_out_address")
  final String? checkOutAddress;
  @JsonKey(name: "status")
  final String? status;
  @JsonKey(name: "alasan_izin")
  final String? alasanIzin;
  @JsonKey(name: "created_at")
  final String? createdAt;
  @JsonKey(name: "updated_at")
  final String? updatedAt;
  @JsonKey(name: "check_in_lat")
  final dynamic checkInLat;
  @JsonKey(name: "check_in_lng")
  final dynamic checkInLng;
  @JsonKey(name: "check_out_lat")
  final dynamic checkOutLat;
  @JsonKey(name: "check_out_lng")
  final dynamic checkOutLng;

  AbsenData({
    this.id,
    this.userId,
    this.checkIn,
    this.checkInLocation,
    this.checkInAddress,
    this.checkOut,
    this.checkOutLocation,
    this.checkOutAddress,
    this.status,
    this.alasanIzin,
    this.createdAt,
    this.updatedAt,
    this.checkInLat,
    this.checkInLng,
    this.checkOutLat,
    this.checkOutLng,
  });

  factory AbsenData.fromJson(Map<String, dynamic> json) =>
      _$AbsenDataFromJson(json);

  Map<String, dynamic> toJson() => _$AbsenDataToJson(this);
}
