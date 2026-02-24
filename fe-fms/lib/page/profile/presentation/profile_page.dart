import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fms/core/services/subscription.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fms/core/constants/variables.dart';
import '../controller/profile_controller.dart';
import '../widget/change_password_dialog.dart';
import '../../../nav_bar.dart';

/// A page displaying the user's profile, subscription status, and logout option.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final ProfileController _controller;
  String? _company;

  @override
  void initState() {
    super.initState();
    _controller = Get.put(ProfileController());

    // Load company from SharedPreferences (persisted at login)
    SharedPreferences.getInstance().then((prefs) {
      final company = prefs.getString(Variables.prefCompany);
      if (mounted) setState(() => _company = company);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isPro = subscriptionService.currentPlan == Plan.pro;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        //back button
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const NavBar()),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Obx(() {
            final profile = _controller.profile.value;
            final loading = _controller.isLoading.value;
            debugPrint('Profile Data Content: ${profile?.data?.toJson()}');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: ListTile(
                    // 1. Ensures leading/trailing are vertically centered with the text
                    isThreeLine: false, 
                    leading: const CircleAvatar(
                      radius: 26,
                      child: Icon(Icons.person),
                    ),
                    title: Text(
                      loading
                          ? 'Loading...'
                          : (profile?.data?.fullname ?? 'Unknown'),
                    ),
                    // 2. Using a simple Text widget instead of a Column fixes internal alignment
                    subtitle: Text(
                      loading
                          ? 'Loading...'
                          : (profile?.data?.email ?? 'Unknown'),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isPro
                            ? Colors.blue.withValues(alpha: 0.08)
                            : Colors.grey.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isPro ? 'PRO' : 'BASIC',
                        style: TextStyle(
                          color: isPro
                              ? Colors.blue.shade700
                              : Colors.grey.shade700,
                          fontWeight: FontWeight.bold, // Optional: makes the badge pop
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Subscription',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        SegmentedButton<Plan>(
                          segments: const [
                            ButtonSegment(
                              value: Plan.basic,
                              label: Text('Basic'),
                            ),
                            ButtonSegment(value: Plan.pro, label: Text('Pro')),
                          ],
                          selected: {subscriptionService.currentPlan},
                          // Disabled - cannot change subscription from app
                          onSelectionChanged: null,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isPro
                            ? '${_company ?? "The company"} is subscribed to the Pro plan.'
                            : '${_company ?? "The company"} is subscribed to the Basic plan.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('Support'),
                    subtitle: const Text('help@efms.app'),
                    onTap: () {},
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Change Password'),
                    onTap: () => showChangePasswordDialog(context),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text(
                      'Logout',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () {
                      //show dialog
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Logout'),
                          content: const Text(
                            'Are you sure you want to logout?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () async {
                                await _controller.logout(
                                  context: context,
                                  mounted: mounted,
                                );
                              },
                              child: const Text(
                                'Logout',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
