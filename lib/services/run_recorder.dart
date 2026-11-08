import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:health/health.dart' show WorkoutRouteLocation;
import 'package:permission_handler/permission_handler.dart' show Permission, PermissionActions;

import '../models/workout.dart';

/// Um ponto de GPS já filtrado.
class Fix {
  const Fix({required this.lat, required this.lng, required this.time, this.accuracy = 5, this.altitude, this.speed});
  final double lat;
  final double lng;
  final DateTime time;
  final double accuracy;
  final double? altitude;
  final double? speed;
}

/// Lógica pura da gravação: distância, tempo em movimento, pace e parciais.
/// Não depende de GPS real, então é testável.
class RunTracker {
  RunTracker({this.maxAccuracyM = 25, this.maxSpeedMs = 9});

  /// Pontos com precisão pior que isso são descartados.
  final double maxAccuracyM;

  /// Saltos acima dessa velocidade (~3:05 /km... ou um carro) são ruído.
  final double maxSpeedMs;

  final List<Fix> points = [];
  final List<Split> splits = [];
  double distanceM = 0;
  Duration _elapsedBeforePause = Duration.zero;
  DateTime? _resumedAt;
  DateTime? startedAt;
  bool paused = false;
  Fix? _last;
  Duration _lastSplitAt = Duration.zero;

  void start(DateTime now) {
    startedAt = now;
    _resumedAt = now;
  }

  void pause(DateTime now) {
    if (paused || _resumedAt == null) return;
    _elapsedBeforePause += now.difference(_resumedAt!);
    paused = true;
    _last = null; // não liga a distância entre a pausa e a retomada
  }

  void resume(DateTime now) {
    if (!paused) return;
    paused = false;
    _resumedAt = now;
  }

  Duration elapsed(DateTime now) {
    if (_resumedAt == null) return Duration.zero;
    return paused ? _elapsedBeforePause : _elapsedBeforePause + now.difference(_resumedAt!);
  }

  /// Retorna true se o ponto foi aceito.
  bool add(Fix f) {
    if (paused || startedAt == null) return false;
    if (f.accuracy > maxAccuracyM) return false;
    final last = _last;
    if (last != null) {
      final d = haversine(last.lat, last.lng, f.lat, f.lng);
      final dt = f.time.difference(last.time).inMilliseconds / 1000;
      if (dt <= 0) return false;
      if (d / dt > maxSpeedMs) return false;
      distanceM += d;
      _checkSplit(f.time);
    }
    _last = f;
    points.add(f);
    return true;
  }

  void _checkSplit(DateTime t) {
    while (distanceM >= (splits.length + 1) * 1000) {
      final now = elapsed(t);
      splits.add(Split(km: splits.length + 1, duration: now - _lastSplitAt));
      _lastSplitAt = now;
    }
  }

  /// Pace médio em s/km.
  double? avgPace(DateTime now) => distanceM < 50 ? null : elapsed(now).inSeconds / (distanceM / 1000);

  /// Pace dos últimos ~30 s (mais útil durante tiros).
  double? currentPace({Duration window = const Duration(seconds: 30)}) {
    if (points.length < 2) return null;
    final end = points.last;
    var i = points.length - 1;
    var d = 0.0;
    while (i > 0 && end.time.difference(points[i - 1].time) <= window) {
      d += haversine(points[i - 1].lat, points[i - 1].lng, points[i].lat, points[i].lng);
      i--;
    }
    final dt = end.time.difference(points[i].time).inSeconds;
    if (d < 20 || dt <= 0) return null;
    return dt / (d / 1000);
  }

  /// Gasto calórico aproximado para corrida: ~1 kcal por kg por km.
  int kcal(double weightKg) => (weightKg * distanceM / 1000).round();
}

double haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
  final dp = (lat2 - lat1) * math.pi / 180, dl = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

enum GpsPermission { granted, denied, deniedForever, serviceOff }

/// Liga o [RunTracker] ao GPS real, com serviço em primeiro plano para a
/// gravação continuar com a tela apagada.
class RunRecorder extends ChangeNotifier {
  RunRecorder({RunTracker? tracker}) : tracker = tracker ?? RunTracker();

  final RunTracker tracker;
  StreamSubscription<Position>? _sub;
  Timer? _ticker;
  bool get running => _sub != null;

  static Future<GpsPermission> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return GpsPermission.serviceOff;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.deniedForever) return GpsPermission.deniedForever;
    if (p == LocationPermission.denied) return GpsPermission.denied;
    // Android 13+: sem isso a notificação da gravação fica oculta.
    await Permission.notification.request();
    return GpsPermission.granted;
  }

  void start() {
    tracker.start(DateTime.now());
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 3,
      intervalDuration: const Duration(seconds: 2),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Gravando corrida',
        notificationText: 'O Fast run está registrando sua rota.',
        notificationChannelName: 'Gravação de corrida',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
      tracker.add(Fix(
        lat: pos.latitude,
        lng: pos.longitude,
        time: pos.timestamp,
        accuracy: pos.accuracy,
        altitude: pos.altitude,
        speed: pos.speed,
      ));
      notifyListeners();
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
  }

  void togglePause() {
    final now = DateTime.now();
    tracker.paused ? tracker.resume(now) : tracker.pause(now);
    notifyListeners();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    _ticker = null;
  }

  List<WorkoutRouteLocation> routeForHealth() => [
        for (final p in tracker.points)
          WorkoutRouteLocation(
            latitude: p.lat,
            longitude: p.lng,
            timestamp: p.time,
            altitude: p.altitude,
            horizontalAccuracy: p.accuracy,
            speed: p.speed,
          ),
      ];

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
