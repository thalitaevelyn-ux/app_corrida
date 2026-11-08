import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fit_sdk/fit_sdk.dart';
import 'package:xml/xml.dart';

import '../models/workout.dart';
import 'run_recorder.dart' show haversine;

/// Erro de importação com mensagem para o usuário.
class ImportException implements Exception {
  ImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Ponto de uma série temporal (GPS e/ou FC e/ou distância acumulada).
class _Pt {
  _Pt(this.t, {this.lat, this.lng, this.hr, this.dist});
  final DateTime t;
  final double? lat, lng, hr;

  /// Distância acumulada informada pelo arquivo (m), se houver.
  double? dist;
}

/// Lê GPX, TCX ou FIT e devolve um [Workout]. O formato é detectado pelo
/// conteúdo (o nome do arquivo só desempata).
Workout importActivity(Uint8List bytes, {String fileName = ''}) {
  if (bytes.length < 12) throw ImportException('Arquivo vazio ou incompleto.');
  // FIT: bytes 8..11 = ".FIT".
  if (bytes[8] == 0x2E && bytes[9] == 0x46 && bytes[10] == 0x49 && bytes[11] == 0x54) {
    return _parseFit(bytes);
  }
  final String text;
  try {
    text = utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    throw ImportException('Formato não reconhecido. Use arquivos GPX, TCX ou FIT.');
  }
  final head = text.substring(0, math.min(text.length, 2000)).toLowerCase();
  if (head.contains('<gpx')) return _parseGpx(text);
  if (head.contains('<trainingcenterdatabase')) return _parseTcx(text);
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.gpx')) return _parseGpx(text);
  if (lower.endsWith('.tcx')) return _parseTcx(text);
  throw ImportException('Formato não reconhecido. Use arquivos GPX, TCX ou FIT.');
}

// ------------------------------------------------------------------- GPX

Workout _parseGpx(String text) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(text);
  } catch (_) {
    throw ImportException('Arquivo GPX inválido.');
  }
  final gpx = doc.rootElement;
  final creator = gpx.getAttribute('creator') ?? '';
  final trk = gpx.findAllElements('trk').firstOrNull;
  final typeTxt = (trk?.getElement('type')?.innerText ?? '').toLowerCase();
  final name = trk?.getElement('name')?.innerText.trim();

  final pts = <_Pt>[];
  for (final p in gpx.findAllElements('trkpt')) {
    final time = p.getElement('time')?.innerText;
    if (time == null) continue;
    final t = DateTime.tryParse(time.trim());
    if (t == null) continue;
    double? hr;
    // Extensões Garmin (gpxtpx:hr) e variações (ns3:hr, hr).
    for (final e in p.descendants.whereType<XmlElement>()) {
      if (e.name.local.toLowerCase() == 'hr' || e.name.local.toLowerCase() == 'heartrate') {
        hr = double.tryParse(e.innerText.trim());
        break;
      }
    }
    pts.add(_Pt(t.toLocal(),
        lat: double.tryParse(p.getAttribute('lat') ?? ''), lng: double.tryParse(p.getAttribute('lon') ?? ''), hr: hr));
  }
  if (pts.length < 2) throw ImportException('O GPX não tem pontos com horário (é uma rota planejada, não um treino?).');
  return _build(
    pts: pts,
    kind: _kindFromText(typeTxt.isEmpty ? (name ?? '') : typeTxt),
    title: name,
    source: _sourceName(creator, 'GPX'),
    format: 'gpx',
  );
}

// ------------------------------------------------------------------- TCX

Workout _parseTcx(String text) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(text);
  } catch (_) {
    throw ImportException('Arquivo TCX inválido.');
  }
  final act = doc.findAllElements('Activity').firstOrNull;
  if (act == null) throw ImportException('O TCX não contém nenhuma atividade.');
  final sport = act.getAttribute('Sport') ?? '';
  final creator = act.getElement('Creator')?.getElement('Name')?.innerText ?? '';

  double totalDist = 0, totalSec = 0;
  int kcal = 0;
  final pts = <_Pt>[];
  for (final lap in act.findElements('Lap')) {
    totalSec += double.tryParse(lap.getElement('TotalTimeSeconds')?.innerText ?? '') ?? 0;
    totalDist += double.tryParse(lap.getElement('DistanceMeters')?.innerText ?? '') ?? 0;
    kcal += int.tryParse(lap.getElement('Calories')?.innerText ?? '') ?? 0;
    for (final tp in lap.findAllElements('Trackpoint')) {
      final t = DateTime.tryParse(tp.getElement('Time')?.innerText.trim() ?? '');
      if (t == null) continue;
      final pos = tp.getElement('Position');
      pts.add(_Pt(
        t.toLocal(),
        lat: double.tryParse(pos?.getElement('LatitudeDegrees')?.innerText ?? ''),
        lng: double.tryParse(pos?.getElement('LongitudeDegrees')?.innerText ?? ''),
        hr: double.tryParse(tp.getElement('HeartRateBpm')?.getElement('Value')?.innerText ?? ''),
        dist: double.tryParse(tp.getElement('DistanceMeters')?.innerText ?? ''),
      ));
    }
  }
  final idTxt = act.getElement('Id')?.innerText.trim();
  final start = pts.isNotEmpty ? pts.first.t : (idTxt == null ? null : DateTime.tryParse(idTxt)?.toLocal());
  if (start == null) throw ImportException('O TCX não tem horário de início.');
  return _build(
    pts: pts,
    kind: _kindFromText(sport),
    source: _sourceName(creator, 'TCX'),
    format: 'tcx',
    start: start,
    totalDistM: totalDist > 0 ? totalDist : null,
    movingSec: totalSec > 0 ? totalSec : null,
    kcal: kcal > 0 ? kcal : null,
  );
}

