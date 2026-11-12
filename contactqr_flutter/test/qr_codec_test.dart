import 'package:flutter_test/flutter_test.dart';
import 'package:contactqr_flutter/core/utils/qr_codec.dart';
import 'package:contactqr_flutter/data/models/contact_model.dart';
import 'package:contactqr_flutter/data/models/transfer_session_model.dart';

void main() {
  group('QrCodec Tests', () {
    test('encodes and decodes session round-trip with https URL format', () {
      final originalSession = TransferSession(
        sessionId: 'sess-12345',
        protocolVersion: 1,
        mode: TransferMode.localNetwork,
        contactCount: 15,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        host: '192.168.1.50',
        port: 8080,
        token: 'auth-token-xyz',
        encryptionKey: 'aes-key-base64',
      );

      final encoded = QrCodec.encodeSession(originalSession);
      expect(encoded.contains('#'), true);

      final decoded = QrCodec.decode(encoded);
      expect(decoded.sessionId, 'sess-12345');
      expect(decoded.contactCount, 15);
      expect(decoded.mode, TransferMode.localNetwork);
      expect(decoded.host, '192.168.1.50');
      expect(decoded.port, 8080);
      expect(decoded.token, 'auth-token-xyz');
      expect(decoded.encryptionKey, 'aes-key-base64');
    });

    test('encodes and unpacks direct contact payload', () {
      const contacts = [
        AppContact(id: '1', name: 'Maya Chen', phone: '+14155550198', initials: 'MC', email: 'maya@chen.com'),
        AppContact(id: '2', name: 'Jordan Rivera', phone: '+14155550142', initials: 'JR'),
      ];

      final encoded = QrCodec.encodeDirectContacts(contacts, timeoutMinutes: 5);
      final session = QrCodec.decode(encoded);

      expect(session.mode, TransferMode.direct);
      expect(session.contactCount, 2);

      final unpacked = QrCodec.decodeDirectPayload(session.directPayload);
      expect(unpacked.length, 2);
      expect(unpacked[0].name, 'Maya Chen');
      expect(unpacked[0].phone, '+14155550198');
      expect(unpacked[0].email, 'maya@chen.com');
      expect(unpacked[1].name, 'Jordan Rivera');
    });

    test('encodes 14 contacts into compact clickable URL and decodes cleanly with PIN', () {
      final contacts = List.generate(
        14,
        (i) => AppContact(
          id: '$i',
          name: 'Contact $i',
          phone: '+6391700000$i',
          email: 'user$i@qiwii.app',
          initials: 'C$i',
        ),
      );
      const pin = '4321';

      final shareUrl = QrCodec.encodeShareUrl(contacts, pin: pin);
      expect(shareUrl.contains('#'), true);

      // Verify decode directly from URL
      final sessionFromUrl = QrCodec.decode(shareUrl);
      expect(sessionFromUrl.contactCount, 14);
      expect(sessionFromUrl.isPinProtected, true);

      // Verify decode from chat message containing text + URL
      final chatMessage = '🔐 Qiwii Secure Contact Transfer\n'
          'I shared 14 contacts with you.\n'
          'Tap link:\n$shareUrl\n'
          'Enter PIN to unlock.';
      final sessionFromChat = QrCodec.decode(chatMessage);
      expect(sessionFromChat.contactCount, 14);
      expect(sessionFromChat.isPinProtected, true);

      // Unpack with correct PIN
      final unpacked = QrCodec.decodeDirectPayload(
        sessionFromChat.directPayload,
        pin: pin,
        salt: sessionFromChat.pinSalt,
      );
      expect(unpacked.length, 14);
      expect(unpacked[0].name, 'Contact 0');
      expect(unpacked[13].name, 'Contact 13');
    });

    test('throws QrExpiredException when QR code is expired', () {
      final expiredSession = TransferSession(
        sessionId: 'expired-123',
        protocolVersion: 1,
        mode: TransferMode.direct,
        contactCount: 1,
        createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
        expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      final encoded = QrCodec.encodeSession(expiredSession);
      expect(() => QrCodec.decode(encoded), throwsA(isA<QrExpiredException>()));
    });

    test('rejects unrecognized or non-Qiwii strings', () {
      expect(() => QrCodec.decode(''), throwsA(isA<QrProtocolException>()));
      expect(() => QrCodec.decode('https://google.com'), throwsA(isA<QrProtocolException>()));
      expect(() => QrCodec.decode('{"app":"otherapp"}'), throwsA(isA<QrProtocolException>()));
    });

    test('correctly handles delimiter characters, newlines, and secondary phones', () {
      const contacts = [
        AppContact(
          id: '1',
          name: 'Jane | Senior Dev\nSpecialist',
          phone: '+1 555 1234',
          email: 'jane|dev@corp.com',
          organization: 'Acme | Labs',
          jobTitle: 'Lead | Architect',
          secondaryPhone: '+1 555 5678',
          notes: 'Met at conference.\nGreat contact!',
          initials: 'JS',
        ),
      ];

      final encoded = QrCodec.encodeDirectContacts(contacts);
      final session = QrCodec.decode(encoded);
      final unpacked = QrCodec.decodeDirectPayload(session.directPayload);

      expect(unpacked.length, 1);
      expect(unpacked[0].name, 'Jane | Senior Dev\nSpecialist');
      expect(unpacked[0].phone, '+1 555 1234');
      expect(unpacked[0].email, 'jane|dev@corp.com');
      expect(unpacked[0].organization, 'Acme | Labs');
      expect(unpacked[0].jobTitle, 'Lead | Architect');
      expect(unpacked[0].secondaryPhone, '+1 555 5678');
      expect(unpacked[0].notes, 'Met at conference.\nGreat contact!');
    });

    test('creates and parses multi-frame animated QR chunks cleanly', () {
      final manyContacts = List.generate(
        35,
        (i) => AppContact(
          id: 'id_$i',
          name: 'Colleague Number $i',
          phone: '+63 917 555 00$i',
          email: 'colleague_$i@enterprise.corp',
          organization: 'MegaCorp International $i',
          jobTitle: 'Senior Vice President of Engineering $i',
          initials: 'CN',
        ),
      );

      final directUrl = QrCodec.encodeDirectContacts(manyContacts);
      final session = QrCodec.decode(directUrl);

      final frames = QrCodec.createMultiFrameQrs(session, maxChunkSize: 300);
      expect(frames.length > 1, true);

      final Map<int, String> collectedChunks = {};
      int? expectedTotal;

      for (final frame in frames) {
        expect(QrCodec.isMultiFrame(frame), true);
        final part = QrCodec.parseMultiFrame(frame);
        expectedTotal = part.total;
        collectedChunks[part.part] = part.chunk;
      }

      expect(collectedChunks.length, expectedTotal);
      final assembled = List.generate(expectedTotal!, (i) => collectedChunks[i + 1]!).join();
      final unpacked = QrCodec.decodeDirectPayload(assembled);
      expect(unpacked.length, 35);
      expect(unpacked[0].name, 'Colleague Number 0');
      expect(unpacked[34].name, 'Colleague Number 34');
    });

    test('decodes legacy demo format for testing', () {
      final session = QrCodec.decode('contactqr://session/demo-5');
      expect(session.sessionId, 'demo-5');
      expect(session.contactCount, 5);
    });
  });
}
