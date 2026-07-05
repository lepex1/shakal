import 'dart:io';
import 'dart:math' as math;
import 'dart:convert' show utf8, LineSplitter;
import 'dart:collection' show Queue;
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart' show ZipDecoder;
import 'package:image/image.dart' as img;

import 'shakal_logger.dart';

class CancellationToken {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _onCancel?.call();
  }

  void setOnCancel(void Function() callback) {
    _onCancel = callback;
  }

  void clearOnCancel() {
    _onCancel = null;
  }

  void throwIfCancelled() {
    if (_cancelled) throw CancelledException();
  }
}

class CancelledException implements Exception {}

class ShakalEngine {
  static final HttpClient _httpClient =
      HttpClient()..connectionTimeout = const Duration(minutes: 10);

  static bool isVideoFile(String path) {
    if (path.isEmpty) return false;
    final ext = p.extension(path).toLowerCase();
    return ['.mp4', '.avi', '.mov', '.mkv', '.webm'].contains(ext);
  }

  static bool isImageFile(String path) {
    if (path.isEmpty) return false;
    final ext = p.extension(path).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.bmp', '.webp'].contains(ext);
  }

  static Future<void> ensureFfmpegAsync({
    void Function(double percent, String eta)? onProgress,
    required CancellationToken token,
  }) async {
    final localFfmpeg = _getFfmpegPath();
    final ffmpegFile = File(localFfmpeg);
    if (await ffmpegFile.exists()) return;

    if (!Platform.isWindows) {
      ShakalLogger().warning('Авто-скачивание FFmpeg поддерживается только на Windows.');
      return;
    }

    ShakalLogger().process('FFmpeg не найден. Скачивание (~100 МБ)...');

    final zipPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}ffmpeg_temp.zip';

    const url =
        'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip';

    try {
      final request = await _httpClient.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Ошибка скачивания FFmpeg: HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength;
      final file = File(zipPath);
      final sink = file.openWrite();

      int totalRead = 0;
      final startTime = DateTime.now();

      await for (final chunk in response) {
        token.throwIfCancelled();
        sink.add(chunk);
        totalRead += chunk.length;

        if (totalBytes > 0 && onProgress != null) {
          final percent = totalRead / totalBytes * 100;
          final elapsed = DateTime.now().difference(startTime).inMilliseconds / 1000;
          final speedBps = elapsed > 0 ? totalRead / elapsed : 0.0;
          final speedText = speedBps >= 1_048_576
              ? '${(speedBps / 1_048_576).toStringAsFixed(1)} MB/s'
              : '${(speedBps / 1024).toStringAsFixed(0)} KB/s';
          final totalEst = elapsed / (percent / 100);
          final etaSec = (totalEst - elapsed).round().clamp(0, 999999);
          final eta = Duration(seconds: etaSec);
          final etaStr =
              '${eta.inMinutes.toString().padLeft(2, '0')}:${(eta.inSeconds % 60).toString().padLeft(2, '0')}';
          onProgress(percent, 'Осталось: $etaStr, $speedText');
        }
      }

      await sink.flush();
      await sink.close();

      ShakalLogger().process('Скачивание завершено. Распаковка...');
      onProgress?.call(100, 'Распаковка...');

      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      var found = false;
      for (final entry in archive) {
        if (entry.isFile &&
            p.basename(entry.name).toLowerCase() == 'ffmpeg.exe') {
          final outFile = File(localFfmpeg);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);
          found = true;
          break;
        }
      }

      if (!found) {
        throw Exception('ffmpeg.exe не найден в скачанном архиве.');
      }

