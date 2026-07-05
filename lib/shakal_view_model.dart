import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'shakal_engine.dart';
import 'shakal_logger.dart';

class ShakalViewModel extends ChangeNotifier {
  CancellationToken? _cts;

  String? _selectedPath;
  String? _outputPath;
  String _statusSubtext = 'Готов к работе';
  String _processButtonText = 'УШАТАТЬ В ХЛАМ';
  bool _ffmpegAvailable = true;
  bool _isDownloadingFfmpeg = false;

  Uint8List? _previewBytes;
  String? _previewTempPath;

  int _qualityValue = 80;
  String _qualityText = '80';
  int _pixelSizeValue = 5;
  String _pixelSizeText = '5';
  int _fpsValue = 24;
  String _fpsText = '24';
  int? _originalFps;

  bool _isProcessing = false;
  bool _isFileLoaded = false;
  bool _isResultAvailable = false;

  double _progressPercent = 0;
  String _etaText = 'Подготовка...';

  String _fileName = '';
  bool _isVideo = false;

  String? get selectedPath => _selectedPath;
  String? get outputPath => _outputPath;
  String get statusSubtext => _statusSubtext;
  String get processButtonText => _processButtonText;
  bool get ffmpegAvailable => _ffmpegAvailable;
  bool get isDownloadingFfmpeg => _isDownloadingFfmpeg;

  int get qualityValue => _qualityValue;
  String get qualityText => _qualityText;
  int get pixelSizeValue => _pixelSizeValue;
  String get pixelSizeText => _pixelSizeText;
  int get fpsValue => _fpsValue;
  String get fpsText => _fpsText;
  int? get originalFps => _originalFps;

  bool get isProcessing => _isProcessing;
  bool get isFileLoaded => _isFileLoaded;
  bool get isResultAvailable => _isResultAvailable;
  double get progressPercent => _progressPercent;
  int get progressPercentRaw => _progressPercent.round();
  String get etaText => _etaText;
  String get fileName => _fileName;
  bool get isVideo => _isVideo;
  Uint8List? get previewBytes => _previewBytes;

  set outputPath(String? value) {
    _outputPath = value;
    notifyListeners();
  }

  void setFfmpegUnavailable() {
    _ffmpegAvailable = false;
    notifyListeners();
  }

  set qualityValue(int value) {
    final clamped = value.clamp(0, 100);
    if (clamped == _qualityValue) return;
    _qualityValue = clamped;
    _qualityText = clamped.toString();
    ShakalLogger().debug('Сжатие: $clamped%');
    notifyListeners();
  }

  set qualityText(String value) {
    _qualityText = value;
    final parsed = int.tryParse(value);
    if (parsed != null) qualityValue = parsed;
    notifyListeners();
  }

  set pixelSizeValue(int value) {
    final clamped = value.clamp(1, 50);
    if (clamped == _pixelSizeValue) return;
    _pixelSizeValue = clamped;
    _pixelSizeText = clamped.toString();
    ShakalLogger().debug('Пиксель: ${clamped}px');
    notifyListeners();
  }

  set pixelSizeText(String value) {
    _pixelSizeText = value;
    final parsed = int.tryParse(value);
    if (parsed != null) pixelSizeValue = parsed;
    notifyListeners();
  }

  set fpsValue(int value) {
    final maxFps = _originalFps ?? 60;
    final clamped = value.clamp(1, maxFps);
    if (clamped == _fpsValue) return;
    _fpsValue = clamped;
    _fpsText = clamped.toString();
    ShakalLogger().debug('FPS: $clamped');
    notifyListeners();
  }

  set fpsText(String value) {
    _fpsText = value;
    final parsed = int.tryParse(value);
    if (parsed != null) fpsValue = parsed;
    notifyListeners();
  }

  Future<void> loadFileAsync(String path) async {
    if (path.isEmpty || !File(path).existsSync()) return;

    _selectedPath = path;
    _isFileLoaded = true;
    _isResultAvailable = false;
    _fileName = p.basename(path);
    _isVideo = ShakalEngine.isVideoFile(path);
    _originalFps = null;
    _previewBytes = null;

    ShakalLogger().success('Загружен файл: $path');

    _statusSubtext = 'Файл загружен';
    notifyListeners();

    if (_isVideo) {
      final detected = await ShakalEngine.getVideoFpsAsync(path);
      _originalFps = detected;
      if (_fpsValue > detected) {
        _fpsValue = detected;
        _fpsText = detected.toString();
      }
      ShakalLogger().debug('Определён FPS видео: $detected');
    }

    final ext = _isVideo ? p.extension(path) : '.jpg';
    _outputPath = p.join(
        p.dirname(path), '${p.basenameWithoutExtension(path)}_shakal$ext');
    notifyListeners();

    loadPreviewAsync();
  }

