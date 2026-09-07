import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/shell.dart';
import '../../../data/models/contact_model.dart';
import '../../home/presentation/home_screen.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.count,
    this.skippedCount = 0,
    this.failedCount = 0,
    this.savedContacts = const [],
    this.skippedContacts = const [],
    this.failedContacts = const [],
  });

  final int count;
  final int skippedCount;
  final int failedCount;
  final List<AppContact> savedContacts;
  final List<AppContact> skippedContacts;
  final List<AppContact> failedContacts;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = CurvedAnimation(parent: _animController, curve: Curves.elasticOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSuccess = !(widget.failedCount > 0 && widget.count == 0);

    return Shell(
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Animated Success Circle ─────────────────────────────
                  ScaleTransition(
                    scale: _scaleAnim,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: isSuccess ? AppColors.accentTint : AppColors.error.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isSuccess ? Icons.check_rounded : Icons.close_rounded,
                        color: isSuccess ? AppColors.accent : AppColors.error,
                        size: 34,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Title ───────────────────────────────────────────────
                  Text(
                    isSuccess ? 'Transfer complete' : 'Import failed',
                    style: AppTextStyles.display(
                      fontSize: 26,
                      color: AppColors.ink,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Stat Rows ────────────────────────────────────────────
                  _StatRow(
                    label: 'Saved to device',
                    value: '${widget.count}',
                    valueColor: AppColors.success,
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  _StatRow(
                    label: 'Skipped / unselected',
                    value: '${widget.skippedCount}',
                  ),
                  if (widget.failedCount > 0) ...[
                    const Divider(height: 1, color: AppColors.border),
                    _StatRow(
                      label: 'Failed',
                      value: '${widget.failedCount}',
                      valueColor: AppColors.error,
                    ),
                  ],

                ],
              ),
            ),
          ),
          PrimaryButton(
            label: 'Done',
            icon: Icons.check,
            onPressed: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const HomeScreen()),
              (route) => false,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.ink2, fontSize: 14),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.ink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
