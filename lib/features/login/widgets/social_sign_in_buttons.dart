import 'package:clean_stream_laundry_app/features/login/controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class SocialSignInButtons extends StatelessWidget {
  final LoginController controller;

  const SocialSignInButtons({super.key, required this.controller});

  bool get _shouldShowAppleSignIn =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: controller.googleSignInPending ||
                      controller.appleSignInPending
                  ? null
                  : () => controller.handleGoogleSignIn(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark
                    ? const Color(0xFF131314)
                    : Colors.white,
                foregroundColor: isDark
                    ? const Color(0xFFE3E3E3)
                    : const Color(0xFF1F1F1F),
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                minimumSize: const Size(48, 48),
                padding: EdgeInsets.symmetric(
                  horizontal: isIOS ? 16 : 12,
                  vertical: 12,
                ),
                side: BorderSide(
                  color: isDark
                      ? const Color(0xFF8E918F)
                      : const Color(0xFF747775),
                ),
                shape: const StadiumBorder(),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/Google.png',
                    width: 20,
                    height: 20,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                    key: const Key('google_logo'),
                  ),
                  SizedBox(width: isIOS ? 12 : 10),
                  const Flexible(
                    child: Text(
                      'Sign in with Google',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Google Sans',
                        fontSize: 14,
                        height: 20 / 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_shouldShowAppleSignIn)
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: SizedBox(
              width: double.infinity,
              height: 36,
              child: ElevatedButton(
                onPressed: controller.appleSignInPending ||
                        controller.googleSignInPending
                    ? null
                    : () => controller.handleAppleSignIn(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.apple, size: 16),
                    SizedBox(width: 8),
                    Text('Sign in with Apple', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
