\
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/return_code.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StudioMayraApp());
}

class StudioMayraApp extends StatelessWidget {
  const StudioMayraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Studio Mayra 2.0',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  File? _videoFile;
  File? _imageFile;
  VideoPlayerController? _controller;

  final _scriptCtrl = TextEditingController();
  final _clothesCtrl = TextEditingController();
  final FlutterTts _tts = FlutterTts();
  bool _processing = false;
  String? _outputPath;

  String _voice = "fem_delicada";
  final List<Map<String, dynamic>> _voiceProfiles = const [
    {"id": "fem_delicada", "label": "Feminina — Delicada (padrão)", "pitch": 1.10, "rate": 0.95},
    {"id": "fem_firme",    "label": "Feminina — Firme",             "pitch": 0.98, "rate": 1.00},
    {"id": "fem_jovem",    "label": "Feminina — Jovem",             "pitch": 1.15, "rate": 1.02},
    {"id": "fem_elegante", "label": "Feminina — Elegante",          "pitch": 0.92, "rate": 0.98},
    {"id": "fem_sussurro", "label": "Feminina — Sussurrada",        "pitch": 1.05, "rate": 0.88},
    {"id": "masc_neutra",  "label": "Masculina — Neutra",           "pitch": 0.90, "rate": 0.98},
    {"id": "masc_grave",   "label": "Masculina — Grave calma",      "pitch": 0.80, "rate": 0.96},
    {"id": "masc_narrador","label": "Masculina — Narrador",         "pitch": 0.88, "rate": 1.02},
    {"id": "masc_casual",  "label": "Masculina — Casual",           "pitch": 0.95, "rate": 1.00},
    {"id": "masc_emocional","label": "Masculina — Emocional",       "pitch": 0.92, "rate": 0.94},
  ];

