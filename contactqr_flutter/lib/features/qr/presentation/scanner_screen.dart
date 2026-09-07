import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_dart_decoder/qr_code_dart_decoder.dart' as qrd;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/qr_codec.dart';
import '../../../core/widgets/header.dart';
import '../../../core/widgets/shell.dart';
import '../../../core/widgets/transfer_error_dialog.dart';
import '../../../data/models/contact_model.dart';
import '../../../data/models/transfer_session_model.dart';
import '../../contacts/providers/sender_provider.dart';
import '../../import/presentation/received_screen.dart';
import '../../import/providers/receiver_provider.dart';
import '../../transfer/providers/transfer_provider.dart';
import '../../transfer/services/local_transfer_client.dart';
import 'widgets/enter_pin_modal.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  final String? initialLink;
  const ScannerScreen({super.key, this.initialLink});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> with SingleTickerProviderStateMixin {
  MobileScannerController? _controller;
  bool _isProcessing = false;
  bool _isDownloading = false;
  String _downloadStatus = 'Downloading contacts...';
  bool _permissionDenied = false;
  bool _torchEnabled = false;
  String? _lastScannedPayload;
  DateTime? _lastScannedTime;

  @override
  void initState() {
    super.initState();
    _initScanner();
    if (widget.initialLink != null && widget.initialLink!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _processQrString(widget.initialLink!);
      });
    }
  }

  Future<void> _initScanner() async {
    if (kIsWeb) {
      _controller = MobileScannerController(
        facing: CameraFacing.front,
        torchEnabled: false,
        formats: const [BarcodeFormat.qrCode],
      );
      if (mounted) setState(() {});
      return;
    }

    final status = await Permission.camera.request();
    if (status.isGranted) {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        detectionTimeoutMs: 200,
        facing: CameraFacing.back,
        torchEnabled: false,
        formats: const [BarcodeFormat.qrCode],
        returnImage: false,
      );
      if (mounted) setState(() {});
    } else {
      if (mounted) {
        setState(() {
          _permissionDenied = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing || _isDownloading) return;

    final barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.isNotEmpty) {
        final now = DateTime.now();
        if (_lastScannedPayload == rawValue &&
            _lastScannedTime != null &&
            now.difference(_lastScannedTime!).inMilliseconds < 3000) {
          return; // Prevent infinite re-scan loop within 3 seconds of the exact same barcode
        }
        _lastScannedPayload = rawValue;
        _lastScannedTime = now;
        _processQrString(rawValue);
        break;
      }
    }
  }

  Future<void> _pickAndScanFromGallery() async {
    if (_isProcessing || _isDownloading) return;
    HapticFeedback.selectionClick();

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );

      if (pickedFile == null) return;

      setState(() {
        _isProcessing = true;
      });

      String? detectedQr;

      // 1. If on native mobile, try mobile_scanner first
      if (!kIsWeb && _controller != null) {
        try {
          final barcodes = await _controller?.analyzeImage(pickedFile.path);
          if (barcodes != null && barcodes.barcodes.isNotEmpty) {
            detectedQr = barcodes.barcodes.first.rawValue;
          }
        } catch (_) {}
      }

      // 2. Cross-platform & Web fallback: decode image bytes with qr_code_dart_decoder
      if (detectedQr == null || detectedQr.isEmpty) {
        try {
          final bytes = await pickedFile.readAsBytes();
          final decoder = qrd.QrCodeDartDecoder(formats: [qrd.BarcodeFormat.qrCode]);
          final result = await decoder.decodeFile(bytes);
          if (result != null && result.text.isNotEmpty) {
            detectedQr = result.text;
          }
        } catch (_) {}
      }

      if (detectedQr != null && detectedQr.isNotEmpty) {
        await _processQrString(detectedQr);
        return;
      }

      _showErrorSnackBar('No QR code detected in this photo. Please select an image with a clear Qiwii QR code.');
      _resetScanner();
    } catch (e) {
      _showErrorSnackBar('Error reading image: $e');
      _resetScanner();
    }
  }

  Future<void> _showPasteLinkDialog() async {
    HapticFeedback.selectionClick();
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final clipboardText = clipboardData?.text?.trim() ?? '';

    if (!mounted) return;

    final controller = TextEditingController(text: clipboardText);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Paste Transfer Link',
              style: AppTextStyles.display(fontSize: 22, color: AppColors.ink),
            ),
            const SizedBox(height: 6),
            const Text(
              'Paste the link or message you received in Messenger, WhatsApp, or SMS.',
              style: TextStyle(color: AppColors.ink2, fontSize: 13.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              style: const TextStyle(fontSize: 14, color: AppColors.ink),
              decoration: InputDecoration(
                hintText: 'https://qiwii.app/t#...',
                filled: true,
                fillColor: AppColors.cardWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.accent, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final text = controller.text.trim();
                  if (text.isNotEmpty) {
                    Navigator.pop(ctx);
                    _processQrString(text);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Unlock & Import Contacts', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _processQrString(String rawData) async {
    setState(() {
      _isProcessing = true;
    });

    HapticFeedback.mediumImpact();

    try {
      final session = QrCodec.decode(rawData);

      List<AppContact> contacts = [];

      if (session.mode == TransferMode.direct) {
        if (session.isPinProtected) {
          // Prompt for 4-digit PIN with 5-attempt limit
          final unlocked = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (ctx) => EnterPinModal(
              onPinSubmitted: (pin) async {
                try {
                  final decoded = QrCodec.decodeDirectPayload(
                    session.directPayload,
                    pin: pin,
                    salt: session.pinSalt,
                  );
                  if (decoded.isNotEmpty) {
                    contacts = decoded;
                    return true;
                  }
                  return false;
                } catch (e) {
                  return false;
                }
              },
            ),
          );

          if (unlocked != true) {
            _resetScanner();
            return;
          }
        } else if (session.directPayload != null && session.directPayload!.isNotEmpty) {
          contacts = QrCodec.decodeDirectPayload(session.directPayload);
        } else {
          contacts = demoContacts.take(session.contactCount > 0 ? session.contactCount : 6).toList();
        }
      } else {
        // TIER 2: Bulk Local Network Transfer mode
        setState(() {
          _isDownloading = true;
          _downloadStatus = 'Downloading ${session.contactCount} contacts from sender...';
        });

        final client = ref.read(transferClientProvider);
        contacts = await client.fetchContactsFromSender(session);
      }

      // Flag duplicates against receiver's address book
      final contactRepo = ref.read(contactRepositoryProvider);
      final flaggedContacts = await contactRepo.flagDuplicates(contacts);

      ref.read(receiverProvider.notifier).setReceivedContacts(flaggedContacts);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ReceivedScreen()),
        );
      }
    } on QrExpiredException {
      _showErrorSnackBar('This transfer QR code has expired. Please ask the sender to generate a new code.');
      _resetScanner();
    } on QrProtocolException catch (e) {
      _showErrorSnackBar(e.message);
      _resetScanner();
    } on NetworkTransferException catch (e) {
      _resetScanner();
      if (mounted) {
        TransferErrorDialog.show(
          context,
          title: 'Connection Failed',
          message: e.message,
          primaryActionText: 'Try Scanning Again',
          onPrimaryAction: () => _resetScanner(),
        );
      }
    } catch (e) {
      _resetScanner();
      _showErrorSnackBar('Transfer failed: $e');
    }
  }

  void _resetScanner() {
    if (mounted) {
      setState(() {
        _isProcessing = false;
        _isDownloading = false;
      });
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _simulateWebScan() {
    final sampleEncoded = QrCodec.encodeDirectContacts(
      demoContacts.take(4).toList(),
      timeoutMinutes: 60,
      customSessionId: 'web-simulated-transfer',
    );
    _processQrString(sampleEncoded);
  }

  @override
  Widget build(BuildContext context) {
    return Shell(
      dark: true,
      child: Column(
        children: [
          const Header(title: 'Scan QR', light: true),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 8),

                  if (_isDownloading)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(color: AppColors.accent),
                            const SizedBox(height: 24),
                            Text(
                              _downloadStatus,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_permissionDenied)
                    Expanded(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.darkSurface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.darkBorder),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.camera_alt_outlined, size: 48, color: AppColors.accent),
                              const SizedBox(height: 16),
                              const Text(
                                'Camera Access Needed',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Qiwii needs the camera to scan the transfer QR code.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.darkSubtitle, fontSize: 14),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton(
                                onPressed: openAppSettings,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Open Settings'),
                              ),
                              const SizedBox(height: 12),
                              TextButton.icon(
                                onPressed: _pickAndScanFromGallery,
                                icon: const Icon(Icons.photo_library_outlined, color: AppColors.accent),
                                label: const Text('Upload from Gallery instead', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: Stack(
                        children: [
                          // Camera Preview Viewport
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              width: double.infinity,
                              color: Colors.black,
                              child: _controller == null
                                  ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                                  : MobileScanner(
                                      controller: _controller!,
                                      onDetect: _onDetect,
                                      errorBuilder: (context, error) {
                                        return GestureDetector(
                                          onTap: _simulateWebScan,
                                          child: Center(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Icon(Icons.videocam_off_outlined, size: 64, color: Colors.white70),
                                                const SizedBox(height: 12),
                                                Text(
                                                  'Webcam: ${error.errorCode.name}',
                                                  style: const TextStyle(color: AppColors.accent, fontSize: 13),
                                                ),
                                                const SizedBox(height: 8),
                                                const Text(
                                                  'Tap to simulate scan',
                                                  style: TextStyle(color: AppColors.darkSubtitle, fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ),

                          // Corner bracket reticle (center of frame)
                          Center(
                            child: SizedBox(
                              width: 220,
                              height: 220,
                              child: CustomPaint(
                                painter: _CornerBracketPainter(
                                  color: AppColors.accent,
                                  bracketLength: 28,
                                  strokeWidth: 3,
                                ),
                              ),
                            ),
                          ),

                          // Floating torch button (top-right)
                          if (!kIsWeb)
                            Positioned(
                              top: 12,
                              right: 12,
                              child: GestureDetector(
                                onTap: () {
                                  _controller?.toggleTorch();
                                  setState(() => _torchEnabled = !_torchEnabled);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Icon(
                                    _torchEnabled ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                                    color: _torchEnabled ? AppColors.accent : Colors.white70,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // ── Actions Row: Upload from Gallery + Paste Link ──────
                  if (!_isDownloading) ...[
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _isProcessing ? null : _pickAndScanFromGallery,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 13),
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
                                  Icon(Icons.photo_library_outlined, color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Upload QR',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: _isProcessing ? null : _showPasteLinkDialog,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 13),
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
                                  Icon(Icons.link_rounded, color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Paste Link',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
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
                    const SizedBox(height: 12),
                  ],

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws 4 L-shaped corner brackets as a scan reticle
class _CornerBracketPainter extends CustomPainter {
  const _CornerBracketPainter({
    required this.color,
    this.bracketLength = 24,
    this.strokeWidth = 3,
  });

  final Color color;
  final double bracketLength;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final bl = bracketLength;

    // Top-left
    canvas.drawLine(Offset(0, bl), Offset(0, 0), paint);
    canvas.drawLine(Offset(0, 0), Offset(bl, 0), paint);
    // Top-right
    canvas.drawLine(Offset(w - bl, 0), Offset(w, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, bl), paint);
    // Bottom-left
    canvas.drawLine(Offset(0, h - bl), Offset(0, h), paint);
    canvas.drawLine(Offset(0, h), Offset(bl, h), paint);
    // Bottom-right
    canvas.drawLine(Offset(w - bl, h), Offset(w, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - bl), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
