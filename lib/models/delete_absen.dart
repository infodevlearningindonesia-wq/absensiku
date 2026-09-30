import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';
import 'package:absensiku/models/checkout_absen.dart';

part 'delete_absen.g.dart';

DeleteAbsen deleteAbsenFromJson(String str) =>
    DeleteAbsen.fromJson(json.decode(str) as Map<String, dynamic>);

String deleteAbsenToJson(DeleteAbsen data) => json.encode(data.toJson());

@JsonSerializable()
class DeleteAbsen {
  @JsonKey(name: "message")
  final String? message;
  @JsonKey(name: "data")
  final AbsenData? data;

  DeleteAbsen({
    this.message,
    this.data,
  });

  factory DeleteAbsen.fromJson(Map<String, dynamic> json) =>
      _$DeleteAbsenFromJson(json);

  Map<String, dynamic> toJson() => _$DeleteAbsenToJson(this);
}
