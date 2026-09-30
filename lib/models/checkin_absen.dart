import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';

part 'checkin_absen.g.dart';

CheckinAbsen checkinAbsenFromJson(String str) =>
    CheckinAbsen.fromJson(json.decode(str) as Map<String, dynamic>);

String checkinAbsenToJson(CheckinAbsen data) => json.encode(data.toJson());

@JsonSerializable()
class CheckinAbsen {
  @JsonKey(name: "message")
  final String? message;
  @JsonKey(name: "data")
  final dynamic data;

  CheckinAbsen({
    this.message,
    this.data,
  });

  factory CheckinAbsen.fromJson(Map<String, dynamic> json) =>
      _$CheckinAbsenFromJson(json);

  Map<String, dynamic> toJson() => _$CheckinAbsenToJson(this);
}
