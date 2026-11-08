import 'dart:convert';
import 'dart:typed_data';

import 'package:app_corrida/models/workout.dart';
import 'package:app_corrida/services/importers.dart';
import 'package:fit_sdk/fit_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

/// GPX de 2 km para o norte, 1 ponto a cada 10 s (~3,3 m/s ≈ 5:00 /km), com FC.
String gpx({String creator = 'Zepp App', String type = 'running', bool withTime = true}) {
  final b = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n'
      '<gpx version="1.1" creator="$creator" xmlns="http://www.topografix.com/GPX/1/1" '
      'xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">'
      '<trk><name>Corrida matinal</name><type>$type</type><trkseg>');
  final t0 = DateTime.utc(2026, 11, 7, 10);
  for (var i = 0; i <= 60; i++) {
    final lat = -23.55 + i * 0.0003; // ~33,4 m por ponto
    final t = t0.add(Duration(seconds: i * 10)).toIso8601String();
    b.write('<trkpt lat="$lat" lon="-46.63"><ele>760</ele>${withTime ? '<time>$t</time>' : ''}'
        '<extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>${140 + i % 10}</gpxtpx:hr>'
        '</gpxtpx:TrackPointExtension></extensions></trkpt>');
  }
  b.write('</trkseg></trk></gpx>');
  return b.toString();
}

const tcx = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
 <Activities><Activity Sport="Running"><Id>2026-11-06T09:00:00Z</Id>
  <Lap StartTime="2026-11-06T09:00:00Z"><TotalTimeSeconds>1500</TotalTimeSeconds><DistanceMeters>5000</DistanceMeters><Calories>350</Calories>
   <Track>
    <Trackpoint><Time>2026-11-06T09:00:00Z</Time><DistanceMeters>0</DistanceMeters><HeartRateBpm><Value>120</Value></HeartRateBpm></Trackpoint>
    <Trackpoint><Time>2026-11-06T09:05:00Z</Time><DistanceMeters>1000</DistanceMeters><HeartRateBpm><Value>150</Value></HeartRateBpm></Trackpoint>
    <Trackpoint><Time>2026-11-06T09:10:00Z</Time><DistanceMeters>2000</DistanceMeters><HeartRateBpm><Value>155</Value></HeartRateBpm></Trackpoint>
    <Trackpoint><Time>2026-11-06T09:25:00Z</Time><DistanceMeters>5000</DistanceMeters><HeartRateBpm><Value>160</Value></HeartRateBpm></Trackpoint>
   </Track></Lap>
  <Creator><Name>Garmin Forerunner 265</Name></Creator>
 </Activity></Activities>
</TrainingCenterDatabase>''';

Uint8List fit({int sport = 1}) {
  const epoch = 631065600;
  final start = DateTime.utc(2026, 11, 5, 7).millisecondsSinceEpoch ~/ 1000 - epoch;
  final e = Encode()..open();
  final id = Mesg.fromMesgNum(MesgNum.fileId)
    ..setFieldValue(0, 4)
    ..setFieldValue(1, Manufacturer.garmin)
    ..setFieldValue(4, start);
  e.writeMesgDefinition(MesgDefinition.fromMesg(id));
  e.writeMesg(id);
  Mesg? recDef;
  for (var i = 0; i <= 36; i++) {
    final r = Mesg.fromMesgNum(MesgNum.record)
      ..setFieldValue(253, start + i * 50)
      ..setFieldValue(0, ((-23.55 + i * 0.0005) / (180 / 2147483648)).round())
      ..setFieldValue(1, (-46.63 / (180 / 2147483648)).round())
      ..setFieldValue(3, 150)
      ..setFieldValue(5, i * 100.0); // 100 m a cada 50 s → 8:20 /km
    if (recDef == null) {
      e.writeMesgDefinition(MesgDefinition.fromMesg(r));
      recDef = r;
    }
    e.writeMesg(r);
  }
  final s = Mesg.fromMesgNum(MesgNum.session)
    ..setFieldValue(253, start + 1800)
    ..setFieldValue(2, start)
    ..setFieldValue(5, sport)
    ..setFieldValue(7, 1800.0)
    ..setFieldValue(8, 1800.0)
    ..setFieldValue(9, 3600.0)
    ..setFieldValue(11, 280)
    ..setFieldValue(16, 150);
  e.writeMesgDefinition(MesgDefinition.fromMesg(s));
  e.writeMesg(s);
  return e.close();
}

void main() {
  group('GPX', () {
    test('lê distância, duração, FC, parciais, rota e fonte Zepp', () {
      final w = importActivity(Uint8List.fromList(utf8.encode(gpx())), fileName: 'treino.gpx');
      expect(w.kind, WorkoutKind.corrida);
      expect(w.source, 'Zepp (GPX)');
      expect(w.title, 'Corrida matinal');
      expect(w.duration, const Duration(minutes: 10));
      expect(w.distanceKm!, closeTo(2.0, 0.03));
      expect(w.paceSecPerKm!, closeTo(300, 6));
      expect(w.splits.length, 2); // 2,0016 km → 2 km completos
      expect(w.splits.first.duration.inSeconds, closeTo(300, 12));
      expect(w.hr, isNotEmpty);
      expect(w.avgHr!, inInclusiveRange(140, 150));
      expect(w.route.length, 61);
    });

    test('reconhece caminhada e bike pelo tipo', () {
      expect(importActivity(Uint8List.fromList(utf8.encode(gpx(type: 'walking')))).kind, WorkoutKind.caminhada);
      expect(importActivity(Uint8List.fromList(utf8.encode(gpx(type: 'cycling', creator: 'Strava')))).kind, WorkoutKind.bike);
    });

    test('rota sem horário (planejada) é recusada com mensagem clara', () {
      expect(
        () => importActivity(Uint8List.fromList(utf8.encode(gpx(withTime: false)))),
        throwsA(isA<ImportException>().having((e) => e.message, 'msg', contains('rota planejada'))),
      );
    });
  });

  group('TCX', () {
    test('usa totais das voltas e a distância do arquivo', () {
      final w = importActivity(Uint8List.fromList(utf8.encode(tcx)), fileName: 'x.tcx');
      expect(w.kind, WorkoutKind.corrida);
      expect(w.source, 'Garmin (TCX)');
      expect(w.distanceKm, 5);
      expect(w.duration, const Duration(minutes: 25));
      expect(w.kcal, 350);
      expect(w.splits.map((s) => s.duration.inMinutes).take(2), [5, 5]);
      expect(w.route, isEmpty);
    });
  });

  group('FIT', () {
    test('lê sessão (distância, tempo, calorias), fabricante, registros e parciais', () {
      final w = importActivity(fit(), fileName: 'a.fit');
      expect(w.kind, WorkoutKind.corrida);
      expect(w.source, 'Garmin (FIT)');
      expect(w.distanceKm, 3.6);
      expect(w.duration, const Duration(minutes: 30));
      expect(w.kcal, 280);
      expect(w.avgHr, 150);
      expect(w.splits.length, 3);
      expect(w.splits.first.duration.inSeconds, 500);
      expect(w.route.length, 37);
      expect(w.route.first.lat, closeTo(-23.55, 1e-5));
    });

    test('esporte bike vira Bike', () {
      expect(importActivity(fit(sport: 2)).kind, WorkoutKind.bike);
    });
  });

  test('formato desconhecido gera erro amigável', () {
    expect(() => importActivity(Uint8List.fromList(utf8.encode('nome,tempo\nJoão,10'))),
        throwsA(isA<ImportException>()));
  });
}
