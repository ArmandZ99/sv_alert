import 'package:flutter/material.dart';

import '../../domain/arrival_status.dart';
import '../../domain/transport_service.dart';
import 'styles.dart';

/// Status shown as icon + text + color, never color alone.
class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.service, required this.status, super.key});

  final TransportService service;
  final ArrivalStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              describeStatus(service, status),
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
