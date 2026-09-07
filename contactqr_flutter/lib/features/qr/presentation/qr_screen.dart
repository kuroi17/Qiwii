import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/crypto_utils.dart';
import '../../../core/utils/network_helper.dart';
import '../../../core/utils/qr_codec.dart';
import '../../../core/widgets/header.dart';
import '../../../core/widgets/shell.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../data/models/contact_model.dart';
import '../../../data/models/transfer_session_model.dart';
import '../../contacts/providers/sender_provider.dart';
import '../../transfer/services/local_transfer_server.dart';
import 'widgets/set_pin_modal.dart';

class QrScreen extends ConsumerStatefulWidget {
  const QrScreen({
    super.key,
    required this.count,
    this.selectedContacts,
  });

  final int count;
  final List<AppContact>? selectedContacts;

  @override
  ConsumerState<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends ConsumerState<QrScreen> {
  late DateTime _expiresAt;
  Timer? _timer;
  Duration _remaining = const Duration(minutes: 15);
  String? _encodedQrData;
  bool _isExpired = false;
  TransferStatus _transferStatus = TransferStatus.waiting;

  LocalTransferServer? _server;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  Future<void> _startSession() async {
    _expiresAt = DateTime.now().add(const Duration(minutes: 15));
    _remaining = const Duration(minutes: 15);
    _isExpired = false;
    _transferStatus = TransferStatus.waiting;

    // Fetch contacts to transfer
    final contactsToTransfer = widget.selectedContacts ??
        ref.read(senderProvider).selectedContacts;

    final actualContacts = contactsToTransfer.isNotEmpty
        ? contactsToTransfer
        : demoContacts.take(widget.count).toList();

    // TIER 1: Direct QR mode (now supports up to 30 contacts seamlessly via minification)
    if (actualContacts.length <= 30) {
      final qrString = QrCodec.encodeDirectContacts(
        actualContacts,
        timeoutMinutes: 15,
      );

      setState(() {
        _encodedQrData = qrString;
      });
    } else {
      // TIER 2: Bulk local network transfer mode for large contact books (>30 contacts)
      final sessionId = 'p2p-${DateTime.now().millisecondsSinceEpoch}';
      final sessionToken = CryptoUtils.generateRandomToken(length: 16);
      final encryptionKey = CryptoUtils.generateSessionKey();
      final localIp = await NetworkHelper.getLocalIpAddress();

      _server = LocalTransferServer(
        contacts: actualContacts,
        sessionId: sessionId,
        sessionToken: sessionToken,
        encryptionKey: encryptionKey,
        onStatusChanged: (status, msg) {
          if (mounted) {
            setState(() {
              _transferStatus = status;
            });
          }
        },
      );

      final port = await _server!.start();

      final session = TransferSession(
        sessionId: sessionId,
        protocolVersion: QrCodec.currentVersion,
        mode: TransferMode.localNetwork,
        contactCount: actualContacts.length,
        createdAt: DateTime.now(),
        expiresAt: _expiresAt,
        host: localIp,
        port: port,
        token: sessionToken,
        encryptionKey: encryptionKey,
      );

      final qrString = QrCodec.encodeSession(session);

      setState(() {
        _encodedQrData = qrString;
      });
    }

    // Start 1-second countdown ticker
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      if (now.isAfter(_expiresAt)) {
        timer.cancel();
        _server?.stop();
        setState(() {
          _isExpired = true;
          _remaining = Duration.zero;
          _transferStatus = TransferStatus.expired;
        });
      } else {
        setState(() {
          _remaining = _expiresAt.difference(now);
        });
      }
    });
  }

  void _onShareWithPinPressed() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SetPinModal(
        onPinConfirmed: (pin) async {
          final contactsToTransfer = widget.selectedContacts ??
              ref.read(senderProvider).selectedContacts;

          final actualContacts = contactsToTransfer.isNotEmpty
              ? contactsToTransfer
              : demoContacts.take(widget.count).toList();

          // Generate clickable, compact PIN-protected transfer URL
          final shareUrl = QrCodec.encodeShareUrl(
            actualContacts,
            timeoutMinutes: 60 * 24, // 24 hours
            pin: pin,
          );

          final shareText = '🔐 Qiwii Secure Contact Transfer\n\n'
              'I shared ${widget.count} contact${widget.count == 1 ? '' : 's'} with you.\n\n'
              '📋 Transfer Link:\n'
              '$shareUrl\n\n'
              '👉 In Qiwii: Copy this message, open Qiwii, and unlock with your 4-digit PIN.';

          if (kIsWeb) {
            await Clipboard.setData(ClipboardData(text: shareText));
            if (mounted) {
              _showShareSuccessModal(shareText, shareUrl, pin);
            }
          } else {
            try {
              await Share.share(
                shareText,
                subject: 'Qiwii Shared Contacts',
              );
            } catch (_) {
              await Clipboard.setData(ClipboardData(text: shareText));
              if (mounted) {
                _showShareSuccessModal(shareText, shareUrl, pin);
              }
            }
          }
        },
      ),
    );
  }

  void _showShareSuccessModal(String shareText, String shareUrl, String pin) {
    bool copied = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Transfer Link Copied!',
                  style: AppTextStyles.display(fontSize: 22, color: AppColors.ink),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'Your PIN-encrypted link is copied to your clipboard. Paste it directly in Messenger, WhatsApp, or any messaging app.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.ink2,
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardWhite,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppColors.accentTint,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.lock_rounded, size: 16, color: AppColors.accent),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Required PIN:',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink2),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              pin,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(color: AppColors.border, height: 1),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.link_rounded, size: 18, color: AppColors.ink3),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              shareUrl,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.ink3,
                                fontFamily: 'monospace',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: shareText));
                          setModalState(() {
                            copied = true;
                          });
                          HapticFeedback.lightImpact();
                        },
                        icon: Icon(copied ? Icons.done_all_rounded : Icons.copy_rounded, size: 18),
                        label: Text(copied ? 'Copied!' : 'Copy Again'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.ink,
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _server?.stop();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _copyQrData() {
    if (_encodedQrData != null) {
      Clipboard.setData(ClipboardData(text: _encodedQrData!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR transfer link copied to clipboard'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSuccess = _transferStatus == TransferStatus.completed;

    return Shell(
      dark: true,
      child: Column(
        children: [
          const Header(title: 'Transfer', light: true),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Spacer(),
                  StatusPill(
                    text: _isExpired
                        ? 'TRANSFER EXPIRED'
                        : isSuccess
                            ? 'TRANSFER COMPLETE'
                            : _transferStatus == TransferStatus.transferring
                                ? 'SENDING DATA'
                                : 'READY TO CONNECT',
                    active: !_isExpired,
                  ),
                  const SizedBox(height: 20),

                  // QR White Card on dark background
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: _isExpired
                          ? SizedBox(
                              height: 190,
                              width: 190,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.timer_off_outlined, size: 48, color: AppColors.accent),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Expired',
                                    style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 16),
                                  ),
                                  const SizedBox(height: 16),
                                  TextButton(
                                    onPressed: _startSession,
                                    child: const Text('Generate new code'),
                                  ),
                                ],
                              ),
                            )
                          : isSuccess
                              ? const SizedBox(
                                  height: 190,
                                  width: 190,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle_rounded, size: 64, color: AppColors.success),
                                      SizedBox(height: 12),
                                      Text(
                                        'Contacts sent!',
                                        style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 16),
                                      ),
                                    ],
                                  ),
                                )
                              : _encodedQrData == null
                                  ? const SizedBox(
                                      height: 190,
                                      width: 190,
                                      child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
                                    )
                                  : GestureDetector(
                                      onTap: _copyQrData,
                                      child: QrImageView(
                                        data: _encodedQrData!,
                                        size: 215,
                                        version: QrVersions.auto,
                                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                                        padding: const EdgeInsets.all(8),
                                        backgroundColor: Colors.white,
                                        eyeStyle: const QrEyeStyle(
                                          eyeShape: QrEyeShape.square,
                                          color: Colors.black,
                                        ),
                                        dataModuleStyle: const QrDataModuleStyle(
                                          dataModuleShape: QrDataModuleShape.square,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                    ),
                  ),

                  // Same-Network Wi-Fi / Hotspot Tip for Tier 2 transfers (>30 contacts)
                  if (widget.count > 30 && !_isExpired && !isSuccess) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.wifi_rounded, color: AppColors.accent, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'Both devices must be on same Wi-Fi / Hotspot',
                            style: TextStyle(
                              color: AppColors.darkSubtitle,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Progress bar countdown
                  if (!_isExpired && !isSuccess) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          '${widget.count} contact${widget.count == 1 ? '' : 's'}',
                          style: const TextStyle(color: AppColors.darkSubtitle, fontSize: 13),
                        ),
                        const Spacer(),
                        Text(
                          _formatDuration(_remaining),
                          style: const TextStyle(color: AppColors.darkSubtitle, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _remaining.inSeconds / (15 * 60),
                        backgroundColor: AppColors.darkBorder,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                        minHeight: 4,
                      ),
                    ),
                  ],

                  const Spacer(),

                  // ── Share with PIN Button ──────────────────────────────
                  if (!_isExpired && !isSuccess)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: InkWell(
                        onTap: _onShareWithPinPressed,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: AppColors.orangeGradient,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accent.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.lock_outline_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 10),
                              Text(
                                'Share with 4-Digit PIN',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
       
        ],
      ),
    );
  }
}
