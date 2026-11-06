import 'package:flutter/material.dart';

import '../config.dart';
import '../theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, this.error});
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
          child: Column(
            children: [
              const Spacer(),
              Image.asset('assets/images/logo_mark.png', width: 112, height: 100),
              const SizedBox(height: 24),
              const Text(
                AppConfig.appName,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: VV.ink),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pin customer locations to Odoo',
                style: TextStyle(fontSize: 16, color: VV.inkMuted),
              ),
              const SizedBox(height: 32),
              if (error == null)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: VV.blue),
                )
              else
                Text(
                  'Could not start: $error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: VV.danger),
                ),
              const Spacer(),
              Image.asset('assets/images/logo_lockup.png', width: 180),
              const SizedBox(height: 12),
              const Text(
                'Version ${AppConfig.appVersion}',
                style: TextStyle(fontSize: 12, color: VV.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
