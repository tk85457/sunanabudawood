// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'chapter_data.dart';

Future<void> main() async {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  final outPath = '${Directory.current.path}/assets/db/sunan_abu_dawood.db';
  final outFile = File(outPath);
  if (await outFile.exists()) await outFile.delete();

  print('Building database for Sunan Abu Dawood at: $outPath');

  final db = await factory.openDatabase(
    outPath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE chapters (
            id INTEGER PRIMARY KEY,
            book_number INTEGER NOT NULL,
            title_arabic TEXT NOT NULL,
            title_urdu TEXT NOT NULL,
            title_english TEXT NOT NULL,
            hadith_count INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE hadiths (
            id INTEGER PRIMARY KEY,
            chapter_id INTEGER NOT NULL,
            hadith_number INTEGER NOT NULL,
            arabic_text TEXT NOT NULL,
            urdu_text TEXT NOT NULL,
            english_text TEXT NOT NULL,
            grade TEXT NOT NULL DEFAULT '',
            FOREIGN KEY (chapter_id) REFERENCES chapters (id)
          )''');
        await db.execute('CREATE INDEX idx_hadiths_chapter ON hadiths(chapter_id)');
        await db.execute('CREATE INDEX idx_hadiths_number ON hadiths(hadith_number)');
      },
    ),
  );

  // 1. Insert chapters
  print('Inserting ${chapters.length} chapters...');
  final batch = db.batch();
  for (var c in chapters) {
    batch.insert('chapters', {
      'id': c[0],
      'book_number': c[0],
      'title_arabic': c[1],
      'title_urdu': c[2],
      'title_english': c[3],
      'hadith_count': 0, // Will update later
    });
  }
  await batch.commit(noResult: true);

  // 2. Load JSON files
  final engPath = r'C:\Windows.old\Users\tk854\Music\Downloads\hadith-api-1\hadith-api-1\editions\eng-abudawud.json';
  final urdPath = r'C:\Windows.old\Users\tk854\Music\Downloads\hadith-api-1\hadith-api-1\editions\urd-abudawud.json';
  final araPath = r'C:\Windows.old\Users\tk854\Music\Downloads\hadith-api-1\hadith-api-1\editions\ara-abudawud.json';

  print('Loading English JSON...');
  final engData = jsonDecode(await File(engPath).readAsString());
  print('Loading Urdu JSON...');
  final urdData = jsonDecode(await File(urdPath).readAsString());
  print('Loading Arabic JSON...');
  final araData = jsonDecode(await File(araPath).readAsString());

  final List<dynamic> engList = engData['hadiths'];
  final List<dynamic> urdList = urdData['hadiths'];
  final List<dynamic> araList = araData['hadiths'];

  print('Found ${araList.length} hadiths in Arabic file.');

  // 3. Map translations and extract grades by hadithnumber
  final Map<int, String> urduMap = {
    for (var h in urdList) h['hadithnumber'] as int: h['text'] as String
  };
  
  final Map<int, String> englishMap = {};
  final Map<int, String> gradeMap = {};
  
  for (var h in engList) {
    int hNum = h['hadithnumber'] as int;
    englishMap[hNum] = h['text'] as String;
    
    // Calculate most common grade
    var grades = h['grades'] as List<dynamic>?;
    String finalGrade = '';
    if (grades != null && grades.isNotEmpty) {
      Map<String, int> counts = {};
      for (var g in grades) {
        String gradeStr = g['grade']?.toString().trim() ?? '';
        if (gradeStr.isNotEmpty) counts[gradeStr] = (counts[gradeStr] ?? 0) + 1;
      }
      if (counts.isNotEmpty) {
        var maxCount = 0;
        counts.forEach((key, val) {
          if (val > maxCount) {
            maxCount = val;
            finalGrade = key;
          }
        });
      }
    }
    gradeMap[hNum] = finalGrade;
  }

  // 4. Insert Hadiths
  print('Inserting hadiths...');
  var hBatch = db.batch();
  int count = 0;

  for (var h in araList) {
    final int hNum = h['hadithnumber'];
    final int bookNum = h['reference']['book'];
    final String arabicText = h['text'];
    final String urduText = urduMap[hNum] ?? 'ترجمہ دستیاب نہیں';
    final String englishText = englishMap[hNum] ?? 'Translation not available';
    final String hadithGrade = gradeMap[hNum] ?? '';

    hBatch.insert('hadiths', {
      'chapter_id': bookNum,
      'hadith_number': hNum,
      'arabic_text': arabicText,
      'urdu_text': urduText,
      'english_text': englishText,
      'grade': hadithGrade,
    });

    count++;
    if (count % 500 == 0) {
      await hBatch.commit(noResult: true);
      hBatch = db.batch();
      print('Inserted $count hadiths...');
    }
  }
  await hBatch.commit(noResult: true);

  // 5. Update counts
  print('Updating chapter counts...');
  await db.execute('''
    UPDATE chapters 
    SET hadith_count = (SELECT COUNT(*) FROM hadiths WHERE chapter_id = chapters.id)
  ''');

  final finalCountRes = await db.rawQuery('SELECT COUNT(*) as count FROM hadiths');
  final finalCount = finalCountRes.first['count'];
  print('✓ Database build complete!');
  print('✓ Total Hadiths: $finalCount');
  
  await db.close();
}
