import 'package:flutter/material.dart';

/// A page displayed when the user attempts to access a feature that requires a higher subscription plan.
///
/// There is no in-app upgrade flow, so the page names who can change the plan.
class UpgradeRequiredPage extends StatelessWidget {
  const UpgradeRequiredPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 70, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              "Your plan doesn't include Jobs. Ask your administrator to upgrade it.",
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
