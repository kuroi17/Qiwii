import 'dart:convert';
import 'package:archive/archive.dart';
import '../../data/models/contact_model.dart';
import '../../data/models/transfer_session_model.dart';
import 'crypto_utils.dart';

class QrProtocolException implements Exception {
  final String message;
  const QrProtocolException(this.message);
  @override
  String toString() => message;
}

class QrExpiredException extends QrProtocolException {
  const QrExpiredException([super.message = 'This transfer QR code has expired.']);
}

class QrPinRequiredException extends QrProtocolException {
  final TransferSession session;
  const QrPinRequiredException(this.session, [super.message = 'This transfer is protected with a 4-digit PIN.']);
}

class MultiFramePart {
  final int version;
  final int part;
  final int total;
  final String sessionId;
  final String? salt;
  final String chunk;

  const MultiFramePart({
    required this.version,
    required this.part,
    required this.total,
    required this.sessionId,
    this.salt,
    required this.chunk,
  });
}

class QrCodec {
  static const String webBaseUrl = 'https://kuroi17.github.io/Qiwii/#';
  static const String shortDomainUrl = 'https://qiwii.app/t#';
  static const String protocolScheme = 'contactqr://';
  static const String qiwiiScheme = 'qiwii://';
  static const String protocolName = 'contactqr';
  static const String qiwiiName = 'qiwii';
  static const int currentVersion = 1;

