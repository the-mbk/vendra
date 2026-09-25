// ══════════════════════════════════════════════════════════════
// Vendra App - User Model
// ══════════════════════════════════════════════════════════════

class UserModel {
  final int id;
  final String fullName;
  final String email;
  final String? phone;
  final String role;
  final double walletBalance;
  final int? vendorId;
  final String? storeName;
  final String? storeAddress;
  final bool? isApproved;
  final String? cnic;
  final double? storeLat;
  final double? storeLng;
  final String? vehicleType;
  final bool? isOnline;
  /// An admin issued a temporary password: ask for a new one before continuing
  final bool mustChangePassword;
  final String? createdAt;
  /// Total Rs. currently held in the platform escrow pool (all users).
  final double platformEscrowBalance;

  UserModel({
    required this.id,
    required this.fullName,
    required this.email,
    this.phone,
    required this.role,
    this.walletBalance = 0.0,
    this.vendorId,
    this.storeName,
    this.storeAddress,
    this.isApproved,
    this.cnic,
    this.storeLat,
    this.storeLng,
    this.vehicleType,
    this.isOnline,
    this.mustChangePassword = false,
    this.createdAt,
    this.platformEscrowBalance = 0,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      fullName: json['fullName'] ?? json['full_name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'],
      role: json['role'] ?? 'customer',
      walletBalance: _toDouble(json['walletBalance'] ?? json['wallet_balance']),
      vendorId: json['vendorId'] ?? json['vendor_id'],
      storeName: json['storeName'] ?? json['store_name'],
      storeAddress: json['storeAddress'] ?? json['store_address'],
      isApproved: json['isApproved'] ?? json['is_approved'],
      cnic: json['cnic'],
      storeLat: json['storeLat'] == null ? null : _toDouble(json['storeLat']),
      storeLng: json['storeLng'] == null ? null : _toDouble(json['storeLng']),
      vehicleType: json['vehicleType'] ?? json['vehicle_type'],
      isOnline: json['isOnline'] ?? json['is_online'],
      mustChangePassword: json['mustChangePassword'] ?? json['must_change_password'] ?? false,
      createdAt: json['createdAt'] ?? json['created_at'],
      platformEscrowBalance: _toDouble(json['platformEscrowBalance'] ?? json['platform_escrow_balance']),
    );
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'fullName': fullName,
    'email': email,
    'role': role,
    'walletBalance': walletBalance,
    'vendorId': vendorId,
    'storeName': storeName,
  };

  bool get isVendor => role == 'vendor';
  bool get isCustomer => role == 'customer';
  bool get isRider => role == 'rider';

  UserModel copyWith({
    double? walletBalance,
    double? platformEscrowBalance,
  }) {
    return UserModel(
      id: id,
      fullName: fullName,
      email: email,
      phone: phone,
      role: role,
      walletBalance: walletBalance ?? this.walletBalance,
      vendorId: vendorId,
      storeName: storeName,
      storeAddress: storeAddress,
      isApproved: isApproved,
      cnic: cnic,
      storeLat: storeLat,
      storeLng: storeLng,
      vehicleType: vehicleType,
      isOnline: isOnline,
      mustChangePassword: mustChangePassword,
      createdAt: createdAt,
      platformEscrowBalance: platformEscrowBalance ?? this.platformEscrowBalance,
    );
  }
}
