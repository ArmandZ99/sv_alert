import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travelalerts/features/settings/data/preferences_store.dart';
import 'package:travelalerts/features/settings/domain/notification_preferences.dart';
import 'package:travelalerts/features/transport/domain/transport_type.dart';
import 'package:travelalerts/features/settings/presentation/preferences_controller.dart';

Future<SharedPreferencesStore> storeWith([
  Map<String, Object> values = const {},
]) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferencesStore.create();
}

void main() {
  test('nothing stored gives the defaults', () async {
    final loaded = await (await storeWith()).load();
    expect(loaded.enabled, isTrue);
    expect(loaded.arrivalAlertsEnabled, isTrue);
    expect(loaded.delayAlertsEnabled, isTrue);
    expect(loaded.reminderMinutes, [30, 15, 5]);
    expect(loaded.delayThresholdMinutes, 15);
    expect(loaded.followedTypes, TransportType.values.toSet());
  });

  test('saved preferences survive a restart', () async {
    final store = await storeWith();
    const saved = NotificationPreferences(
      enabled: false,
      arrivalAlertsEnabled: false,
      delayAlertsEnabled: true,
      followedTypes: {TransportType.train},
      reminderMinutes: [60, 10],
      delayThresholdMinutes: 25,
      quietHours: QuietHours(
        enabled: true,
        startMinutes: 23 * 60,
        endMinutes: 6 * 60 + 30,
      ),
      followedServiceIds: {'a-1', 'b-2'},
    );
    await store.save(saved);

    // "Restart": a new store instance reading the same underlying storage.
    final reloaded = await SharedPreferencesStore(
      await SharedPreferences.getInstance(),
    ).load();
    expect(reloaded.enabled, isFalse);
    expect(reloaded.arrivalAlertsEnabled, isFalse);
    expect(reloaded.delayAlertsEnabled, isTrue);
    expect(reloaded.followedTypes, {TransportType.train});
    expect(reloaded.reminderMinutes, [60, 10]);
    expect(reloaded.delayThresholdMinutes, 25);
    expect(reloaded.quietHours.enabled, isTrue);
    expect(reloaded.quietHours.startMinutes, 23 * 60);
    expect(reloaded.quietHours.endMinutes, 6 * 60 + 30);
    expect(reloaded.followedServiceIds, {'a-1', 'b-2'});
  });

  test('an empty followed-types set is kept, not reset to defaults', () async {
    final store = await storeWith();
    await store.save(const NotificationPreferences(followedTypes: {}));
    expect((await store.load()).followedTypes, isEmpty);
  });

  test('corrupt JSON falls back to defaults', () async {
    final store = await storeWith({
      SharedPreferencesStore.storageKey: '{not json',
    });
    final loaded = await store.load();
    expect(loaded.delayThresholdMinutes, 15);
    expect(loaded.reminderMinutes, [30, 15, 5]);
  });

  test('a value of the wrong shape falls back to defaults', () async {
    final store = await storeWith({
      SharedPreferencesStore.storageKey: '[1,2,3]',
    });
    expect((await store.load()).enabled, isTrue);
  });

  test('invalid fields fall back individually while valid ones are kept', () async {
    final store = await storeWith({
      SharedPreferencesStore.storageKey:
          '{"enabled":false,"arrivalAlertsEnabled":"yes","delayThresholdMinutes":9999,'
          '"reminderMinutes":[10,"x",-5,0,10],"followedTypes":["train","boat",7],'
          '"quietHours":{"enabled":true,"startMinutes":99999,"endMinutes":120},'
          '"followedServiceIds":["a",3]}',
    });
    final loaded = await store.load();
    expect(loaded.enabled, isFalse); // valid, kept
    expect(loaded.arrivalAlertsEnabled, isTrue); // wrong type -> default
    expect(loaded.delayThresholdMinutes, 15); // out of range -> default
    expect(loaded.reminderMinutes, [10]); // junk and duplicates dropped
    expect(loaded.followedTypes, {
      TransportType.train,
    }); // unknown names dropped
    expect(loaded.quietHours.enabled, isTrue);
    expect(loaded.quietHours.startMinutes, 22 * 60); // out of range -> default
    expect(loaded.quietHours.endMinutes, 120);
    expect(loaded.followedServiceIds, {'a'});
  });

  test('the controller saves every change through the store', () async {
    final store = await storeWith();
    final controller = PreferencesController(store: store);
    controller.setArrivalAlertsEnabled(false);
    controller.setDelayAlertsEnabled(false);
    controller.setTypeFollowed(TransportType.flight, false);
    controller.toggleReminder(10);
    controller.setDelayThreshold(40);
    await Future<void>.delayed(Duration.zero);

    final reloaded = await store.load();
    expect(reloaded.arrivalAlertsEnabled, isFalse);
    expect(reloaded.delayAlertsEnabled, isFalse);
    expect(reloaded.followedTypes.contains(TransportType.flight), isFalse);
    expect(reloaded.reminderMinutes, [30, 15, 10, 5]);
    expect(reloaded.delayThresholdMinutes, 40);
  });

  test('a failing store does not break the controller', () async {
    final controller = PreferencesController(store: _ThrowingStore());
    controller.setDelayThreshold(30);
    await Future<void>.delayed(Duration.zero);
    expect(controller.value.delayThresholdMinutes, 30);
  });
}

class _ThrowingStore implements PreferencesStore {
  @override
  Future<NotificationPreferences> load() async =>
      const NotificationPreferences();

  @override
  Future<void> save(NotificationPreferences preferences) async =>
      throw StateError('disk full');
}
