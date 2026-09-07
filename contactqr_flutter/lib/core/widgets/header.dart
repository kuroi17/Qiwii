import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

class Header extends StatelessWidget {
  const Header({
    super.key,
    required this.title,
    this.light = false,
    this.onBack,
    this.trailing,
  });

  final String title;
  final bool light;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: Row(
      children: [
        IconButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            if (onBack != null) {
              onBack!();
            } else {
              Navigator.pop(context);
            }
          },
          icon: Icon(
            Icons.arrow_back_ios_new,
            size: 18,
            color: light ? Colors.white70 : AppColors.ink2,
          ),
        ),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: light ? Colors.white : AppColors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (trailing != null)
          trailing!
        else
          const SizedBox(width: 48),
      ],
    ),
  );
}