  Future<void> loadPreviewAsync() async {
    final source = _isResultAvailable ? _outputPath : _selectedPath;
    if (source == null) return;
    try {
      if (_isVideo) {
        final tempDir = Directory.systemTemp;
        if (!await tempDir.exists()) await tempDir.create(recursive: true);
        _previewTempPath = '${tempDir.path}${Platform.pathSeparator}shakal_preview.jpg';
        await ShakalEngine.extractVideoFrameAsync(
          inputPath: source,
          outputPath: _previewTempPath!,
          token: CancellationToken(),
        );
        _previewBytes = await File(_previewTempPath!).readAsBytes();
      } else {
        _previewBytes = await File(source).readAsBytes();
      }
      notifyListeners();
    } catch (ex) {
      ShakalLogger().warning('Не удалось загрузить превью: $ex');
    }
  }

  void clearFile() {
    _selectedPath = null;
    _outputPath = null;
    _isFileLoaded = false;
    _isResultAvailable = false;
    _fileName = '';
    _isVideo = false;
    _statusSubtext = 'Готов к работе';
    _previewBytes = null;
    if (_previewTempPath != null) {
      try { File(_previewTempPath!).delete(); } catch (_) {}
      _previewTempPath = null;
    }
    notifyListeners();
  }

  Future<void> processMediaAsync() async {
    if (_selectedPath == null ||
        _selectedPath!.isEmpty ||
        _outputPath == null ||
        _outputPath!.isEmpty) {
      return;
    }

    _cts = CancellationToken();
    final token = _cts!;

    _isProcessing = true;
    _isResultAvailable = false;
    _processButtonText = 'ШАКАЛИЗАЦИЯ...';
    _etaText = 'Подготовка...';
    _progressPercent = 0;
    notifyListeners();

    try {
      await ShakalEngine.ensureFfmpegAsync(
        onProgress: (percent, eta) {
          _progressPercent = percent;
          _etaText = eta;
          notifyListeners();
        },
        token: token,
      );

      _progressPercent = 0;
      notifyListeners();

      if (_isVideo) {
        await ShakalEngine.shakalizeVideoAsync(
          inputPath: _selectedPath!,
          outputPath: _outputPath!,
          quality: _qualityValue,
          pixelSize: _pixelSizeValue,
          fps: _fpsValue,
          token: token,
          onProgress: (percent, eta) {
            _progressPercent = percent;
            _etaText = eta;
            notifyListeners();
          },
        );
      } else {
        await ShakalEngine.shakalizeImageAsync(
          inputPath: _selectedPath!,
          outputPath: _outputPath!,
          quality: _qualityValue,
          pixelSize: _pixelSizeValue,
          token: token,
        );
      }

      _isResultAvailable = true;
      _statusSubtext = 'Готово';
      _previewBytes = null;
      notifyListeners();
      loadPreviewAsync();
    } on CancelledException {
      ShakalLogger().warning('Операция отменена.');
      _cleanFailedOutput();
    } catch (ex) {
      ShakalLogger().error('Ошибка: $ex');
      _etaText = 'Сбой: $ex';
      notifyListeners();
    } finally {
      _cts?.clearOnCancel();
      _cts = null;
      _isProcessing = false;
      _processButtonText = 'УШАТАТЬ В ХЛАМ';
      notifyListeners();
    }
  }

  void cancelProcessing() {
    if (_cts != null && !_cts!.isCancelled) {
      ShakalLogger().warning('Отмена...');
      _cts!.cancel();
    }
  }

  void viewResult() {
    if (_outputPath != null && File(_outputPath!).existsSync()) {
      ShakalEngine.openFile(_outputPath!);
    }
  }

  void openOutputFolder() {
    if (_outputPath != null && File(_outputPath!).existsSync()) {
      ShakalEngine.openFolder(_outputPath!);
    }
  }

  void _cleanFailedOutput() {
    if (_outputPath != null && File(_outputPath!).existsSync()) {
      try {
        File(_outputPath!).delete();
      } catch (_) {}
    }
  }

  Future<void> checkFfmpegAsync() async {
    _ffmpegAvailable = await ShakalEngine.isFfmpegAvailable();
    notifyListeners();
  }

  Future<void> downloadFfmpegAsync() async {
    _isDownloadingFfmpeg = true;
    _statusSubtext = 'Скачивание FFmpeg...';
    notifyListeners();

    final token = CancellationToken();
    try {
      await ShakalEngine.ensureFfmpegAsync(
        onProgress: (percent, eta) {
          _progressPercent = percent;
          _etaText = eta;
          notifyListeners();
        },
        token: token,
      );
      _ffmpegAvailable = true;
      _statusSubtext = 'FFmpeg установлен';
    } catch (ex) {
      ShakalLogger().error('Ошибка скачивания FFmpeg: $ex');
      rethrow;
    } finally {
      _isDownloadingFfmpeg = false;
      _progressPercent = 0;
      notifyListeners();
    }
  }
}
