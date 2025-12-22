import 'user.dart';

class AuthPayload {
  const AuthPayload({required this.token, required this.user});

  final String token;
  final User user;

  factory AuthPayload.fromJson(Map<String, dynamic> json) => AuthPayload(
        token: json['token'] as String,
        user: User.fromJson(json['user'] as Map<String, dynamic>),
      );
}
