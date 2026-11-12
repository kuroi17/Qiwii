import 'package:flutter_test/flutter_test.dart';
import 'package:contactqr_flutter/core/utils/phone_normalizer.dart';
import 'package:contactqr_flutter/data/models/contact_model.dart';

void main() {
  group('PhoneNormalizer Tests', () {
    test('normalizes raw phone numbers with formatting', () {
      expect(PhoneNormalizer.normalize('+1 (415) 555-0198'), '+14155550198');
      expect(PhoneNormalizer.normalize('(02) 8123-4567'), '0281234567');
      expect(PhoneNormalizer.normalize('   +63 917 123 4567  '), '+639171234567');
      expect(PhoneNormalizer.normalize(''), '');
    });

    test('extracts core significant digits for comparison', () {
      expect(PhoneNormalizer.extractCoreDigits('+639171234567', minDigits: 9), '171234567');
      expect(PhoneNormalizer.extractCoreDigits('09171234567', minDigits: 9), '171234567');
      expect(PhoneNormalizer.areNumbersEqual('+639171234567', '09171234567'), true);
      expect(PhoneNormalizer.areNumbersEqual('+14155550198', '+14155550198'), true);
      expect(PhoneNormalizer.areNumbersEqual('+14155550198', '+14155550199'), false);
    });

    test('compares emails case-insensitively', () {
      expect(PhoneNormalizer.areEmailsEqual('Test@Example.Com', 'test@example.com'), true);
      expect(PhoneNormalizer.areEmailsEqual('user1@mail.com', 'user2@mail.com'), false);
      expect(PhoneNormalizer.areEmailsEqual(null, 'user@mail.com'), false);
    });

    test('detects duplicate contacts in list correctly', () {
      const existingList = [
        AppContact(id: '1', name: 'John Cruz', phone: '+63 917 123 4567', initials: 'JC', email: 'john@cruz.ph'),
        AppContact(id: '2', name: 'Maria Santos', phone: '+1 415 555 0142', initials: 'MS'),
      ];

      // Phone match
      const candidate1 = AppContact(id: '3', name: 'John C.', phone: '09171234567', initials: 'JC');
      expect(PhoneNormalizer.isDuplicateContact(candidate1, existingList), true);

      // Email match
      const candidate2 = AppContact(id: '4', name: 'Johnny', phone: '+63 999 000 0000', initials: 'J', email: 'JOHN@cruz.ph');
      expect(PhoneNormalizer.isDuplicateContact(candidate2, existingList), true);

      // Distinct contact
      const candidate3 = AppContact(id: '5', name: 'Liam Park', phone: '+1 408 555 0121', initials: 'LP', email: 'liam@park.io');
      expect(PhoneNormalizer.isDuplicateContact(candidate3, existingList), false);

      // Same first name but different phone number should NOT be considered duplicate
      const candidate4 = AppContact(id: '6', name: 'John', phone: '+1 555 999 8888', initials: 'J');
      expect(PhoneNormalizer.isDuplicateContact(candidate4, existingList), false);

      // Exact full name match without conflicting phone/email is a duplicate
      const candidate5 = AppContact(id: '7', name: 'Maria Santos', phone: '', initials: 'MS');
      expect(PhoneNormalizer.isDuplicateContact(candidate5, existingList), true);
    });
  });
}
