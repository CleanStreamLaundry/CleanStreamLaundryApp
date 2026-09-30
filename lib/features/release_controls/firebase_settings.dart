import 'package:clean_stream_laundry_app/services/firebase/firebase_service.dart';
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
          title: const Text('Usage analytics'),
          subtitle: const Text('Optional app usage measurement'),
          value: service.analyticsEnabled,
          onChanged: service.available ? service.setAnalytics : null,
        ),
        SwitchListTile(
          title: const Text('In-app messages'),
          subtitle: const Text(
            'Optional announcements; requires usage analytics',
          ),
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
            trailing: IconButton(
              tooltip: 'Retry',
              icon: const Icon(Icons.refresh),
              onPressed: service.resume,
            ),
          ),
      ],
    ),
  );
}
