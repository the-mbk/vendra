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
  /// Vendor's store pictures (relative /uploads paths); null when not set
  final String? storeLogoUrl;
  final String? storeCoverUrl;
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
  /// Riders: pending | approved | rejected (documents checked by an admin)
  final String? riderApprovalStatus;
  final String? riderRejectionReason;
  final RiderDocuments? riderDocuments;
  /// Vendors: the shop staff member using this session (null = the store owner)
  final StaffInfo? staff;
  /// Vendors: what this session may do (products.view, products.manage, pos,
  /// orders.view, orders.fulfil, ledger, owner). Empty = not loaded / other roles
  final List<String> permissions;

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
    this.storeLogoUrl,
    this.storeCoverUrl,
    this.isApproved,
    this.cnic,
    this.storeLat,
    this.storeLng,
    this.vehicleType,
    this.isOnline,
    this.mustChangePassword = false,
    this.createdAt,
    this.platformEscrowBalance = 0,
    this.riderApprovalStatus,
    this.riderRejectionReason,
    this.riderDocuments,
    this.staff,
    this.permissions = const [],
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
      storeLogoUrl: json['storeLogoUrl'] ?? json['store_logo_url'],
      storeCoverUrl: json['storeCoverUrl'] ?? json['store_cover_url'],
      isApproved: json['isApproved'] ?? json['is_approved'],
      cnic: json['cnic'],
      storeLat: json['storeLat'] == null ? null : _toDouble(json['storeLat']),
      storeLng: json['storeLng'] == null ? null : _toDouble(json['storeLng']),
      vehicleType: json['vehicleType'] ?? json['vehicle_type'],
      isOnline: json['isOnline'] ?? json['is_online'],
      mustChangePassword: json['mustChangePassword'] ?? json['must_change_password'] ?? false,
      createdAt: json['createdAt'] ?? json['created_at'],
      platformEscrowBalance: _toDouble(json['platformEscrowBalance'] ?? json['platform_escrow_balance']),
      riderApprovalStatus: json['riderApprovalStatus'],
      riderRejectionReason: json['riderRejectionReason'],
      riderDocuments: json['riderDocuments'] is Map
          ? RiderDocuments.fromJson(Map<String, dynamic>.from(json['riderDocuments']))
          : null,
      staff: json['staff'] is Map ? StaffInfo.fromJson(Map<String, dynamic>.from(json['staff'])) : null,
      permissions: (json['permissions'] as List?)?.map((p) => p.toString()).toList() ?? const [],
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

  /// Riders deliver only once an admin has approved their documents
  bool get isRiderApproved => riderApprovalStatus == null || riderApprovalStatus == 'approved';

  /// Vendor permission check: the owner (no staff) may do everything
  bool can(String permission) => staff == null || permissions.contains(permission);
  bool get isStoreOwner => isVendor && staff == null;

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
      storeLogoUrl: storeLogoUrl,
      storeCoverUrl: storeCoverUrl,
      isApproved: isApproved,
      cnic: cnic,
      storeLat: storeLat,
      storeLng: storeLng,
      vehicleType: vehicleType,
      isOnline: isOnline,
      mustChangePassword: mustChangePassword,
      createdAt: createdAt,
      platformEscrowBalance: platformEscrowBalance ?? this.platformEscrowBalance,
      riderApprovalStatus: riderApprovalStatus,
      riderRejectionReason: riderRejectionReason,
      riderDocuments: riderDocuments,
      staff: staff,
      permissions: permissions,
    );
  }
}

class RiderDocuments {
  final String? cnic;
  final String? licenseNumber;
  final String? vehicleNumber;

  const RiderDocuments({this.cnic, this.licenseNumber, this.vehicleNumber});

  factory RiderDocuments.fromJson(Map<String, dynamic> json) => RiderDocuments(
        cnic: json['cnic'],
        licenseNumber: json['licenseNumber'],
        vehicleNumber: json['vehicleNumber'],
      );
}

/// A cashier / packer / inventory manager signed in on the shop's device with a PIN
class StaffInfo {
  final int id;
  final String fullName;
  final String role; // cashier | packer | inventory_manager

  const StaffInfo({required this.id, required this.fullName, required this.role});

  factory StaffInfo.fromJson(Map<String, dynamic> json) => StaffInfo(
        id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}') ?? 0,
        fullName: json['fullName'] ?? '',
        role: json['role'] ?? '',
      );

  String get roleLabel => switch (role) {
        'cashier' => 'Cashier',
        'packer' => 'Packer',
        'inventory_manager' => 'Inventory Manager',
        _ => role,
      };
}
