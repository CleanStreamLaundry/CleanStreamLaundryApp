import 'package:flutter/material.dart';

class Logo extends StatefulWidget {
  const Logo({super.key});

  @override
  State<Logo> createState() => _LogoState();
}

class _LogoState extends State<Logo> {
  double begin = 0.95;
  double end = 1.05;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: begin, end: end),
      duration: const Duration(seconds: 1),
      curve: Curves.easeInOut,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Image.asset('assets/splash-logo.png', height: 250),
      onEnd: () {
        setState(() {
          final temp = begin;
          begin = end;
          end = temp;
        });
      },
    );
  }
}
