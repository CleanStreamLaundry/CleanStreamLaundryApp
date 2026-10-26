import 'package:clean_stream_laundry_app/logic/enums/authentication_response_enum.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:clean_stream_laundry_app/logic/services/auth_service.dart';

class NotFound extends StatelessWidget {
  const NotFound({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = GetIt.instance<AuthService>();

    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: colors.error, size: 48),
                const SizedBox(height: 20),
                Text(
                  '404 - Page Not Found',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(48, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    late final AuthenticationResponses response;
                    try {
                      response = await authService.isLoggedIn();
                    } catch (_) {
                      if (!context.mounted) return;
                      rethrow;
                    }
                    if (!context.mounted) return;
                    if (response == AuthenticationResponses.success) {
                      context.go("/homePage");
                    } else {
                      context.go("/login");
                    }
                  },
                  child: const Text("Go to Home"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
