import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/qr_codec.dart';
import '../../../core/widgets/shell.dart';
import '../../../data/models/transfer_session_model.dart';
import '../../contacts/presentation/send_screen.dart';
import '../../contacts/providers/sender_provider.dart';
import '../../info/presentation/privacy_policy_screen.dart';
import '../../qr/presentation/scanner_screen.dart';
import 'widgets/action_tile.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  String? _lastCheckedClipboard;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDeepLinks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkClipboardForTransfer();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboardForTransfer();
    }
  }

  Future<void> _initDeepLinks() async {
    if (kIsWeb) return;

    _appLinks = AppLinks();

    // Check if app was opened via link (cold boot)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null && mounted) {
        _handleIncomingUri(initialUri);
      }
    } catch (_) {}

    // Listen for incoming links while app is running
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      if (mounted) {
        _handleIncomingUri(uri);
      }
    });
  }

  void _handleIncomingUri(Uri uri) {
    final uriString = uri.toString();
    if (uriString.contains('qiwii.app/t') ||
        uriString.contains('github.io') ||
        uriString.startsWith('qiwii://') ||
        uriString.startsWith('contactqr://')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ScannerScreen(initialLink: uriString),
        ),
      );
    }
  }

  Future<void> _checkClipboardForTransfer() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboardData?.text?.trim();
      if (text == null || text.isEmpty || text == _lastCheckedClipboard) return;

      if (text.contains('1~') ||
          text.contains('qiwii.app/t') ||
          text.contains('github.io') ||
          text.startsWith('qiwii://') ||
          text.startsWith('contactqr://') ||
          text.contains('Qiwii Secure Contact Transfer')) {
        try {
          final session = QrCodec.decode(text);
          _lastCheckedClipboard = text;
          if (mounted) {
            _showClipboardDetectedModal(text, session);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _showClipboardDetectedModal(String rawText, TransferSession session) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
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
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.mark_email_unread_rounded, color: AppColors.accent, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Transfer Code Detected',
                        style: AppTextStyles.display(fontSize: 18, color: AppColors.ink),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${session.contactCount} contacts ready to import',
                        style: const TextStyle(color: AppColors.ink2, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ScannerScreen(initialLink: rawText),
                    ),
                  );
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final senderState = ref.watch(senderProvider);
    final contactCount = senderState.contacts.length;

    return Shell(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Top Bar ───────────────────────────────────────────
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset(
                            'assets/qiwii_logo.png',
                            width: 38,
                            height: 38,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Center(
                                child: Text(
                                  'Q',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Qiwii',
                          style: AppTextStyles.brand(
                            fontSize: 22,
                            color: AppColors.ink,
                          ),
                        ),
                        const Spacer(),

                        // ── Modern 3-Dots Dropdown Menu ───────────────────
                        Theme(
                          data: Theme.of(context).copyWith(
                            popupMenuTheme: PopupMenuThemeData(
                              color: AppColors.cardWhite,
                              elevation: 10,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: const BorderSide(color: AppColors.border),
                              ),
                            ),
                          ),
                          child: PopupMenuButton<String>(
                            tooltip: 'More options',
                            offset: const Offset(0, 46),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                            icon: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: const Icon(
                                Icons.more_vert_rounded,
                                color: AppColors.ink,
                                size: 20,
                              ),
                            ),
                            onOpened: () => HapticFeedback.selectionClick(),
                            onSelected: (value) async {
                              HapticFeedback.selectionClick();
                              if (value == 'feedback') {
                                final uri = Uri.parse(
                                  'https://github.com/kuroi17/Qiwii-Easy-Contact-Share-QR/issues',
                                );
                                try {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                } catch (_) {
                                  // Fallback if unable to launch browser
                                }
                              } else if (value == 'privacy') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const PrivacyPolicyScreen(),
                                  ),
                                );
                              } else if (value == 'licenses') {
                                showLicensePage(
                                  context: context,
                                  applicationName: 'Qiwii - Easy Contact Share QR',
                                  applicationVersion: '1.0.0+1',
                                  applicationIcon: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.asset(
                                        'assets/qiwii_logo.png',
                                        width: 52,
                                        height: 52,
                                        errorBuilder: (context, error, stackTrace) => Container(
                                          width: 52,
                                          height: 52,
                                          decoration: BoxDecoration(
                                            color: AppColors.accent,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Center(
                                            child: Text(
                                              'Q',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 24,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'feedback',
                                child: Row(
                                  children: const [
                                    Icon(Icons.feedback_outlined, size: 19, color: AppColors.ink),
                                    SizedBox(width: 12),
                                    Text(
                                      'Help & Feedback',
                                      style: TextStyle(
                                        color: AppColors.ink,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'privacy',
                                child: Row(
                                  children: const [
                                    Icon(Icons.privacy_tip_outlined, size: 19, color: AppColors.ink),
                                    SizedBox(width: 12),
                                    Text(
                                      'Privacy Policy',
                                      style: TextStyle(
                                        color: AppColors.ink,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'licenses',
                                child: Row(
                                  children: const [
                                    Icon(Icons.article_outlined, size: 19, color: AppColors.ink),
                                    SizedBox(width: 12),
                                    Text(
                                      'Licenses',
                                      style: TextStyle(
                                        color: AppColors.ink,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // ── Middle Hero Section (Centered & Prominent) ─────────
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Less typing.\nMore connecting.',
                            style: AppTextStyles.display(
                              fontSize: 26,
                              color: AppColors.ink,
                            ),
                          ),

                          const SizedBox(height: 28),

                          // ── Card 1: Send Contacts (Large Hero Card) ────
                          ActionTile(
                            icon: Icons.north_east_rounded,
                            title: 'Send contacts',
                            subtitle:
                                'Choose contacts you want to share.',
                            badgeText: contactCount > 0 ? '$contactCount contacts' : null,
                            isPrimary: true,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SendScreen()),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // ── Card 2: Receive Contacts (Large Hero Card) ──
                          ActionTile(
                            icon: Icons.qr_code_scanner_rounded,
                            title: 'Receive contacts',
                            subtitle: 'Scan a QR code to receive contacts.',
                            isPrimary: false,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ScannerScreen()),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Bottom Trust Footer ───────────────────────────────
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Center(
                        child: Text(
                          'Zero cloud. Nothing leaves your device.',
                          style: TextStyle(
                            color: AppColors.ink3,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
