import 'package:flutter/material.dart';

import '../consent/privacy_tab.dart';
import 'profile_tab.dart';

/// Full-screen Profile, opened from the Home header avatar. Privacy & access
/// now lives here as a second tab (moved off the bottom bar) so the patient's
/// personal + consent settings sit together. [initialTab] 0 = Profile,
/// 1 = Privacy.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Profile'),
              Tab(text: 'Privacy & access'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ProfileTab(),
            PrivacyTab(),
          ],
        ),
      ),
    );
  }
}
