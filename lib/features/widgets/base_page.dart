import 'package:flutter/material.dart';
import 'custom_app_bar.dart';
import 'navigation_bar.dart';

class BasePage extends StatelessWidget {
  final Widget body;
  final Gradient? headerGradient;

  const BasePage({super.key, required this.body, this.headerGradient});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: CustomAppBar(gradient: headerGradient),
      body: body,
      bottomNavigationBar: NavBar(),
    );
  }
}
