// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'register_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RegisterModel _$RegisterModelFromJson(Map<String, dynamic> json) =>
    RegisterModel(
      name: json['name'] as String?,
      email: json['email'] as String?,
      password: json['password'] as String?,
      passwordConfirmation: json['password_confirmation'] as String?,
    );

Map<String, dynamic> _$RegisterModelToJson(RegisterModel instance) {
  final val = <String, dynamic>{
    'name': instance.name,
    'email': instance.email,
    'password': instance.password,
  };
  if (instance.passwordConfirmation != null) {
    val['password_confirmation'] = instance.passwordConfirmation;
  }
  return val;
}
