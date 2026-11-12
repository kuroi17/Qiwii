import '../../data/models/contact_model.dart';

class PhoneNormalizer {
  /// Strips whitespace, dashes, parentheses, dots, and formatting characters.
  /// Keeps a leading '+' if present.
  static String normalize(String rawPhone) {
    if (rawPhone.trim().isEmpty) return '';
    final trimmed = rawPhone.trim();
    final hasLeadingPlus = trimmed.startsWith('+');
    final digitsOnly = trimmed.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.isEmpty) return '';
    return hasLeadingPlus ? '+$digitsOnly' : digitsOnly;
  }

  /// Returns the core significant digits (last 9 to 10 digits) for fuzzy matching
  /// across local dialing formats vs international country codes.
  static String extractCoreDigits(String phone, {int minDigits = 10}) {
    final normalized = normalize(phone).replaceAll('+', '');
    if (normalized.length <= minDigits) return normalized;
    return normalized.substring(normalized.length - minDigits);
  }

  /// Checks whether two phone numbers represent the same recipient.
  static bool areNumbersEqual(String phoneA, String phoneB) {
    final normA = normalize(phoneA);
    final normB = normalize(phoneB);
    if (normA.isEmpty || normB.isEmpty) return false;
    if (normA == normB) return true;

    final digitsOnlyA = normA.replaceAll('+', '');
    final digitsOnlyB = normB.replaceAll('+', '');

    // Compare 10-digit national significant number (e.g. 9171234567)
    if (digitsOnlyA.length >= 10 && digitsOnlyB.length >= 10) {
      final coreA = digitsOnlyA.substring(digitsOnlyA.length - 10);
      final coreB = digitsOnlyB.substring(digitsOnlyB.length - 10);
      return coreA == coreB;
    }

    // Compare 9-digit format if available
    if (digitsOnlyA.length >= 9 && digitsOnlyB.length >= 9) {
      final coreA = digitsOnlyA.substring(digitsOnlyA.length - 9);
      final coreB = digitsOnlyB.substring(digitsOnlyB.length - 9);
      return coreA == coreB;
    }

    return digitsOnlyA == digitsOnlyB;
  }

  /// Checks whether two emails represent the same email address.
  static bool areEmailsEqual(String? emailA, String? emailB) {
    if (emailA == null || emailB == null) return false;
    final cleanA = emailA.trim().toLowerCase();
    final cleanB = emailB.trim().toLowerCase();
    if (cleanA.isEmpty || cleanB.isEmpty) return false;
    return cleanA == cleanB;
  }

  /// Checks if a contact already exists within a target contact list.
  /// Prevents false positives on common single names (e.g. "Alex") by requiring
  /// matching phone numbers, matching emails, or full matching names where phones do not conflict.
  static bool isDuplicateContact(AppContact candidate, List<AppContact> targetList) {
    final candPhone = normalize(candidate.phone);
    final candEmail = candidate.email?.trim().toLowerCase();
    final candName = candidate.name.trim().toLowerCase();

    for (final existing in targetList) {
      final existPhone = normalize(existing.phone);
      final existEmail = existing.email?.trim().toLowerCase();
      final existName = existing.name.trim().toLowerCase();

      // 1. Phone number match (strongest signal)
      if (candPhone.isNotEmpty && existPhone.isNotEmpty && areNumbersEqual(candidate.phone, existing.phone)) {
        return true;
      }

      // 2. Email match (strong signal)
      if (candEmail != null && candEmail.isNotEmpty &&
          existEmail != null && existEmail.isNotEmpty &&
          areEmailsEqual(candidate.email, existing.email)) {
        return true;
      }

      // 3. If both parties have phone numbers and they do NOT match, they are different people!
      if (candPhone.isNotEmpty && existPhone.isNotEmpty) {
        continue;
      }

      // 4. If both parties have emails and they do NOT match, they are different people!
      if (candEmail != null && candEmail.isNotEmpty && existEmail != null && existEmail.isNotEmpty) {
        continue;
      }

      // 5. Name match (only if neither phone nor email conflicts):
      if (candName.isNotEmpty && existName.isNotEmpty && candName == existName) {
        // Require at least two words (e.g. "John Smith") to avoid false positives on common first names
        final nameParts = candName.split(RegExp(r'\s+'));
        if (nameParts.length >= 2) {
          return true;
        }
        // If single-word name, only match if organization also matches and is non-empty
        if (candidate.organization != null &&
            existing.organization != null &&
            candidate.organization!.trim().isNotEmpty &&
            candidate.organization!.trim().toLowerCase() == existing.organization!.trim().toLowerCase()) {
          return true;
        }
      }
    }
    return false;
  }
}
