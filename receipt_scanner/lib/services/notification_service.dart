import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../models/inventory_item.dart';

class NotificationService {
  static const _leadDaysKey = 'expiry_reminder_lead_days';
  static const _defaultLeadDays = 3;

  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz_data.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<int> getLeadDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_leadDaysKey) ?? _defaultLeadDays;
  }

  Future<void> setLeadDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_leadDaysKey, days);
  }

  int _notificationId(String itemId) => itemId.hashCode & 0x7fffffff;

  Future<void> scheduleExpiryReminder(InventoryItem item) async {
    if (item.id == null) return;
    final id = _notificationId(item.id!);
    await _plugin.cancel(id);

    if (item.expiryDate == null) return;

    final leadDays = await getLeadDays();
    final reminderDate = item.expiryDate!.subtract(Duration(days: leadDays));
    if (reminderDate.isBefore(DateTime.now())) return;

    final scheduledTime = tz.TZDateTime.from(
      DateTime(reminderDate.year, reminderDate.month, reminderDate.day, 9),
      tz.local,
    );

    await _plugin.zonedSchedule(
      id,
      'המוצר "${item.name}" עומד לפוג',
      'תוקף בעוד $leadDays ימים - ${item.quantity} ${item.unit}',
      scheduledTime,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'expiry_reminders',
          'תזכורות תפוגה',
          channelDescription: 'התראות על מוצרים שעומדים לפוג תוקף',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelExpiryReminder(String itemId) async {
    await _plugin.cancel(_notificationId(itemId));
  }

  Future<void> showLowStockAlert(InventoryItem item) async {
    if (item.id == null) return;
    final id = _notificationId('${item.id}#lowstock');

    await _plugin.show(
      id,
      'מלאי נמוך: ${item.name}',
      'נותרו ${item.quantity} ${item.unit} בלבד - כדאי להוסיף לרשימת הקניות',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'low_stock_alerts',
          'התראות מלאי נמוך',
          channelDescription: 'התראות כשכמות מוצר יורדת מתחת לסף המינימלי',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
