import 'package:flutter/material.dart';

import '../../domain/demand_overview.dart';
import '../l10n/formatters.dart';
import '../l10n/strings.dart';

/// Potential-demand overview for drivers, built from upcoming arrivals only.
class DemandCard extends StatelessWidget {
  const DemandCard({required this.overview, super.key});

  final DemandOverview overview;

  static const _gold = Color(0xFFFFD166);

  @override
  Widget build(BuildContext context) {
    final (headline, levelIcon) = switch (overview.level) {
      DemandLevel.low => (Strings.demandLow, Icons.trending_flat),
      DemandLevel.moderate => (Strings.demandModerate, Icons.trending_up),
      DemandLevel.high => (
        Strings.demandHigh,
        Icons.local_fire_department_outlined,
      ),
    };
    final maxCount = overview.buckets.fold<int>(
      1,
      (m, b) => b.count > m ? b.count : m,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF172B4D), Color(0xFF234E91)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.radar, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  Strings.demandTitle,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (overview.isSampleData)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Text(
                    Strings.demandSampleBadge,
                    style: TextStyle(
                      color: _gold,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(levelIcon, color: _gold, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  headline,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            Strings.arrivalsNextHour(overview.arrivalsNextHour),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            Strings.arrivalsInWindow(overview.arrivalsInWindow),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final bucket in overview.buckets)
                Expanded(
                  child: Semantics(
                    label:
                        '${bucket.fromMinute}–${bucket.toMinute} min: ${bucket.count}',
                    excludeSemantics: true,
                    child: Column(
                      children: [
                        Text(
                          '${bucket.count}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: 8 + 36.0 * bucket.count / maxCount,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: bucket.count == 0
                                ? Colors.white.withValues(alpha: 0.2)
                                : _gold,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${bucket.fromMinute}–${bucket.toMinute}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'minute',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final hub in overview.hubs) _HubRow(hub: hub),
          if (overview.scheduleOnlyCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              Strings.scheduleOnlyNote(overview.scheduleOnlyCount),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 11.5,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            Strings.demandDisclaimer,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _HubRow extends StatelessWidget {
  const _HubRow({required this.hub});

  final HubDemand hub;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (hub.hub) {
      DemandHub.railway => (Icons.train, Strings.hubRailway),
      DemandHub.airport => (Icons.flight, Strings.hubAirport),
      DemandHub.coachStation => (Icons.directions_bus, Strings.hubCoach),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            Strings.hubArrivals(hub.arrivalsNextHour),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 12,
            ),
          ),
          if (hub.nextArrival != null) ...[
            const SizedBox(width: 8),
            Text(
              formatTime(hub.nextArrival!),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
