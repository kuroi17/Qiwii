import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class SetPinModal extends StatefulWidget {
  const SetPinModal({
    super.key,
    required this.onPinConfirmed,
  });

  final ValueChanged<String> onPinConfirmed;

  @override
  State<SetPinModal> createState() => _SetPinModalState();
}

class _SetPinModalState extends State<SetPinModal> with SingleTickerProviderStateMixin {
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  bool _obscurePin = true;
  String? _errorMessage;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _shakeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onDigitPressed(String digit) {
    HapticFeedback.selectionClick();
    setState(() {
      _errorMessage = null;
      if (!_isConfirming) {
        if (_pin.length < 4) {
          _pin += digit;
          if (_pin.length == 4) {
            // Move to confirmation step automatically with subtle haptic
            HapticFeedback.lightImpact();
            Future.delayed(const Duration(milliseconds: 200), () {
              if (mounted) {
                setState(() {
                  _isConfirming = true;
                });
              }
            });
          }
        }
      } else {
        if (_confirmPin.length < 4) {
          _confirmPin += digit;
          if (_confirmPin.length == 4) {
            if (_pin == _confirmPin) {
              HapticFeedback.mediumImpact();
              Navigator.pop(context);
              widget.onPinConfirmed(_pin);
            } else {
              HapticFeedback.heavyImpact();
              _shakeController.forward(from: 0.0);
              _errorMessage = 'PINs do not match. Please try again.';
              _confirmPin = '';
              _isConfirming = false;
              _pin = '';
            }
          }
        }
      }
    });
  }

  void _onBackspace() {
    HapticFeedback.selectionClick();
    setState(() {
      _errorMessage = null;
      if (_isConfirming) {
        if (_confirmPin.isNotEmpty) {
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
        } else {
          _isConfirming = false;
        }
      } else {
        if (_pin.isNotEmpty) {
          _pin = _pin.substring(0, _pin.length - 1);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentCode = _isConfirming ? _confirmPin : _pin;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle bar
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Icon badge
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.accentTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline_rounded, color: AppColors.accent, size: 24),
            ),
            const SizedBox(height: 12),

            // Title & Subtitle
            Text(
              _isConfirming ? 'Confirm 4-Digit PIN' : 'Create 4-Digit PIN',
              style: AppTextStyles.display(fontSize: 22, color: AppColors.ink),
            ),
            const SizedBox(height: 6),
            Text(
              _isConfirming
                  ? 'Re-enter your 4-digit PIN for confirmation.'
                  : 'The receiver will need this PIN to unlock your contacts.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.ink2, fontSize: 13.5),
            ),
            const SizedBox(height: 20),

            // PIN Dots / Digits Indicator with Peek Toggle and Spring Shake
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) {
                final offset = math.sin(_shakeAnimation.value * math.pi * 6) * 12 * (1 - _shakeAnimation.value);
                return Transform.translate(
                  offset: Offset(offset, 0),
                  child: child,
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 40), // Center balance
                  Row(
                    children: List.generate(4, (index) {
                      final hasDigit = index < currentCode.length;
                      final digitChar = hasDigit ? currentCode[index] : '';

                      if (_obscurePin) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasDigit ? AppColors.accent : Colors.transparent,
                            border: Border.all(
                              color: hasDigit ? AppColors.accent : AppColors.ink3,
                              width: 2,
                            ),
                          ),
                        );
                      }

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: 32,
                        height: 40,
                        decoration: BoxDecoration(
                          color: hasDigit ? AppColors.accentTint : AppColors.cardWhite,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: hasDigit ? AppColors.accent : AppColors.border,
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          digitChar,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      );
                    }),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _obscurePin = !_obscurePin),
                    icon: Icon(
                      _obscurePin ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 20,
                      color: AppColors.ink2,
                    ),
                    tooltip: _obscurePin ? 'Show PIN' : 'Hide PIN',
                  ),
                ],
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Keypad
            _NumericKeypad(
              onDigit: _onDigitPressed,
              onBackspace: _onBackspace,
            ),
          ],
        ),
      ),
    );
  }
}

class _NumericKeypad extends StatelessWidget {
  const _NumericKeypad({
    required this.onDigit,
    required this.onBackspace,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', '⌫'],
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((key) {
                if (key.isEmpty) {
                  return const SizedBox(width: 72, height: 60);
                }
                if (key == '⌫') {
                  return InkWell(
                    onTap: onBackspace,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 72,
                      height: 60,
                      alignment: Alignment.center,
                      child: const Icon(Icons.backspace_outlined, color: AppColors.ink, size: 22),
                    ),
                  );
                }
                return InkWell(
                  onTap: () => onDigit(key),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 72,
                    height: 60,
                    decoration: BoxDecoration(
                      color: AppColors.cardWhite,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      key,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
