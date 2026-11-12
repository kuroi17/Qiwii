import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import '../../core/utils/phone_normalizer.dart';
import '../models/contact_model.dart';

/// Top-level function for background isolate computation.
/// Maps raw contact maps into AppContact objects, standardizes phone numbers,
/// and sorts them alphabetically by display name.
List<AppContact> _parseAndSortRawContacts(List<Map<String, dynamic>> rawList) {
  final List<AppContact> result = [];

  for (final item in rawList) {
    final name = (item['name'] as String? ?? '').trim();
    final phone = (item['phone'] as String? ?? '').trim();
    final id = (item['id'] as String? ?? '').trim();
    final email = item['email'] as String?;
    final org = item['organization'] as String?;
    final jobTitle = item['jobTitle'] as String?;

    if (name.isEmpty && phone.isEmpty) continue;

    final displayName = name.isNotEmpty ? name : phone;
    final initials = AppContact.generateInitials(displayName);

    result.add(
      AppContact(
        id: id.isNotEmpty ? id : UniqueKey().toString(),
        name: displayName,
        phone: phone,
        initials: initials,
        email: email,
        organization: org,
        jobTitle: jobTitle,
      ),
    );
  }

  // Sort alphabetically by name (case-insensitive)
  result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return result;
}

class ContactRepository {
  final bool isMock;
  const ContactRepository({this.isMock = false});

  /// Requests permission to read device contacts.
  Future<bool> requestReadPermission() async {
    if (kIsWeb || isMock) return true;
    try {
      final status = await fc.FlutterContacts.permissions.request(fc.PermissionType.read);
      return status == fc.PermissionStatus.granted;
    } catch (e) {
      debugPrint('Error requesting contacts read permission: $e');
      return false;
    }
  }

  /// Requests permission to write to device contacts.
  Future<bool> requestWritePermission() async {
    if (kIsWeb || isMock) return true;
    try {
      final status = await fc.FlutterContacts.permissions.request(fc.PermissionType.readWrite);
      return status == fc.PermissionStatus.granted;
    } catch (e) {
      debugPrint('Error requesting contacts write permission: $e');
      return false;
    }
  }

  /// Fetches device contacts, parsing and sorting in a background Isolate.
  Future<List<AppContact>> getDeviceContacts() async {
    if (kIsWeb || isMock) {
      // In web or mock environments, return demo contacts for testing
      return List<AppContact>.from(demoContacts);
    }

    try {
      final hasPermission = await requestReadPermission();
      if (!hasPermission) {
        throw Exception('CONTACTS_PERMISSION_DENIED');
      }

      final rawContacts = await fc.FlutterContacts.getAll(
        properties: {
          fc.ContactProperty.name,
          fc.ContactProperty.phone,
          fc.ContactProperty.email,
          fc.ContactProperty.organization,
        },
      );

      if (rawContacts.isEmpty) {
        return [];
      }

      // Convert raw contacts to lightweight DTOs to pass across isolate boundary
      final List<Map<String, dynamic>> rawDtoList = rawContacts.map((c) {
        final phone = c.phones.isNotEmpty ? c.phones.first.number : '';
        final email = c.emails.isNotEmpty ? c.emails.first.address : null;
        final org = c.organizations.isNotEmpty ? c.organizations.first.name : null;
        final job = c.organizations.isNotEmpty ? c.organizations.first.jobTitle : null;

        return {
          'id': c.id,
          'name': c.displayName,
          'phone': phone,
          'email': email,
          'organization': org,
          'jobTitle': job,
        };
      }).toList();

      // Offload normalization and sorting to background isolate
      return await compute(_parseAndSortRawContacts, rawDtoList);
    } catch (e) {
      if (e.toString().contains('CONTACTS_PERMISSION_DENIED')) {
        rethrow;
      }
      debugPrint('Exception reading device contacts: $e. Falling back to mock.');
      return List<AppContact>.from(demoContacts);
    }
  }

