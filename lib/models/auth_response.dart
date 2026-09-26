import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';

part 'auth_response.g.dart';

AuthResponseModel authResponseModelFromJson(String str) =>
    AuthResponseModel.fromJson(json.decode(str));

String authResponseModelToJson(AuthResponseModel data) =>
    json.encode(data.toJson());

@JsonSerializable()
class AuthResponseModel {
  @JsonKey(name: "message")
  final String? message;
  @JsonKey(name: "data")
  final AuthData? data;

  AuthResponseModel({
    this.message,
    this.data,
  });

  factory AuthResponseModel.fromJson(Map<String, dynamic> json) =>
      _$AuthResponseModelFromJson(json);

  Map<String, dynamic> toJson() => _$AuthResponseModelToJson(this);
}

@JsonSerializable()
class AuthData {
  @JsonKey(name: "token")
  final String? token;
  @JsonKey(name: "user")
  final UserModel? user;

  AuthData({
    this.token,
    this.user,
  });

  factory AuthData.fromJson(Map<String, dynamic> json) =>
      _$AuthDataFromJson(json);

  Map<String, dynamic> toJson() => _$AuthDataToJson(this);
}

@JsonSerializable()
class UserModel {
  @JsonKey(name: "id")
  final int? id;
  @JsonKey(name: "name")
  final String? name;
  @JsonKey(name: "email")
  final String? email;
  @JsonKey(name: "email_verified_at")
  final String? emailVerifiedAt;
  @JsonKey(name: "created_at")
  final String? createdAt;
  @JsonKey(name: "updated_at")
  final String? updatedAt;

  UserModel({
    this.id,
    this.name,
    this.email,
    this.emailVerifiedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);

  Map<String, dynamic> toJson() => _$UserModelToJson(this);
}

typedef LoginResponseModel = AuthResponseModel;
typedef RegisterResponseModel = AuthResponseModel;