// ------------------------------------------------------------------- FIT

const _fitEpoch = 631065600; // segundos entre 1970 e 1989-12-31
const _semi = 180 / 2147483648; // semicírculos → graus

DateTime? _fitTime(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(((v.toInt() + _fitEpoch) * 1000)) : null;

Workout _parseFit(Uint8List bytes) {
  final records = <_Pt>[];
  Mesg? session;
  String manufacturer = '';
  final d = Decode();
  d.onMesg = (m) {
    switch (m.num) {
      case 20: // record
        final t = _fitTime(m.getFieldValue(253));
        if (t == null) return;
        final lat = m.getFieldValue(0), lng = m.getFieldValue(1);
        records.add(_Pt(
          t,
          lat: lat is num ? lat * _semi : null,
          lng: lng is num ? lng * _semi : null,
          hr: (m.getFieldValue(3) as num?)?.toDouble(),
          dist: (m.getFieldValue(5) as num?)?.toDouble(),
        ));
      case 18: // session
        session ??= m;
      case 0: // file_id
        final man = m.getFieldValue(1);
        manufacturer = _fitManufacturers[man] ?? '';
    }
  };
  try {
    d.read(bytes);
  } catch (_) {
    // CRC ou cabeçalho ruins (alguns apps exportam assim): lê de novo sem validar.
    records.clear();
    session = null;
    try {
      Decode()
        ..onMesg = d.onMesg
        ..read(bytes, mode: DecodeMode.invalidHeader);
    } catch (_) {
      // Fica com o que deu para ler até o erro.
    }
    if (records.isEmpty && session == null) throw ImportException('Arquivo FIT inválido ou corrompido.');
  }
  final s = session;
  final start = _fitTime(s?.getFieldValue(2)) ?? (records.isNotEmpty ? records.first.t : null);
  if (start == null) throw ImportException('O FIT não contém uma atividade.');
  final sport = (s?.getFieldValue(5) as num?)?.toInt();
  return _build(
    pts: records,
    kind: _kindFromFitSport(sport),
    source: manufacturer.isEmpty ? 'Arquivo FIT' : '$manufacturer (FIT)',
    format: 'fit',
    start: start,
    totalDistM: (s?.getFieldValue(9) as num?)?.toDouble(),
    movingSec: (s?.getFieldValue(8) as num?)?.toDouble() ?? (s?.getFieldValue(7) as num?)?.toDouble(),
    elapsedSec: (s?.getFieldValue(7) as num?)?.toDouble(),
    kcal: (s?.getFieldValue(11) as num?)?.toInt(),
    avgHr: (s?.getFieldValue(16) as num?)?.toDouble(),
  );
}

const _fitManufacturers = <Object?, String>{
  Manufacturer.garmin: 'Garmin',
  Manufacturer.suunto: 'Suunto',
  Manufacturer.wahooFitness: 'Wahoo',
  Manufacturer.polarElectro: 'Polar',
  Manufacturer.corosByte: 'Coros',
  Manufacturer.coros: 'Coros',
  Manufacturer.strava: 'Strava',
};

WorkoutKind _kindFromFitSport(int? s) {
  switch (s) {
    case 1:
      return WorkoutKind.corrida;
    case 2:
      return WorkoutKind.bike;
    case 11:
    case 17:
      return WorkoutKind.caminhada;
    case 4:
    case 10:
      return WorkoutKind.academia;
    default:
      return s == null ? WorkoutKind.corrida : WorkoutKind.outro;
  }
}

// ---------------------------------------------------------------- comum

WorkoutKind _kindFromText(String t) {
  final s = t.toLowerCase();
  if (s.contains('run') || s.contains('corr') || s == '9') return WorkoutKind.corrida;
  if (s.contains('walk') || s.contains('camin') || s.contains('hik')) return WorkoutKind.caminhada;
  if (s.contains('bik') || s.contains('cycl') || s.contains('ciclis') || s.contains('pedal') || s == '1') {
    return WorkoutKind.bike;
  }
  if (s.contains('other') || s.contains('outro')) return WorkoutKind.outro;
  return WorkoutKind.corrida; // a maioria dos arquivos importados aqui são corridas
}

String _sourceName(String creator, String fmt) {
  final c = creator.toLowerCase();
  if (c.contains('zepp') || c.contains('amazfit') || c.contains('huami')) return 'Zepp ($fmt)';
  if (c.contains('garmin')) return 'Garmin ($fmt)';
  if (c.contains('strava')) return 'Strava ($fmt)';
  if (c.contains('coros')) return 'Coros ($fmt)';
  if (c.contains('polar')) return 'Polar ($fmt)';
  if (c.contains('suunto')) return 'Suunto ($fmt)';
  return 'Arquivo $fmt';
}

/// Monta o treino a partir da série: distância, parciais, FC e rota.
Workout _build({
  required List<_Pt> pts,
  required WorkoutKind kind,
  required String source,
  required String format,
  String? title,
  DateTime? start,
  double? totalDistM,
  double? movingSec,
  double? elapsedSec,
  int? kcal,
  double? avgHr,
}) {
  pts.sort((a, b) => a.t.compareTo(b.t));
  final begin = start ?? pts.first.t;
  final end = pts.isNotEmpty && pts.last.t.isAfter(begin)
      ? pts.last.t
      : begin.add(Duration(milliseconds: ((elapsedSec ?? movingSec ?? 0) * 1000).round()));
  if (!end.isAfter(begin)) throw ImportException('O arquivo não tem duração.');

  // Distância acumulada: usa a do arquivo; senão, soma pelo GPS (ignorando saltos).
  final hasFileDist = pts.where((p) => p.dist != null).length >= 2;
  if (!hasFileDist) {
    double acc = 0;
    _Pt? last;
    for (final p in pts) {
      if (p.lat != null && p.lng != null) {
        if (last != null) {
          final dd = haversine(last.lat!, last.lng!, p.lat!, p.lng!);
          final dt = p.t.difference(last.t).inMilliseconds / 1000;
          if (dt > 0 && dd / dt < 12) acc += dd;
        }
        last = p;
      }
      p.dist = acc;
    }
  }
  final seriesDist = pts.isEmpty ? 0.0 : (pts.lastWhere((p) => p.dist != null, orElse: () => pts.last).dist ?? 0);
  final distM = (totalDistM != null && totalDistM > 0) ? totalDistM : seriesDist;

  // Parciais por km pela série tempo × distância.
  final splits = <Split>[];
  if (kind == WorkoutKind.corrida || kind == WorkoutKind.caminhada) {
    var nextKm = 1000.0;
    var lastT = begin;
    final hrSum = <double>[];
    for (final p in pts) {
      if (p.hr != null) hrSum.add(p.hr!);
      final dd = p.dist;
      if (dd == null) continue;
      while (dd >= nextKm) {
        splits.add(Split(
          km: splits.length + 1,
          duration: p.t.difference(lastT),
          avgHr: hrSum.isEmpty ? null : hrSum.reduce((a, b) => a + b) / hrSum.length,
        ));
        hrSum.clear();
        lastT = p.t;
        nextKm += 1000;
      }
    }
  }

  // FC: amostras (no máximo ~1 a cada 5 s, para não pesar).
  final hr = <HrSample>[];
  DateTime? lastHr;
  for (final p in pts.where((p) => p.hr != null && p.hr! > 30 && p.hr! < 240)) {
    if (lastHr == null || p.t.difference(lastHr).inSeconds >= 5) {
      hr.add(HrSample(p.t, p.hr!));
      lastHr = p.t;
    }
  }
  if (hr.isEmpty && avgHr != null && avgHr > 0) hr.add(HrSample(begin, avgHr));

  // Rota reduzida a ~500 pontos.
  final geo = pts.where((p) => p.lat != null && p.lng != null && (p.lat != 0 || p.lng != 0)).toList();
  final step = math.max(1, (geo.length / 500).ceil());
  final route = [for (var i = 0; i < geo.length; i += step) RoutePoint(geo[i].lat!, geo[i].lng!)];

  final duration = end.difference(begin);
  // Duração "em movimento" do arquivo (sem pausas), quando houver, para o pace.
  final effectiveEnd = movingSec != null && movingSec > 0 && movingSec < duration.inSeconds
      ? begin.add(Duration(milliseconds: (movingSec * 1000).round()))
      : end;

  return Workout(
    id: 'import-$format-${begin.millisecondsSinceEpoch}',
    kind: kind,
    title: title?.isNotEmpty == true ? title! : _defaultTitle(kind),
    start: begin,
    end: effectiveEnd,
    source: source,
    distanceM: distM > 0 ? distM : null,
    kcal: kcal,
    hr: hr,
    splits: splits,
    route: route,
    imported: true,
  );
}

String _defaultTitle(WorkoutKind k) => switch (k) {
      WorkoutKind.corrida => 'Corrida importada',
      WorkoutKind.caminhada => 'Caminhada importada',
      WorkoutKind.bike => 'Pedal importado',
      WorkoutKind.academia => 'Treino importado',
      WorkoutKind.outro => 'Treino importado',
    };
