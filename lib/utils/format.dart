import 'package:intl/intl.dart';

String fmtPace(double? secPerKm, {bool unit = true}) {
  if (secPerKm == null || secPerKm.isNaN || secPerKm.isInfinite || secPerKm <= 0) return '—';
  final s = secPerKm.round();
  final txt = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  return unit ? '$txt /km' : txt;
}

String fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${d.inMinutes.remainder(60)}:$s';
}

/// "1h 05" ou "42 min".
String fmtDurationShort(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  return '${d.inHours}h ${d.inMinutes.remainder(60).toString().padLeft(2, '0')}';
}

String fmtKm(double? km, {int decimals = 1}) {
  if (km == null) return '—';
  return '${km.toStringAsFixed(decimals).replaceAll('.', ',')} km';
}

/// "Hoje, 07:12", "Ontem, 18:30", "qui., 06:50" ou "02/11, 07:00".
String fmtWorkoutDate(DateTime d, {DateTime? now}) {
  now ??= DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  final hm = DateFormat('HH:mm', 'pt_BR').format(d);
  if (diff == 0) return 'Hoje, $hm';
  if (diff == 1) return 'Ontem, $hm';
  if (diff < 7 && diff > 0) return '${DateFormat('EEE', 'pt_BR').format(d)}, $hm';
  return '${DateFormat('dd/MM', 'pt_BR').format(d)}, $hm';
}

/// Converte "mm:ss" ou "h:mm:ss" em Duration. Retorna null se inválido.
Duration? parseDuration(String text) {
  final parts = text.trim().split(':').map(int.tryParse).toList();
  if (parts.isEmpty || parts.any((p) => p == null)) return null;
  if (parts.length == 2) return Duration(minutes: parts[0]!, seconds: parts[1]!);
  if (parts.length == 3) return Duration(hours: parts[0]!, minutes: parts[1]!, seconds: parts[2]!);
  return null;
}

const weekdayShort = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
