import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/card_box.dart';
import '../../../core/widgets/header.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/shell.dart';
import '../../qr/presentation/qr_screen.dart';
import '../providers/sender_provider.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key, required this.ids});
  final List<String> ids;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final senderState = ref.watch(senderProvider);
    final chosen = senderState.contacts.where((c) => ids.contains(c.id)).toList();

    return Shell(
      child: Column(
        children: [
          Header(title: 'Review (${chosen.length})'),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Expanded(
                    child: CardBox(
                      child: ListView.separated(
                        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                        itemCount: chosen.length,
                        separatorBuilder: (_, _) => const Divider(color: AppColors.border, height: 1),
                        itemBuilder: (_, index) {
                          final c = chosen[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: AppColors.accentTint,
                                  child: Text(
                                    c.initials,
                                    style: const TextStyle(
                                      color: AppColors.accentDark,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.name,
                                        style: const TextStyle(
                                          color: AppColors.ink,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        c.phone,
                                        style: const TextStyle(
                                          color: AppColors.ink2,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          PrimaryButton(
            label: 'Generate QR',
            icon: Icons.qr_code_rounded,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => QrScreen(
                  count: chosen.length,
                  selectedContacts: chosen,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
