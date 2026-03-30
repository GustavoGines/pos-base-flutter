import 'package:equatable/equatable.dart';

class BusinessSettings extends Equatable {
  final String? companyName;
  final String? address;
  final String? phone;
  final String? taxId;
  final String? receiptFooterMessage;
  final String printerType;
  final String? printerComPort;
  final String? printerIpAddress;
  final String? printerIpPort;
  final String? comPortScale;
  final String? licenseStatus;
  final String? licensePlanType;
  final String? licensePlanMode; // 'saas' or 'lifetime'
  final List<String>? licenseAllowedAddons;
  final String? lastLicenseCheck;
  final String? serverTime; // Timestamp from the server
  final DateTime? licenseExpiresAt;
  final DateTime? licenseNextPaymentAt;
  final String? licenseManageUrl;
  final bool isLifetime;

  const BusinessSettings({
    this.companyName,
    this.address,
    this.phone,
    this.taxId,
    this.receiptFooterMessage,
    this.printerType = 'none',
    this.printerComPort,
    this.printerIpAddress,
    this.printerIpPort,
    this.comPortScale,
    this.licenseStatus,
    this.licensePlanType,
    this.licensePlanMode,
    this.licenseAllowedAddons,
    this.lastLicenseCheck,
    this.serverTime,
    this.licenseExpiresAt,
    this.licenseNextPaymentAt,
    this.licenseManageUrl,
    this.isLifetime = false,
  });

  @override
  List<Object?> get props => [
        companyName,
        address,
        phone,
        taxId,
        receiptFooterMessage,
        printerType,
        printerComPort,
        printerIpAddress,
        printerIpPort,
        comPortScale,
        licenseStatus,
        licensePlanType,
        licensePlanMode,
        licenseAllowedAddons,
        lastLicenseCheck,
        serverTime,
        licenseExpiresAt,
        licenseNextPaymentAt,
        licenseManageUrl,
        isLifetime,
      ];
}
