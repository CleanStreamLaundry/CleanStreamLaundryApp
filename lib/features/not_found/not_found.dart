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

    return Container(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 80),
            const SizedBox(height: 20),
            const Text(
              '404 - Page Not Found',
              style: TextStyle(
                fontSize: 24,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                late final AuthenticationResponses response;
                try {
                  response = await authService.isLoggedIn();
                } catch (_) {
                  if (!context.mounted) return;
                  rethrow;
                }
                if (!context.mounted) return;
                if (response == AuthenticationResponses.success){
                  context.go("/homePage");
                }else{
                  context.go("/login");
                }
              },
              child: const Text("Go to Home"),
            ),
          ],
        ),
      ),
    );
  }
}