  static String _escapeField(String? s) {
    if (s == null || s.isEmpty) return '';
    return s.replaceAll(r'\', r'\\').replaceAll('|', r'\|').replaceAll('\n', r'\n');
  }

  static String _unescapeField(String s) {
    return s.replaceAll(r'\|', '|').replaceAll(r'\n', '\n').replaceAll(r'\\', r'\');
  }

  static List<String> _splitEscapedLine(String line) {
    final List<String> parts = [];
    final StringBuffer current = StringBuffer();
    bool isEscaped = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (isEscaped) {
        current.write(char);
        isEscaped = false;
      } else if (char == r'\') {
        current.write(char);
        isEscaped = true;
      } else if (char == '|') {
        parts.add(_unescapeField(current.toString()));
        current.clear();
      } else {
        current.write(char);
      }
    }
    parts.add(_unescapeField(current.toString()));
    return parts;
  }

  /// Encodes list of contacts into ultra-compact delimited format with escaping
  static String _compactContacts(List<AppContact> contacts) {
    final lines = contacts.map((c) {
      final n = _escapeField(c.name);
      final p = _escapeField(c.phone);
      final e = _escapeField(c.email);
      final o = _escapeField(c.organization);
      final j = _escapeField(c.jobTitle);
      final p2 = _escapeField(c.secondaryPhone);
      final notes = _escapeField(c.notes);
      if ((p2.isNotEmpty) || (notes.isNotEmpty)) {
        return '$n|$p|$e|$o|$j|$p2|$notes';
      }
      return '$n|$p|$e|$o|$j';
    }).join('\n');
    return '1~$lines';
  }

  /// Compresses input string using Deflate/Zlib and encodes to Base64Url
  static String _compressString(String input) {
    final rawBytes = utf8.encode(input);
    final compressed = ZLibEncoder().encode(rawBytes);
    return 'z~${base64UrlEncode(compressed).replaceAll('=', '')}';
  }

  /// Decompresses Base64Url string, with automatic fallback for plain text / legacy formats
  static String _decompressString(String input) {
    String payload = input;
    bool isZlib = false;
    if (payload.startsWith('z~')) {
      isZlib = true;
      payload = payload.substring(2);
    }

    String normalized = payload.replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    final bytes = base64.decode(normalized);

    if (isZlib) {
      try {
        final decompressed = ZLibDecoder().decodeBytes(bytes);
        return utf8.decode(decompressed);
      } catch (_) {}
    }

    // Try zlib magic bytes header check
    if (bytes.length >= 2 && bytes[0] == 0x78) {
      try {
        final decompressed = ZLibDecoder().decodeBytes(bytes);
        return utf8.decode(decompressed);
      } catch (_) {}
    }

    return utf8.decode(bytes);
  }

  /// Restores contacts from compact delimited format or fallback JSON
  static List<AppContact> _expandContacts(String raw) {
    if (raw.startsWith('1~')) {
      final lines = raw.substring(2).split('\n');
      final result = <AppContact>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final parts = line.contains(r'\') ? _splitEscapedLine(line) : line.split('|');
        final name = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : 'Unnamed';
        final phone = parts.length > 1 ? parts[1] : '';
        final email = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
        final org = parts.length > 3 && parts[3].isNotEmpty ? parts[3] : null;
        final job = parts.length > 4 && parts[4].isNotEmpty ? parts[4] : null;
        final p2 = parts.length > 5 && parts[5].isNotEmpty ? parts[5] : null;
        final notes = parts.length > 6 && parts[6].isNotEmpty ? parts[6] : null;
        result.add(AppContact(
          id: 'c_${DateTime.now().microsecondsSinceEpoch}_${phone.hashCode}_${result.length}',
          name: name,
          phone: phone,
          email: email,
          organization: org,
          jobTitle: job,
          secondaryPhone: p2,
          notes: notes,
          initials: AppContact.generateInitials(name),
        ));
      }
      return result;
    }

    // Fallback to JSON array
    final dynamic parsed = jsonDecode(raw);
    if (parsed is List) {
      return parsed.map((item) {
        if (item is Map<String, dynamic>) {
          return _unminifyContact(item);
        }
        return AppContact.fromJson(item as Map<String, dynamic>);
      }).toList();
    }
    return [];
  }

  /// Restores a full AppContact from minified JSON map
  static AppContact _unminifyContact(Map<String, dynamic> m) {
    final name = m['n'] as String? ?? m['name'] as String? ?? 'Unnamed';
    final phone = m['p'] as String? ?? m['phone'] as String? ?? '';
    final email = m['e'] as String? ?? m['email'] as String?;
    final org = m['o'] as String? ?? m['organization'] as String? ?? m['company'] as String? ?? m['c'] as String?;
    final job = m['j'] as String? ?? m['jobTitle'] as String?;
    final p2 = m['p2'] as String? ?? m['secondaryPhone'] as String?;
    final notes = m['notes'] as String?;
    final initials = m['initials'] as String? ?? AppContact.generateInitials(name);
    return AppContact(
      id: m['id'] as String? ?? 'c_${DateTime.now().microsecondsSinceEpoch}_${phone.hashCode}',
      name: name,
      phone: phone,
      email: email,
      organization: org,
      jobTitle: job,
      secondaryPhone: p2,
      notes: notes,
      initials: initials,
    );
  }

  /// Encodes a TransferSession into an ultra-short compact payload string.
  /// Encodes real expiration timestamp for exact expiration enforcement.
  static String encodeSession(TransferSession session) {
    if (session.mode == TransferMode.direct && session.directPayload != null) {
      // Ultra-short direct format: <version>~<expMs>~<contactCount>~<pinSaltOrEmpty>~<payload>
      final salt = session.pinSalt ?? '';
      final expMs = session.expiresAt.millisecondsSinceEpoch;
      return '$webBaseUrl${session.protocolVersion}~$expMs~${session.contactCount}~$salt~${session.directPayload}';
    }

    final payload = {
      'a': 'q',
      'v': session.protocolVersion,
      'm': 'p',
      'id': session.sessionId,
      'cnt': session.contactCount,
      'exp': session.expiresAt.millisecondsSinceEpoch,
      if (session.host != null) 'host': session.host,
      if (session.port != null) 'port': session.port,
      if (session.token != null) 'token': session.token,
      if (session.encryptionKey != null) 'k': session.encryptionKey,
    };

    final jsonString = jsonEncode(payload);
    final base64Payload = base64UrlEncode(utf8.encode(jsonString)).replaceAll('=', '');
    return '$webBaseUrl$base64Payload';
  }

  /// Splits a Direct session into multiple sequential frames for Animated / Multi-Frame QR.
  static List<String> createMultiFrameQrs(
    TransferSession session, {
    int maxChunkSize = 500,
  }) {
    String payload = session.directPayload ?? '';
    // If directPayload is a full URL or encoded session string, extract the inner data
    if (payload.contains('#') || (payload.contains('~') && payload.startsWith('1~'))) {
      try {
        final decodedSession = decode(payload);
        payload = decodedSession.directPayload ?? payload;
      } catch (_) {}
    }

    if (payload.length <= maxChunkSize) {
      return [encodeSession(session)];
    }

    final totalParts = (payload.length / maxChunkSize).ceil();
    final List<String> frames = [];
    final salt = session.pinSalt ?? '';

    for (int i = 0; i < totalParts; i++) {
      final start = i * maxChunkSize;
      final end = (start + maxChunkSize < payload.length) ? start + maxChunkSize : payload.length;
      final chunk = payload.substring(start, end);
      final frameUrl = '$webBaseUrl${session.protocolVersion}~m~${i + 1}~$totalParts~${session.sessionId}~$salt~$chunk';
      frames.add(frameUrl);
    }
    return frames;
  }

  /// Generates a clickable universal link for sharing contacts with optional 4-digit PIN protection.
  static String encodeShareUrl(
    List<AppContact> contacts, {
    int timeoutMinutes = 60 * 24, // 24 hours
    String? pin,
  }) {
    return encodeDirectContacts(
      contacts,
      timeoutMinutes: timeoutMinutes,
      pin: pin,
    );
  }

  /// Convenience method to generate an ultra-compact Direct QR transfer for datasets, optionally PIN-protected.
  /// Uses genuine Deflate/Zlib compression for dramatic space savings.
  static String encodeDirectContacts(
    List<AppContact> contacts, {
    int timeoutMinutes = 60,
    String? customSessionId,
    String? pin,
  }) {
    final compactDataString = _compactContacts(contacts);

    String compressedData;
    String? pinSalt;
    bool isPinProtected = false;

    if (pin != null && pin.trim().isNotEmpty) {
      pinSalt = CryptoUtils.generateRandomToken(length: 12);
      final derivedKey = CryptoUtils.deriveKeyFromPin(pin.trim(), pinSalt);
      final preCompressed = _compressString(compactDataString);
      compressedData = CryptoUtils.encryptPayload(preCompressed, derivedKey);
      isPinProtected = true;
    } else {
      compressedData = _compressString(compactDataString);
    }

    final session = TransferSession(
      sessionId: customSessionId ?? 'direct-${DateTime.now().millisecondsSinceEpoch}',
      protocolVersion: currentVersion,
      mode: TransferMode.direct,
      contactCount: contacts.length,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(Duration(minutes: timeoutMinutes)),
      directPayload: compressedData,
      isPinProtected: isPinProtected,
      pinSalt: pinSalt,
    );

    return encodeSession(session);
  }

  static String _extractPayload(String rawData) {
    final trimmed = rawData.trim();
    if (trimmed.isEmpty) return '';

    if (trimmed.contains('#')) {
      final afterHash = trimmed.split('#').last.trim();
      if (afterHash.isNotEmpty) {
        return afterHash.split('&').first.split(RegExp(r'\s+')).first;
      }
    } else if (trimmed.contains('qiwii.app/share?d=')) {
      return trimmed.split('qiwii.app/share?d=').last.split('&').first.split(RegExp(r'\s+')).first;
    } else if (trimmed.contains('://')) {
      return trimmed.split('://').last.split(RegExp(r'\s+')).first;
    } else {
      final urlMatch = RegExp(r'https?:\/\/[^\s#]+#([^\s]+)').firstMatch(trimmed);
      if (urlMatch != null) {
        return urlMatch.group(1)!;
      }
    }
    return trimmed;
  }

  /// Checks if scanned QR data is part of a Multi-Frame / Animated QR sequence
  static bool isMultiFrame(String rawData) {
    final extracted = _extractPayload(rawData);
    final parts = extracted.split('~');
    return parts.length >= 6 && parts[1] == 'm';
  }

  /// Parses a MultiFramePart from an animated frame QR
  static MultiFramePart parseMultiFrame(String rawData) {
    final extracted = _extractPayload(rawData);
    final parts = extracted.split('~');
    if (parts.length < 6 || parts[1] != 'm') {
      throw const QrProtocolException('Invalid multi-frame QR code');
    }
    return MultiFramePart(
      version: int.tryParse(parts[0]) ?? 1,
      part: int.tryParse(parts[2]) ?? 1,
      total: int.tryParse(parts[3]) ?? 1,
      sessionId: parts[4],
      salt: parts[5].isNotEmpty ? parts[5] : null,
      chunk: parts.sublist(6).join('~'),
    );
  }

  /// Decodes and validates raw QR data or shared URL into a TransferSession.
  /// Supports short delimited format, web URLs, deep links, raw base64, base64Url, and legacy formats.
  static TransferSession decode(String rawData) {
    final trimmed = rawData.trim();
    if (trimmed.isEmpty) {
      throw const QrProtocolException('Scanned data is empty.');
    }

    // Check for legacy demo format
    if (trimmed.contains('session/demo-')) {
      final countStr = trimmed.split('demo-').last.split(' ').first;
      final count = int.tryParse(countStr) ?? 3;
      return TransferSession(
        sessionId: 'demo-$count',
        protocolVersion: currentVersion,
        mode: TransferMode.direct,
        contactCount: count,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(minutes: 60)),
      );
    }

    // Check for direct JSON object
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        return _parseJsonMap(jsonDecode(trimmed) as Map<String, dynamic>);
      } catch (_) {}
    }

    final extractedPayload = _extractPayload(trimmed);

    // Check for ultra-short delimited format:
    // Format A (with real expiry): <version>~<expMs>~<contactCount>~<pinSaltOrEmpty>~<payload>
    // Format B (legacy): <version>~<contactCount>~<pinSaltOrEmpty>~<payload>
    if (extractedPayload.contains('~')) {
      final parts = extractedPayload.split('~');
      if (parts.length >= 5 && parts[1] != 'm') {
        final version = int.tryParse(parts[0]) ?? 1;
        final expTimestamp = int.tryParse(parts[1]);
        DateTime expiresAt = DateTime.now().add(const Duration(hours: 24));
        if (expTimestamp != null) {
          expiresAt = DateTime.fromMillisecondsSinceEpoch(expTimestamp);
          if (DateTime.now().isAfter(expiresAt)) {
            throw const QrExpiredException();
          }
        }
        final count = int.tryParse(parts[2]) ?? 0;
        final salt = parts[3].isNotEmpty ? parts[3] : null;
        final directData = parts.sublist(4).join('~');

        return TransferSession(
          sessionId: 'direct-${DateTime.now().millisecondsSinceEpoch}',
          protocolVersion: version,
          mode: TransferMode.direct,
          contactCount: count,
          createdAt: DateTime.now(),
          expiresAt: expiresAt,
          directPayload: directData,
          isPinProtected: salt != null && salt.isNotEmpty,
          pinSalt: salt,
        );
      } else if (parts.length == 4 && parts[1] != 'm') {
        final version = int.tryParse(parts[0]) ?? 1;
        final count = int.tryParse(parts[1]) ?? 0;
        final salt = parts[2].isNotEmpty ? parts[2] : null;
        final directData = parts.sublist(3).join('~');

        return TransferSession(
          sessionId: 'direct-${DateTime.now().millisecondsSinceEpoch}',
          protocolVersion: version,
          mode: TransferMode.direct,
          contactCount: count,
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(hours: 24)),
          directPayload: directData,
          isPinProtected: salt != null && salt.isNotEmpty,
          pinSalt: salt,
        );
      }
    }

    // Fallback: Base64 JSON decoding
    String jsonString;
    try {
      String normalized = extractedPayload.replaceAll('-', '+').replaceAll('_', '/');
      while (normalized.length % 4 != 0) {
        normalized += '=';
      }
      final decodedBytes = base64.decode(normalized);
      jsonString = utf8.decode(decodedBytes);
    } catch (e) {
      try {
        String normalized = extractedPayload;
        while (normalized.length % 4 != 0) {
          normalized += '=';
        }
        final decodedBytes = base64Url.decode(normalized);
        jsonString = utf8.decode(decodedBytes);
      } catch (_) {
        throw const QrProtocolException('Invalid or corrupted Qiwii transfer code.');
      }
    }

    Map<String, dynamic> map;
    try {
      map = jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (_) {
      throw const QrProtocolException('Corrupted Qiwii transfer payload.');
    }

    return _parseJsonMap(map);
  }

  static TransferSession _parseJsonMap(Map<String, dynamic> map) {
    final app = map['a'] as String? ?? map['app'] as String?;
    if (app != null && app != 'q' && app != qiwiiName && app != protocolName) {
      throw const QrProtocolException('Not a valid Qiwii transfer code.');
    }

    final version = map['v'] as int? ?? map['ver'] as int? ?? map['version'] as int? ?? 1;
    if (version > currentVersion) {
      throw QrProtocolException('This QR code requires a newer version of Qiwii (v$version).');
    }

    final expTimestamp = map['exp'] as int?;
    DateTime expiresAt;
    if (expTimestamp != null) {
      expiresAt = DateTime.fromMillisecondsSinceEpoch(expTimestamp);
      if (DateTime.now().isAfter(expiresAt)) {
        throw const QrExpiredException();
      }
    } else if (map['expiresAt'] != null) {
      expiresAt = DateTime.tryParse(map['expiresAt'] as String) ??
          DateTime.now().add(const Duration(minutes: 60));
      if (DateTime.now().isAfter(expiresAt)) {
        throw const QrExpiredException();
      }
    } else {
      expiresAt = DateTime.now().add(const Duration(minutes: 60));
    }

    final modeStr = map['m'] as String? ?? map['mode'] as String?;
    final isDirect = modeStr == 'd' || modeStr == 'direct';
    final count = map['cnt'] as int? ?? map['count'] as int? ?? 0;
    final isPin = map['pin'] == 1 || map['pin'] == true || map['isPinProtected'] == true;
    final salt = map['s'] as String? ?? map['salt'] as String? ?? map['pinSalt'] as String?;
    final directPayload = map['d'] as String? ?? map['data'] as String? ?? map['directPayload'] as String?;
    final encKey = map['k'] as String? ?? map['key'] as String? ?? map['encryptionKey'] as String?;

    return TransferSession(
      sessionId: map['id'] as String? ?? map['sessionId'] as String? ?? 'session-${DateTime.now().millisecondsSinceEpoch}',
      protocolVersion: version,
      mode: isDirect ? TransferMode.direct : TransferMode.localNetwork,
      contactCount: count,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
      host: map['host'] as String?,
      port: map['port'] as int?,
      token: map['token'] as String?,
      encryptionKey: encKey,
      directPayload: directPayload,
      isPinProtected: isPin,
      pinSalt: salt,
    );
  }

  /// Decodes direct contact payload if session contains embedded data.
  /// If [pin] is provided, uses PIN key derivation to decrypt the payload.
  static List<AppContact> decodeDirectPayload(String? payloadData, {String? pin, String? salt}) {
    if (payloadData == null || payloadData.isEmpty) return [];

    try {
      String decompressedString;
      if (pin != null && pin.trim().isNotEmpty && salt != null) {
        final derivedKey = CryptoUtils.deriveKeyFromPin(pin.trim(), salt);
        final decryptedRaw = CryptoUtils.decryptPayload(payloadData, derivedKey);
        if (decryptedRaw.startsWith('z~')) {
          decompressedString = _decompressString(decryptedRaw);
        } else {
          decompressedString = decryptedRaw;
        }
      } else {
        decompressedString = _decompressString(payloadData);
      }

      return _expandContacts(decompressedString);
    } catch (e) {
      if (pin != null) {
        throw const QrProtocolException('Incorrect 4-digit PIN. Unable to unlock contacts.');
      }
      throw const QrProtocolException('Failed to unpack embedded contact data.');
    }
  }
}
