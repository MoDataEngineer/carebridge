import 'package:flutter/material.dart';

/// Large tappable button used on the three-button entry screen (Section 2).
class RoleButton extends StatelessWidget {
  const RoleButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 28),
      label: Text(label, style: const TextStyle(fontSize: 18)),
    );
  }
}
