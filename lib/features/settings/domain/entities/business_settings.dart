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
      ];
}
