class User {
  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    this.pharmacyId,
  });

  final int id;
  final String username;
  final String email;
  final String role;
  final int? pharmacyId;

  bool get isOwner => role == 'owner';

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as int,
        username: json['username'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
        pharmacyId: json['pharmacy_id'] as int?,
      );
}
