import 'package:flutter/material.dart';
import 'checador_page.dart';
import 'attendance_admin_page.dart';

class AttendanceHubPage extends StatelessWidget {
  final String role;
  final Map<String, dynamic> permissions;

  const AttendanceHubPage(
      {super.key, required this.role, required this.permissions});

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = role == 'admin';

    return ChecadorPage(
      isAdmin: isAdmin,
      role: role,
      permissions: permissions,
    );
  }
}
