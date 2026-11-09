class AccountUser {
  const AccountUser({
    required this.displayName,
    required this.email,
    this.id,
    this.photoUrl,
  });

  final String? id;
  final String displayName;
  final String email;
  final String? photoUrl;
}
