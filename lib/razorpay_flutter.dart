import 'package:flutter/services.dart';
import 'package:eventify/eventify.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io' show Platform;

class Razorpay {
  // Response codes from platform
  static const _CODE_PAYMENT_SUCCESS = 0;
  static const _CODE_PAYMENT_ERROR = 1;
  static const _CODE_PAYMENT_EXTERNAL_WALLET = 2;

  // Event names
  static const EVENT_PAYMENT_SUCCESS = 'payment.success';
  static const EVENT_PAYMENT_ERROR = 'payment.error';
  static const EVENT_EXTERNAL_WALLET = 'payment.external_wallet';

  // Payment error codes
  static const NETWORK_ERROR = 0;
  static const INVALID_OPTIONS = 1;
  static const PAYMENT_CANCELLED = 2;
  static const TLS_ERROR = 3;
  static const INCOMPATIBLE_PLUGIN = 4;
  static const UNKNOWN_ERROR = 100;

  static const MethodChannel _channel = const MethodChannel('razorpay_flutter');

  // EventEmitter instance used for communication
  late EventEmitter _eventEmitter;

  Razorpay() {
    _eventEmitter = new EventEmitter();
  }

  /// Opens Razorpay checkout
  void open(Map<String, dynamic> options) async {
    Map<String, dynamic> validationResult = _validateOptions(options);

    if (!validationResult['success']) {
      _handleResult({
        'type': _CODE_PAYMENT_ERROR,
        'data': {'code': INVALID_OPTIONS, 'message': validationResult['message']}
      });
      return;
    }

    if (Platform.isAndroid) {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      _channel.invokeMethod('setPackageName', packageInfo.packageName);
    }

    var response = await _channel.invokeMethod('open', options);
    _handleResult(response);
  }

  /// Handles checkout response from platform
  void _handleResult(Map<dynamic, dynamic> response) {
    String eventName;
    Map<dynamic, dynamic>? data = response["data"];

    dynamic payload;

    switch (response['type']) {
      case _CODE_PAYMENT_SUCCESS:
        eventName = EVENT_PAYMENT_SUCCESS;
        payload = PaymentSuccessResponse.fromMap(data!);
        break;

      case _CODE_PAYMENT_ERROR:
        eventName = EVENT_PAYMENT_ERROR;
        payload = PaymentFailureResponse.fromMap(data!);
        break;

      case _CODE_PAYMENT_EXTERNAL_WALLET:
        eventName = EVENT_EXTERNAL_WALLET;
        payload = ExternalWalletResponse.fromMap(data!);
        break;

      default:
        eventName = 'error';
        payload = PaymentFailureResponse(UNKNOWN_ERROR, 'An unknown error occurred.', null, data: {});
    }

    _eventEmitter.emit(eventName, null, payload);
  }

  /// Registers event listeners for payment events
  void on(String event, Function handler) {
    EventCallback cb = (event, cont) {
      handler(event.eventData);
    };
    _eventEmitter.on(event, null, cb);
    _resync();
  }

  /// Clears all event listeners
  void clear() {
    _eventEmitter.clear();
  }

  /// Retrieves lost responses from platform
  void _resync() async {
    var response = await _channel.invokeMethod('resync');
    if (response != null) {
      _handleResult(response);
    }
  }

  /// Validate payment options
  static Map<String, dynamic> _validateOptions(Map<String, dynamic> options) {
    var key = options['key'];
    if (key == null) {
      return {'success': false, 'message': 'Key is required. Please check if key is present in options.'};
    }
    return {'success': true};
  }
}

class PaymentSuccessResponse {
  String? paymentId;
  String? orderId;
  String? signature;
  Map<dynamic, dynamic> data;

  PaymentSuccessResponse(this.paymentId, this.orderId, this.signature, {required this.data});

  static PaymentSuccessResponse fromMap(Map<dynamic, dynamic> map) {
    String? paymentId = map["razorpay_payment_id"];
    String? signature = map["razorpay_signature"];
    String? orderId = map["razorpay_order_id"];

    return new PaymentSuccessResponse(paymentId, orderId, signature, data: map);
  }
}

class PaymentFailureResponse {
  int? code;
  String? message;
  Map<dynamic, dynamic>? error;
  Map<dynamic, dynamic> data;

  PaymentFailureResponse(this.code, this.message, this.error, {required this.data});

  static PaymentFailureResponse fromMap(Map<dynamic, dynamic> map) {
    var code = map["code"] as int?;
    var message = map["message"] as String?;
    var responseBody;

    if (responseBody is Map<dynamic, dynamic>) {
      return new PaymentFailureResponse(code, message, responseBody, data: map);
    } else {
      Map<dynamic, dynamic> errorMap = new Map<dynamic, dynamic>();
      errorMap["reason"] = responseBody;
      return new PaymentFailureResponse(code, message, responseBody, data: map);
    }
  }
}

class ExternalWalletResponse {
  String? walletName;
  Map<dynamic, dynamic> data;

  ExternalWalletResponse(this.walletName, {required this.data});

  static ExternalWalletResponse fromMap(Map<dynamic, dynamic> map) {
    var walletName = map["external_wallet"] as String?;
    return new ExternalWalletResponse(walletName, data: map);
  }
}