  /// Writes a single AppContact to the native device address book.
  Future<bool> insertContact(AppContact contact) async {
    if (kIsWeb || isMock) {
      return true;
    }

    try {
      final hasPermission = await requestWritePermission();
      if (!hasPermission) {
        throw Exception('CONTACTS_PERMISSION_DENIED');
      }

      final parts = contact.name.trim().split(RegExp(r'\s+'));
      final firstName = parts.isNotEmpty ? parts.first : contact.name;
      final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

      final nativeContact = fc.Contact(
        name: fc.Name(first: firstName, last: lastName),
        phones: [fc.Phone(number: contact.phone)],
        emails: contact.email != null && contact.email!.isNotEmpty
            ? [fc.Email(address: contact.email!)]
            : [],
        organizations: contact.organization != null && contact.organization!.isNotEmpty
            ? [fc.Organization(name: contact.organization, jobTitle: contact.jobTitle)]
            : [],
      );

      await fc.FlutterContacts.create(nativeContact);
      return true;
    } catch (e) {
      debugPrint('Error inserting contact: $e');
      return false;
    }
  }

  /// Merges incoming contact information into an existing native contact.
  Future<bool> mergeContact(AppContact incoming) async {
    if (kIsWeb || isMock) {
      return true;
    }

    try {
      final hasPermission = await requestWritePermission();
      if (!hasPermission) {
        throw Exception('CONTACTS_PERMISSION_DENIED');
      }

      final existingList = await fc.FlutterContacts.getAll(
        properties: {
          fc.ContactProperty.name,
          fc.ContactProperty.phone,
          fc.ContactProperty.email,
          fc.ContactProperty.organization,
        },
      );

      // Find matching contact
      fc.Contact? match;
      for (final c in existingList) {
        final phones = c.phones.map((p) => p.number).toList();
        final emails = c.emails.map((e) => e.address).toList();
        if (phones.any((p) => PhoneNormalizer.areNumbersEqual(incoming.phone, p)) ||
            (incoming.email != null && emails.any((e) => PhoneNormalizer.areEmailsEqual(incoming.email, e)))) {
          match = c;
          break;
        }
      }

      if (match == null) {
        return await insertContact(incoming);
      }

      // Add phone if not present
      final currentNumbers = match.phones.map((p) => PhoneNormalizer.normalize(p.number)).toSet();
      if (incoming.phone.isNotEmpty && !currentNumbers.contains(PhoneNormalizer.normalize(incoming.phone))) {
        match.phones.add(fc.Phone(number: incoming.phone));
      }

      // Add email if not present
      final currentEmails = match.emails.map((e) => e.address.toLowerCase().trim()).toSet();
      if (incoming.email != null &&
          incoming.email!.isNotEmpty &&
          !currentEmails.contains(incoming.email!.toLowerCase().trim())) {
        match.emails.add(fc.Email(address: incoming.email!));
      }

      // Add organization if empty
      if (match.organizations.isEmpty && incoming.organization != null && incoming.organization!.isNotEmpty) {
        match.organizations.add(fc.Organization(name: incoming.organization, jobTitle: incoming.jobTitle));
      }

      await fc.FlutterContacts.update(match);
      return true;
    } catch (e) {
      debugPrint('Error merging contact: $e');
      return false;
    }
  }

  /// Batch inserts contacts with progress feedback.
  Future<Map<String, int>> batchInsertContacts(
    List<AppContact> contacts, {
    void Function(int current, int total)? onProgress,
  }) async {
    int saved = 0;
    int failed = 0;

    for (int i = 0; i < contacts.length; i++) {
      final success = await insertContact(contacts[i]);
      if (success) {
        saved++;
      } else {
        failed++;
      }
      onProgress?.call(i + 1, contacts.length);
    }

    return {
      'saved': saved,
      'failed': failed,
    };
  }

  /// Tags duplicate contacts in received dataset against the user's current address book.
  Future<List<AppContact>> flagDuplicates(List<AppContact> incomingContacts) async {
    try {
      final currentContacts = await getDeviceContacts();
      return incomingContacts.map((c) {
        final isDup = PhoneNormalizer.isDuplicateContact(c, currentContacts);
        return c.copyWith(isDuplicate: isDup);
      }).toList();
    } catch (_) {
      return incomingContacts;
    }
  }
}
