/// GSTIN, phone and email checks for Indian customers.
class Validators {
  Validators._();

  static const _gstChars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static final _gstPattern = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');

  static const Map<String, String> gstStates = {
    '01': 'Jammu & Kashmir',
    '02': 'Himachal Pradesh',
    '03': 'Punjab',
    '04': 'Chandigarh',
    '05': 'Uttarakhand',
    '06': 'Haryana',
    '07': 'Delhi',
    '08': 'Rajasthan',
    '09': 'Uttar Pradesh',
    '10': 'Bihar',
    '11': 'Sikkim',
    '12': 'Arunachal Pradesh',
    '13': 'Nagaland',
    '14': 'Manipur',
    '15': 'Mizoram',
    '16': 'Tripura',
    '17': 'Meghalaya',
    '18': 'Assam',
    '19': 'West Bengal',
    '20': 'Jharkhand',
    '21': 'Odisha',
    '22': 'Chhattisgarh',
    '23': 'Madhya Pradesh',
    '24': 'Gujarat',
    '25': 'Daman & Diu',
    '26': 'Dadra & Nagar Haveli and Daman & Diu',
    '27': 'Maharashtra',
    '28': 'Andhra Pradesh (old)',
    '29': 'Karnataka',
    '30': 'Goa',
    '31': 'Lakshadweep',
    '32': 'Kerala',
    '33': 'Tamil Nadu',
    '34': 'Puducherry',
    '35': 'Andaman & Nicobar Islands',
    '36': 'Telangana',
    '37': 'Andhra Pradesh',
    '38': 'Ladakh',
    '97': 'Other Territory',
    '99': 'Centre Jurisdiction',
  };

  static String cleanGstin(String input) => input.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');

  /// Null when valid (or empty); otherwise the problem in plain words.
  static String? gstinError(String input) {
    final g = cleanGstin(input);
    if (g.isEmpty) return null;
    if (g.length != 15) return 'GSTIN must be 15 characters (now ${g.length}).';
    if (!_gstPattern.hasMatch(g)) return 'GSTIN format is not correct.';
    if (!gstStates.containsKey(g.substring(0, 2))) {
      return 'GSTIN state code ${g.substring(0, 2)} is not valid.';
    }
    if (_gstCheckChar(g.substring(0, 14)) != g[14]) {
      return 'GSTIN check digit is wrong. Please re-check the number.';
    }
    return null;
  }

  static String? gstinState(String input) {
    final g = cleanGstin(input);
    if (g.length < 2) return null;
    return gstStates[g.substring(0, 2)];
  }

  static String _gstCheckChar(String first14) {
    var sum = 0;
    for (var i = 0; i < 14; i++) {
      final value = _gstChars.indexOf(first14[i]);
      final product = value * (i.isEven ? 1 : 2);
      sum += product ~/ 36 + product % 36;
    }
    return _gstChars[(36 - sum % 36) % 36];
  }

  /// Last 10 digits of an Indian mobile number, or '' if not found.
  static String mobileDigits(String input) {
    var d = input.replaceAll(RegExp(r'\D'), '');
    if (d.length > 10 && d.startsWith('91')) d = d.substring(d.length - 10);
    if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
    return d.length >= 10 ? d.substring(d.length - 10) : d;
  }

  static String? mobileError(String input) {
    final d = input.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return 'Enter the mobile number.';
    final m = mobileDigits(input);
    if (m.length != 10 || !RegExp(r'^[6-9]').hasMatch(m)) {
      return 'Enter a valid 10-digit mobile number.';
    }
    return null;
  }

  /// "9876543210" -> "+91 98765 43210"
  static String formatMobile(String input) {
    final m = mobileDigits(input);
    if (m.length != 10) return input.trim();
    return '+91 ${m.substring(0, 5)} ${m.substring(5)}';
  }

  static String? emailError(String input) {
    final e = input.trim();
    if (e.isEmpty) return null;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) return 'Email address is not valid.';
    return null;
  }

  static String? pinError(String input) {
    final p = input.trim();
    if (p.isEmpty) return null;
    if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(p)) return '6-digit PIN';
    return null;
  }
}