  @override
  void initState() {
    super.initState();
    _initTts();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.storage,
      Permission.manageExternalStorage,
      Permission.photos,
      Permission.videos,
      Permission.audio,
    ].request();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("pt-BR");
    await _tts.setPitch(1.10);
    await _tts.setSpeechRate(0.95);
    _applyVoiceProfile(_voice);
  }

  void _applyVoiceProfile(String id) async {
    final cfg = _voiceProfiles.firstWhere((e) => e["id"] == id, orElse: () => _voiceProfiles.first);
    _voice = id;
    await _tts.setLanguage("pt-BR");
    await _tts.setPitch((cfg["pitch"] as num).toDouble());
    await _tts.setSpeechRate((cfg["rate"] as num).toDouble());
    setState(() {});
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      _setVideo(file);
    }
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() => _imageFile = File(result.files.single.path!));
    }
  }

  Future<void> _setVideo(File file) async {
    _controller?.dispose();
    final c = VideoPlayerController.file(file);
    await c.initialize();
    setState(() {
      _videoFile = file;
      _controller = c;
      _outputPath = null;
    });
  }

  Future<File> _synthesizeTtsToFile(String text) async {
    final tempDir = await getTemporaryDirectory();
    final out = File('${tempDir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.wav');
    try {
      // ignore: deprecated_member_use
      await _tts.synthesizeToFile(text, out.path);
      return out;
    } catch (_) {
      await out.writeAsBytes(_generateSilentWav(durationSeconds: 1));
      return out;
    }
  }

  List<int> _generateSilentWav({int durationSeconds = 1, int sampleRate = 16000}) {
    final numSamples = durationSeconds * sampleRate;
    final dataSize = numSamples * 2;
    final totalSize = 44 + dataSize;
    final bytes = BytesBuilder();
    void writeString(String s) => bytes.add(s.codeUnits);
    void writeInt32(int v) => bytes.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
    void writeInt16(int v) => bytes.add([v & 0xff, (v >> 8) & 0xff]);
    writeString('RIFF'); writeInt32(totalSize - 8); writeString('WAVE');
    writeString('fmt '); writeInt32(16); writeInt16(1); writeInt16(1);
    writeInt32(sampleRate); writeInt32(sampleRate * 2); writeInt16(2); writeInt16(16);
    writeString('data'); writeInt32(dataSize);
    bytes.add(Uint8List(dataSize));
    return bytes.toBytes();
  }

  Future<void> _renderVideo({bool demo = false}) async {
    setState(() => _processing = true);
    try {
      final docs = await getApplicationDocumentsDirectory();
      final outPath = "${docs.path}/studio_mayra_${DateTime.now().millisecondsSinceEpoch}.mp4";
      final clothes = _clothesCtrl.text.trim();
      final dialogue = _scriptCtrl.text.trim().isEmpty ? "Olá! Este vídeo foi gerado pelo app Studio Mayra." : _scriptCtrl.text.trim();
      final descriptionPrefix = clothes.isNotEmpty ? "Aparência/roupa: $clothes. " : "";
      final ttsText = "$descriptionPrefix$dialogue";
      final ttsFile = await _synthesizeTtsToFile(ttsText);

      String inputs = "";
      final filters = <String>[];

      if (demo) {
        inputs += "-f lavfi -i color=c=black:s=1080x1920:d=4:r=30 ";
      } else {
        if (_videoFile == null) {
          _snack("Selecione um vídeo ou use o Modo Demonstração.");
          setState(() => _processing = false);
          return;
        }
        inputs += "-i \"${_videoFile!.path}\" ";
      }

      if (_imageFile != null) {
        inputs += "-i \"${_imageFile!.path}\" ";
        filters.add("[0:v][1:v]overlay=W-w-40:H-h-200:format=auto");
      }

      inputs += "-i \"${ttsFile.path}\" ";
      final vf = filters.isNotEmpty ? "-filter_complex \"${filters.join(',')}\" " : "";

      final cmd = StringBuffer()
        ..write(inputs)
        ..write(vf)
        ..write("-map 0:v:0 -map 0:a:0? -map 2:a:0 ")
        ..write("-c:v libx264 -preset veryfast -crf 18 ")
        ..write("-c:a aac -shortest ")
        ..write("\"$outPath\"");

      final session = await FFmpegKit.execute(cmd.toString());
      final rc = await session.getReturnCode();

      if (ReturnCode.isSuccess(rc)) {
        setState(() => _outputPath = outPath);
        _snack("Vídeo exportado com sucesso!");
      } else {
        _snack("Falha ao exportar vídeo.");
      }
    } catch (e) {
      _snack("Erro: $e");
    } finally {
      setState(() => _processing = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _controller?.dispose();
    _tts.stop();
    _scriptCtrl.dispose();
    _clothesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Studio Mayra 2.0'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickVideo,
                    icon: const Icon(Icons.video_file),
                    label: const Text("Selecionar vídeo (vertical)"),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _processing ? null : () => _renderVideo(demo: true),
                  icon: const Icon(Icons.play_circle_fill),
                  label: const Text("Modo demonstração"),
                ),
              ],
            ),
            if (_controller != null && _controller!.value.isInitialized) ...[
              const SizedBox(height: 12),
              AspectRatio(aspectRatio: _controller!.value.aspectRatio, child: VideoPlayer(_controller!)),
              Row(
                children: [
                  IconButton(
                    icon: Icon(_controller!.value.isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: () async {
                      setState(() {
                        _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  const Text("Prévia do vídeo selecionado"),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text("Adicionar pessoa (foto / IA)"),
                  ),
                ),
              ],
            ),
            if (_imageFile != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(_imageFile!, height: 120)),
                  const SizedBox(width: 12),
                  const Expanded(child: Text("A imagem será inserida no canto inferior direito.\nVersões futuras: corpo/pose e lip-sync neural completa.")),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text("Voz (10 perfis):", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _voice,
              items: _voiceProfiles.map((v) => DropdownMenuItem<String>(
                value: v["id"],
                child: Text(v["label"]),
              )).toList(),
              onChanged: (v) { if (v != null) _applyVoiceProfile(v); },
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Text("Descrição de roupas/aparência:", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _clothesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: "Ex.: vestido azul claro de verão, cabelo preso...",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text("Roteiro / Diálogo:", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _scriptCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: "Descreva o que a pessoa diz/faz...",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _processing ? null : () => _renderVideo(demo: false),
              icon: _processing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.movie_creation_outlined),
              label: Text(_processing ? "Processando..." : "Gerar vídeo"),
            ),
            const SizedBox(height: 12),
            if (_outputPath != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text("Vídeo exportado com sucesso. Veja na galeria do app.", style: TextStyle(fontWeight: FontWeight.bold)),
                  Text("Compatível com Instagram, TikTok, WhatsApp e YouTube."),
                ],
              ),
            const SizedBox(height: 24),
            const Divider(),
            const Text(
              "Confirme que todas as pessoas têm autorização de uso de imagem. Evite músicas com direitos autorais.",
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
