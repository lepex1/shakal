import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;

import '../shakal_view_model.dart';
import '../shakal_engine.dart';
import '../shakal_logger.dart';
import 'log_viewer_dialog.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late final ShakalViewModel _vm;
  bool _ffmpegInitialized = false;
  String? _ffmpegError;

  @override
  void initState() {
    super.initState();
    _vm = ShakalViewModel();
    _checkFfmpeg();
    windowManager.setTitle('SHAKAL');
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  Future<void> _checkFfmpeg() async {
    final available = await ShakalEngine.isFfmpegAvailable();
    final ffmpegPath = await ShakalEngine.getFfmpegPath();
    if (available) {
      ShakalLogger().success('FFmpeg найден: $ffmpegPath');
    } else {
      ShakalLogger().debug('FFmpeg не найден по пути: $ffmpegPath');
      _vm.setFfmpegUnavailable();
    }
    if (!mounted) return;
    setState(() => _ffmpegInitialized = true);
  }

  Future<void> _downloadFfmpeg() async {
    setState(() => _ffmpegError = null);
    try {
      await _vm.downloadFfmpegAsync();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _ffmpegError = e.toString());
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp4', 'avi', 'mov', 'mkv', 'webm',
        'jpg', 'jpeg', 'png', 'bmp', 'webp',
      ],
    );
    if (result != null && result.files.single.path != null) {
      await _vm.loadFileAsync(result.files.single.path!);
    }
  }

  Future<void> _browseOutput() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null && _vm.outputPath != null) {
      final name = p.basename(_vm.outputPath!);
      _vm.outputPath = p.join(dir, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!_ffmpegInitialized) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: cs.surface,
          body: Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    children: [
                      _HeaderBar(
                        cs: cs,
                        statusSubtext: _vm.statusSubtext,
                      ),
                      Expanded(
                        child: _vm.isFileLoaded
                            ? AbsorbPointer(
                                absorbing: !_vm.ffmpegAvailable,
                                child: Opacity(
                                  opacity: _vm.ffmpegAvailable ? 1.0 : 0.4,
                                  child: _buildLoadedContent(cs),
                                ),
                              )
                            : _buildDropZone(cs),
                      ),
                    ],
                  ),
                ),
              ),
              if (!_vm.ffmpegAvailable)
                _buildFfmpegOverlay(cs),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFfmpegOverlay(ColorScheme cs) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.download_for_offline_outlined,
                    size: 56, color: cs.primary),
                const SizedBox(height: 20),
                Text(
                  'Требуется FFmpeg',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Для обработки файлов необходим FFmpeg.\nНажмите «Скачать», чтобы автоматически загрузить и установить его.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                if (_vm.isDownloadingFfmpeg) ...[
                  const SizedBox(height: 24),
                  LinearProgressIndicator(
                    value: _vm.progressPercent / 100,
                    minHeight: 6,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _vm.etaText,
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
                if (_ffmpegError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _ffmpegError!,
                    style: TextStyle(fontSize: 12, color: cs.error),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed:
                        _vm.isDownloadingFfmpeg ? null : _downloadFfmpeg,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: Text(
                      _vm.isDownloadingFfmpeg ? 'СКАЧИВАНИЕ...' : 'СКАЧАТЬ',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropZone(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: DropTarget(
          onDragDone: (detail) {
            if (detail.files.isNotEmpty) {
              final path = detail.files.first.path;
              if (ShakalEngine.isVideoFile(path) || ShakalEngine.isImageFile(path)) {
                _vm.loadFileAsync(path);
              } else {
                ShakalLogger().warning('Отклонён неподдерживаемый файл: $path');
              }
            }
          },
          child: AbsorbPointer(
            absorbing: !_vm.ffmpegAvailable,
            child: Opacity(
              opacity: _vm.ffmpegAvailable ? 1.0 : 0.4,
              child: Container(
                constraints:
                    const BoxConstraints(maxWidth: 400, maxHeight: 350),
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: cs.secondaryContainer.withValues(alpha: 0.4),
                  border: Border.all(color: cs.outlineVariant, width: 2),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.cloud_upload_outlined,
                      size: 64,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Перетащите файл сюда',
                      style: TextStyle(
                        fontSize: 16,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'MP4, AVI, MOV, MKV, WEBM, JPG, PNG',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.tonal(
                      onPressed: _pickFile,
                      child: const Text('ВЫБРАТЬ ФАЙЛ'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadedContent(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        children: [
          _PreviewCard(vm: _vm, cs: cs),
          const SizedBox(height: 16),
          _ControlsCard(vm: _vm, cs: cs),
          const SizedBox(height: 16),
          _OutputPathCard(vm: _vm, cs: cs, onBrowse: _browseOutput),
          const SizedBox(height: 16),
          _ActionButtons(vm: _vm, cs: cs),
          if (_vm.isResultAvailable) ...[
            const SizedBox(height: 12),
            _ResultButton(vm: _vm, cs: cs),
          ],
          if (_vm.isProcessing) ...[
            const SizedBox(height: 16),
            _ProgressCard(vm: _vm, cs: cs),
          ],
        ],
      ),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  final ColorScheme cs;
  final String statusSubtext;
  const _HeaderBar({
    required this.cs,
    required this.statusSubtext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      color: cs.surface,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.auto_fix_high, color: cs.onPrimary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SHAKAL',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  statusSubtext,
                  style:
                      TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.terminal, color: cs.onSurfaceVariant),
            tooltip: 'Журнал событий',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const LogViewerDialog(),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final ShakalViewModel vm;
  final ColorScheme cs;
  const _PreviewCard({required this.vm, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (vm.previewBytes != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      vm.previewBytes!,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stack) => _previewPlaceholder(cs),
                    ),
                    if (!vm.isVideo)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Оригинал',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            )
          else
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _previewPlaceholder(cs),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vm.fileName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        vm.isVideo ? 'Видеофайл' : 'Изображение',
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => vm.clearFile(),
                  icon: Icon(Icons.close,
                      color: cs.onSurfaceVariant, size: 18),
                  style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewPlaceholder(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              vm.isVideo ? Icons.movie_outlined : Icons.image_outlined,
              size: 48,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 8),
            Text(
              vm.isVideo ? 'Загрузка превью...' : 'Изображение',
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlsCard extends StatelessWidget {
  final ShakalViewModel vm;
  final ColorScheme cs;
  const _ControlsCard({required this.vm, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _SliderSection(
            label: 'Сжатие',
            value: '${vm.qualityValue}%',
            sliderValue: vm.qualityValue.toDouble(),
            textValue: vm.qualityText,
            min: 0,
            max: 100,
            onSliderChanged: (v) => vm.qualityValue = v.round(),
            onTextChanged: (v) => vm.qualityText = v,
            enabled: !vm.isProcessing,
            cs: cs,
            bottomLabels: const ['Меньше', 'Больше'],
          ),
          const SizedBox(height: 20),
          _SliderSection(
            label: 'Размер пикселя',
            value: '${vm.pixelSizeValue}px',
            sliderValue: vm.pixelSizeValue.toDouble(),
            textValue: vm.pixelSizeText,
            min: 1,
            max: 50,
            onSliderChanged: (v) => vm.pixelSizeValue = v.round(),
            onTextChanged: (v) => vm.pixelSizeText = v,
            enabled: !vm.isProcessing,
            cs: cs,
            bottomLabels: const ['Мелко', 'Крупно'],
          ),
          if (vm.isVideo) ...[
            const SizedBox(height: 20),
            _SliderSection(
              label: 'FPS${vm.originalFps != null ? ' (ориг. ${vm.originalFps})' : ''}',
              value: '${vm.fpsValue} FPS',
              sliderValue: vm.fpsValue.toDouble(),
              textValue: vm.fpsText,
              min: 1,
              max: (vm.originalFps ?? 60).toDouble(),
              onSliderChanged: (v) => vm.fpsValue = v.round(),
              onTextChanged: (v) => vm.fpsText = v,
              enabled: !vm.isProcessing,
              cs: cs,
              bottomLabels: const ['Слайд-шоу', 'Оригинал'],
            ),
          ],
        ],
      ),
    );
  }
}

class _SliderSection extends StatelessWidget {
  final String label;
  final String value;
  final double sliderValue;
  final String textValue;
  final double min;
  final double max;
  final ValueChanged<double> onSliderChanged;
  final ValueChanged<String> onTextChanged;
  final bool enabled;
  final ColorScheme cs;
  final List<String>? bottomLabels;

  const _SliderSection({
    required this.label,
    required this.value,
    required this.sliderValue,
    required this.textValue,
    required this.min,
    required this.max,
    required this.onSliderChanged,
    required this.onTextChanged,
    required this.enabled,
    required this.cs,
    this.bottomLabels,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
            SizedBox(
              width: 72,
              child: TextField(
                controller: TextEditingController(text: textValue)
                  ..selection =
                      TextSelection.collapsed(offset: textValue.length),
                enabled: enabled,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                ),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: cs.outline),
                  ),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                onChanged: onTextChanged,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              value.split(' ').skip(1).join(' '),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          min: min,
          max: max,
          value: sliderValue.clamp(min, max),
          onChanged: enabled ? onSliderChanged : null,
        ),
        if (bottomLabels != null)
          Row(
            children: [
              Text(
                bottomLabels![0],
                style: TextStyle(
                    fontSize: 11, color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                bottomLabels![1],
                style: TextStyle(
                    fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
      ],
    );
  }
}

class _OutputPathCard extends StatelessWidget {
  final ShakalViewModel vm;
  final ColorScheme cs;
  final VoidCallback onBrowse;
  const _OutputPathCard(
      {required this.vm, required this.cs, required this.onBrowse});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Куда сохранить',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller:
                      TextEditingController(text: vm.outputPath ?? '')
                        ..selection = TextSelection.collapsed(
                            offset: (vm.outputPath ?? '').length),
                  enabled: vm.isFileLoaded,
                  decoration: InputDecoration(
                    hintText: 'Путь сохранения...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  onChanged: (v) => vm.outputPath = v,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: vm.isFileLoaded ? onBrowse : null,
                icon: Icon(Icons.folder_outlined,
                    color: cs.onSurfaceVariant),
                style: IconButton.styleFrom(
                  backgroundColor: cs.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final ShakalViewModel vm;
  final ColorScheme cs;
  const _ActionButtons({required this.vm, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: FilledButton(
              onPressed:
                  vm.isProcessing ? null : () => vm.processMediaAsync(),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_fix_high, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    vm.processButtonText,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (vm.isProcessing) ...[
          const SizedBox(width: 12),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: () => vm.cancelProcessing(),
              style: FilledButton.styleFrom(
                backgroundColor: cs.errorContainer,
                foregroundColor: cs.onErrorContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.close, size: 18),
                  const SizedBox(width: 6),
                  const Text(
                    'Отмена',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ResultButton extends StatelessWidget {
  final ShakalViewModel vm;
  final ColorScheme cs;
  const _ResultButton({required this.vm, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: FilledButton.tonal(
              onPressed: () => vm.viewResult(),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_circle_outline, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Открыть результат',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 44,
          child: FilledButton.tonal(
            onPressed: () => vm.openOutputFolder(),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_open, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Открыть папку',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final ShakalViewModel vm;
  final ColorScheme cs;
  const _ProgressCard({required this.vm, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Обработка...',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '${vm.progressPercentRaw}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: vm.progressPercent / 100,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            vm.etaText,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
