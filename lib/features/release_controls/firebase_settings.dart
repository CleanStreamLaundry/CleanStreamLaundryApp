import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

class FirebaseSettings extends StatelessWidget {
  final FirebaseService service;
  const FirebaseSettings({super.key, required this.service});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) => Column(
      children: [
        SwitchListTile(
          title: const Text('In-app messages'),
          subtitle: const Text('Optional announcements'),
          value: service.messagesEnabled,
          onChanged: service.available && service.analyticsEnabled
              ? service.setMessages
              : null,
        ),
        SwitchListTile(
          title: const Text('Push notifications'),
          value: service.pushEnabled,
          onChanged: service.available ? service.setPush : null,
        ),
        if (!service.available)
          const ListTile(title: Text('Optional services unavailable')),
        if (service.problem != null)
          ListTile(
            title: Text(service.problem!),
            subtitle: kDebugMode && service.pushCleanupDiagnostic != null
                ? Text(service.pushCleanupDiagnostic!)
                : null,
            trailing: IconButton(
              tooltip: Overlay.maybeOf(context) != null ? 'Retry' : null,
              icon: Icon(
                Icons.refresh,
                semanticLabel: Overlay.maybeOf(context) == null
                    ? 'Retry'
                    : null,
              ),
              onPressed: service.resume,
            ),
          ),
      ],
    ),
  );
}