      ShakalLogger().success('FFmpeg установлен.');
    } finally {
      try {
        await File(zipPath).delete();
      } catch (_) {}
    }
  }

  static Future<void> shakalizeImageAsync({
    required String inputPath,
    required String outputPath,
    required int quality,
    required int pixelSize,
    required CancellationToken token,
  }) async {
    ShakalLogger().process('Шакализация изображения...');

    final px = pixelSize.clamp(1, 100);
    final q = quality / 100.0;
    final cf = 1 + q * q * 5;
    final effPx = (px * cf).round().clamp(1, 100);

    final bytes = await File(inputPath).readAsBytes();
    token.throwIfCancelled();

    final src = img.decodeImage(bytes);
    if (src == null) throw Exception('Не удалось декодировать изображение');

    final w = src.width;
    final h = src.height;
    final sw = (w / effPx).round().clamp(1, w);
    final sh = (h / effPx).round().clamp(1, h);

    ShakalLogger().debug('Изображение ${w}x$h, блок пикселя: $effPx');

    final small = img.copyResize(src,
        width: sw, height: sh, interpolation: img.Interpolation.nearest);
    token.throwIfCancelled();

    final pixelated = img.copyResize(small,
        width: w, height: h, interpolation: img.Interpolation.nearest);
    token.throwIfCancelled();

    final jpgQuality = (95 * (1 - q) * (1 - q) * (1 - q) + 1).round().clamp(1, 95);
    final outBytes = img.encodeJpg(pixelated, quality: jpgQuality);
    token.throwIfCancelled();

    await File(outputPath).writeAsBytes(outBytes);

    ShakalLogger().success('Изображение ушатано. Размер: ${(outBytes.length / 1024).toStringAsFixed(1)} KB');
  }

  static Future<void> extractVideoFrameAsync({
    required String inputPath,
    required String outputPath,
    required CancellationToken token,
  }) async {
    final ffmpegPath = _getFfmpegPath();
    final result = await Process.run(ffmpegPath, [
      '-y', '-ss', '1', '-i', inputPath, '-vframes', '1',
      '-q:v', '2', outputPath,
    ]);
    token.throwIfCancelled();
    if (result.exitCode != 0) {
      throw Exception('Failed to extract frame: ${result.stderr}');
    }
  }

  static Future<void> shakalizeVideoAsync({
    required String inputPath,
    required String outputPath,
    required int quality,
    required int pixelSize,
    required int fps,
    required CancellationToken token,
    required void Function(double percent, String eta) onProgress,
  }) async {
    ShakalLogger().process('Шакализация видео...');

    final ffmpegPath = _getFfmpegPath();
    final px = pixelSize.clamp(1, 100);
    final crf = (23 + quality * 28.0 / 100.0).round();
    final maxBitrate = (5000 * math.exp(-0.045 * quality)).round();
    final audioRate = quality < 30 ? 44100 : quality < 60 ? 22050 : quality < 90 ? 16000 : 8000;
    final aBitrate = (128 - quality).clamp(8, 128);

    final args = [
      '-y',
      '-i', inputPath,
      '-vf', 'scale=iw/$px:ih/$px:flags=area,scale=iw*$px:ih*$px:flags=neighbor',
      '-r', fps.toString(),
      '-c:v', 'libx264',
      '-preset', 'faster',
      '-crf', crf.toString(),
      '-maxrate', '${maxBitrate}k',
      '-bufsize', '${maxBitrate * 2}k',
      '-c:a', 'aac',
      '-ar', audioRate.toString(),
      '-b:a', '${aBitrate}k',
      outputPath,
    ];

    ShakalLogger().debug('[FFmpeg Command]: $ffmpegPath ${args.join(' ')}');

    final process = await Process.start(ffmpegPath, args, runInShell: false);

    Duration totalDuration = Duration.zero;
    DateTime? startTime;
    int lastLoggedPercent = 0;
    final errorHistory = Queue<String>();

    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.isEmpty) return;

      errorHistory.add(line);
      if (errorHistory.length > 15) errorHistory.removeFirst();

      if (totalDuration == Duration.zero && line.contains('Duration:')) {
        final match = RegExp(r'Duration:\s*(\d{2}:\d{2}:\d{2}\.\d{2})')
            .firstMatch(line);
        if (match != null) {
          final parts = match.group(1)!.split(RegExp(r'[:.]'));
          if (parts.length >= 4) {
            totalDuration = Duration(
              hours: int.parse(parts[0]),
              minutes: int.parse(parts[1]),
              seconds: int.parse(parts[2]),
              milliseconds: int.parse(parts[3]) * 10,
            );
            ShakalLogger().process('[FFmpeg] Длительность видео: ${totalDuration.toString().substring(0, 7)}');
            ShakalLogger().debug('[FFmpeg] Целевой битрейт: $maxBitrate kbps');
          }
        }
      }

      if (totalDuration != Duration.zero && line.contains('time=')) {
        final match =
            RegExp(r'time=\s*(\d{2}:\d{2}:\d{2}\.\d{2})').firstMatch(line);
        if (match != null) {
          final parts = match.group(1)!.split(RegExp(r'[:.]'));
          if (parts.length >= 4) {
            final currentTime = Duration(
              hours: int.parse(parts[0]),
              minutes: int.parse(parts[1]),
              seconds: int.parse(parts[2]),
              milliseconds: int.parse(parts[3]) * 10,
            );

            startTime ??= DateTime.now();

            final percent = currentTime.inMilliseconds /
                totalDuration.inMilliseconds;
            if (percent > 0 && percent <= 1) {
              final currentPercentDouble = percent * 100;
              final elapsed =
                  DateTime.now().difference(startTime!).inSeconds;
              final totalEstSeconds = elapsed / percent;
              final etaSeconds =
                  (totalEstSeconds - elapsed).round().clamp(0, 999999);
              final eta = Duration(seconds: etaSeconds);
              final etaStr =
                  '${eta.inMinutes.toString().padLeft(2, '0')}:${(eta.inSeconds % 60).toString().padLeft(2, '0')}';

              onProgress(currentPercentDouble, 'Осталось: $etaStr');

              final currentPercentInt = currentPercentDouble.round();
              if (currentPercentInt >= lastLoggedPercent + 10) {
                ShakalLogger()
                    .process('Прогресс: $currentPercentInt% | $etaStr');
                lastLoggedPercent = currentPercentInt;
              }
            }
          }
        }
      }
    });

    token.throwIfCancelled();

    token.setOnCancel(() {
      try {
        if (!process.kill()) {
          process.kill(ProcessSignal.sigkill);
        }
      } catch (_) {}
    });

    try {
      final exitCode = await process.exitCode;
      token.throwIfCancelled();

      if (exitCode != 0) {
        final detailErr = errorHistory.join('\n');
        throw Exception(
            'FFmpeg ошибка (Код $exitCode).\nПоследние логи:\n$detailErr');
      }

      ShakalLogger().success('Видео ушатано! (Макс. битрейт: ${maxBitrate}k)');
    } finally {
      token.clearOnCancel();
    }
  }

  static void openFile(String path) {
    if (!File(path).existsSync()) return;
    if (Platform.isWindows) {
      Process.run('explorer', [path]);
    } else {
      Process.run('xdg-open', [path]);
    }
  }

  static void openFolder(String path) {
    if (!File(path).existsSync()) return;
    if (Platform.isWindows) {
      Process.run('explorer', ['/select,', path]);
    } else {
      Process.run('xdg-open', [p.dirname(path)]);
    }
  }

  static Future<bool> isFfmpegAvailable() async {
    final path = _getFfmpegPath();
    return File(path).exists();
  }

  static String _getFfmpegPath() {
    final appData = Platform.environment['APPDATA'] ?? '';
    final dir = p.join(appData, 'shakal');
    return p.join(dir, Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg');
  }

  static Future<String> getFfmpegPath() async => _getFfmpegPath();
}
