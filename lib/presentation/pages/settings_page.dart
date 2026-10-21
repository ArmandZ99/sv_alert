import 'package:flutter/material.dart';

import '../../domain/notification_preferences.dart';
import '../../domain/transport_type.dart';
import '../l10n/formatters.dart';
import '../l10n/strings.dart';
import '../state/preferences_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/notice_banner.dart';
import '../widgets/styles.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.preferences, super.key});

  final PreferencesController preferences;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) {
        final prefs = preferences.value;
        final controlsEnabled = prefs.enabled;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            const Text(
              Strings.settingsTitle,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              Strings.settingsSubtitle,
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            const NoticeBanner(
              title: Strings.notificationsNotActiveTitle,
              body: Strings.notificationsNotActiveBody,
              icon: Icons.notifications_off_outlined,
            ),
            const SizedBox(height: 20),
            const _SectionTitle(Strings.sectionNotifications),
            Card(
              child: SwitchListTile(
                value: prefs.enabled,
                onChanged: preferences.setEnabled,
                title: const Text(
                  Strings.notificationsEnabled,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(Strings.notificationsEnabledHint),
              ),
            ),
            const SizedBox(height: 18),
            const _SectionTitle(Strings.sectionTypes),
            Card(
              child: Column(
                children: [
                  for (final (index, type) in TransportType.values.indexed) ...[
                    if (index > 0)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      secondary: Icon(type.icon, color: type.color),
                      value: prefs.followedTypes.contains(type),
                      onChanged: controlsEnabled
                          ? (value) => preferences.setTypeFollowed(type, value)
                          : null,
                      title: Text(_typeTitle(type)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _SectionTitle(Strings.sectionReminders),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      Strings.remindersHint,
                      style: TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final minutes
                            in NotificationPreferences.reminderOptions)
                          FilterChip(
                            label: Text(Strings.reminderChip(minutes)),
                            selected: prefs.reminderMinutes.contains(minutes),
                            onSelected: controlsEnabled
                                ? (_) => preferences.toggleReminder(minutes)
                                : null,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            const _SectionTitle(Strings.sectionDelay),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Strings.delayThresholdLabel(prefs.delayThresholdMinutes),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Slider(
                      value: prefs.delayThresholdMinutes.toDouble(),
                      min: NotificationPreferences.minDelayThreshold.toDouble(),
                      max: NotificationPreferences.maxDelayThreshold.toDouble(),
                      divisions:
                          (NotificationPreferences.maxDelayThreshold -
                              NotificationPreferences.minDelayThreshold) ~/
                          5,
                      label: Strings.minutesShort(prefs.delayThresholdMinutes),
                      onChanged: controlsEnabled
                          ? (value) =>
                                preferences.setDelayThreshold(value.round())
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            const _SectionTitle(Strings.sectionQuiet),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    value: prefs.quietHours.enabled,
                    onChanged: controlsEnabled
                        ? (value) => preferences.setQuietHours(
                            prefs.quietHours.copyWith(enabled: value),
                          )
                        : null,
                    title: const Text(Strings.quietEnabled),
                  ),
                  if (prefs.quietHours.enabled) ...[
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      title: const Text(Strings.quietFrom),
                      trailing: Text(
                        formatMinuteOfDay(prefs.quietHours.startMinutes),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onTap: () => _pickTime(
                        context,
                        prefs.quietHours.startMinutes,
                        (m) => preferences.setQuietHours(
                          prefs.quietHours.copyWith(startMinutes: m),
                        ),
                      ),
                    ),
                    ListTile(
                      title: const Text(Strings.quietTo),
                      trailing: Text(
                        formatMinuteOfDay(prefs.quietHours.endMinutes),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onTap: () => _pickTime(
                        context,
                        prefs.quietHours.endMinutes,
                        (m) => preferences.setQuietHours(
                          prefs.quietHours.copyWith(endMinutes: m),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _SectionTitle(Strings.sectionFollowed),
            Card(
              child: ListTile(
                leading: const Icon(Icons.star_outline_rounded),
                title: Text(
                  prefs.followedServiceIds.isEmpty
                      ? Strings.followedNone
                      : Strings.followedCount(prefs.followedServiceIds.length),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const _SectionTitle(Strings.sectionAbout),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Strings.independentNotice,
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                    SizedBox(height: 10),
                    Text(
                      Strings.aboutPrivacy,
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _typeTitle(TransportType type) => switch (type) {
    TransportType.flight => Strings.settingsFlights,
    TransportType.train => Strings.settingsTrains,
    TransportType.coach => Strings.settingsCoaches,
  };

  Future<void> _pickTime(
    BuildContext context,
    int minutes,
    ValueChanged<int> onPicked,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked != null) onPicked(picked.hour * 60 + picked.minute);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          letterSpacing: 1.0,
          fontWeight: FontWeight.w900,
          color: AppColors.muted,
        ),
      ),
    );
  }
}
