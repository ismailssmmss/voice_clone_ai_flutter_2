import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api/voice_engine.dart';

final VoiceEngine engine = HttpVoiceEngine();

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'Voice Clone AI',
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const Home(),
      );
  ThemeData _theme(Brightness b) {
    final dark = b == Brightness.dark;
    return ThemeData(
      brightness: b,
      colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF005F66), brightness: b,
          primary: dark ? const Color(0xFF5FD3DB) : const Color(0xFF005F66)),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64),
              textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56),
              side: const BorderSide(width: 2),
              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
    );
  }
}

class VoiceItem {
  String id, name, date;
  VoiceItem(this.id, this.name, this.date);
  Map toJson() => {'id': id, 'name': name, 'date': date};
  static VoiceItem from(Map m) => VoiceItem(m['id'], m['name'], m['date']);
}

class Store {
  static Future<List<VoiceItem>> load() async {
    final p = await SharedPreferences.getInstance();
    return (jsonDecode(p.getString('voices') ?? '[]') as List).map((e) => VoiceItem.from(e)).toList();
  }
  static Future<void> save(List<VoiceItem> v) async =>
      (await SharedPreferences.getInstance()).setString('voices', jsonEncode(v.map((e) => e.toJson()).toList()));
}

void say(BuildContext c, String m) {
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m, style: const TextStyle(fontSize: 18))));
}

class Home extends StatelessWidget {
  const Home({super.key});
  @override
  Widget build(BuildContext c) {
    Widget b(String t, Widget p, {bool main = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: main
              ? FilledButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => p)), child: Text(t))
              : OutlinedButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => p)), child: Text(t)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Clone AI')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Semantics(header: true, child: const Text('مرحبًا بك', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold))),
        const SizedBox(height: 16),
        b('إنشاء صوت', const CreateVoice(), main: true),
        b('أصواتي', const Voices()),
        b('تحويل النص إلى كلام', const Tts()),
        b('الملفات', const Files()),
        b('الإعدادات', const SettingsPage()),
      ]),
    );
  }
}

class CreateVoice extends StatefulWidget {
  const CreateVoice({super.key});
  @override
  State<CreateVoice> createState() => _CreateVoiceState();
}

class _CreateVoiceState extends State<CreateVoice> {
  bool own = false, agree = false, recording = false, busy = false;
  File? sample;
  final name = TextEditingController();
  final rec = AudioRecorder();

  Future<void> toggleRec() async {
    if (recording) {
      final p = await rec.stop();
      setState(() { recording = false; if (p != null) sample = File(p); });
      return;
    }
    if (!await rec.hasPermission()) { say(context, 'لا يوجد إذن للميكروفون.'); return; }
    final d = await getTemporaryDirectory();
    await rec.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 48000, numChannels: 1),
        path: '${d.path}/sample_${DateTime.now().millisecondsSinceEpoch}.wav');
    setState(() => recording = true);
  }

  Future<void> pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['wav', 'mp3', 'm4a']);
    if (r?.files.single.path != null) setState(() => sample = File(r!.files.single.path!));
  }

  Future<void> create() async {
    if (name.text.trim().isEmpty) { say(context, 'اكتب اسمًا للصوت أولًا.'); return; }
    setState(() => busy = true);
    try {
      final id = await engine.createVoice(sample: sample!, name: name.text.trim());
      final v = await Store.load();
      v.add(VoiceItem(id, name.text.trim(), DateTime.now().toString().substring(0, 10)));
      await Store.save(v);
      if (mounted) { say(context, 'تم إنشاء الصوت.'); Navigator.pop(context); }
    } on VoiceEngineException catch (e) {
      if (mounted) say(context, e.userMessage);
    } catch (_) {
      if (mounted) say(context, 'حدث خطأ أثناء معالجة الصوت، يرجى المحاولة مرة أخرى.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final ok = own && agree;
    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء صوت جديد')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        CheckboxListTile(value: own, onChanged: (v) => setState(() => own = v!),
            title: const Text('أؤكد أن هذا الصوت صوتي، أو أن لدي إذنًا كتابيًا من صاحبه.')),
        CheckboxListTile(value: agree, onChanged: (v) => setState(() => agree = v!),
            title: const Text('أوافق على معالجة التسجيل لإنشاء نموذج خاص بي دون مشاركته.')),
        const Text('لا يُسمح بانتحال شخصية أي شخص دون إذنه.'),
        if (ok) ...[
          const SizedBox(height: 16),
          OutlinedButton(onPressed: toggleRec, child: Text(recording ? 'إيقاف التسجيل' : 'بدء التسجيل')),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: pick, child: const Text('رفع ملف صوتي (WAV / MP3 / M4A)')),
          if (sample != null) Semantics(liveRegion: true, child: Padding(padding: const EdgeInsets.all(12),
              child: Text('العينة جاهزة: ${sample!.path.split('/').last}', style: const TextStyle(fontWeight: FontWeight.w600)))),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الصوت')),
          const SizedBox(height: 16),
          FilledButton(onPressed: (sample == null || busy) ? null : create,
              child: Text(busy ? 'جارٍ الإنشاء…' : 'إنشاء النموذج الصوتي')),
        ],
      ]),
    );
  }
}

class Voices extends StatefulWidget {
  const Voices({super.key});
  @override
  State<Voices> createState() => _VoicesState();
}

class _VoicesState extends State<Voices> {
  List<VoiceItem> v = [];
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async { final l = await Store.load(); setState(() => v = l); }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('أصواتي')),
        body: v.isEmpty
            ? const Center(child: Text('لا توجد أصوات محفوظة بعد.', style: TextStyle(fontSize: 20)))
            : ListView(padding: const EdgeInsets.all(16), children: [
                for (final x in v)
                  Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(x.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    Text('تاريخ الإنشاء: ${x.date}'),
                    Row(children: [
                      TextButton(
                          onPressed: () async {
                            final t = TextEditingController(text: x.name);
                            final n = await showDialog<String>(context: c, builder: (_) => AlertDialog(
                                title: const Text('تعديل الاسم'), content: TextField(controller: t),
                                actions: [TextButton(onPressed: () => Navigator.pop(c, t.text), child: const Text('حفظ'))]));
                            if (n != null && n.trim().isNotEmpty) { x.name = n.trim(); await Store.save(v); load(); }
                          },
                          child: Text('تعديل اسم الصوت ${x.name}')),
                      TextButton(
                          onPressed: () async {
                            final yes = await showDialog<bool>(context: c, builder: (_) => AlertDialog(
                                title: Text('حذف ${x.name} نهائيًا؟'), content: const Text('لا يمكن التراجع.'),
                                actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف'))]));
                            if (yes == true) {
                              try { await engine.deleteVoice(x.id); } catch (_) {}
                              v.remove(x); await Store.save(v); load();
                            }
                          },
                          child: Text('حذف الصوت ${x.name}')),
                    ]),
                  ]))),
              ]),
      );
}

class Tts extends StatefulWidget {
  const Tts({super.key});
  @override
  State<Tts> createState() => _TtsState();
}

class _TtsState extends State<Tts> {
  List<VoiceItem> v = [];
  VoiceItem? sel;
  String lang = 'ar-IQ', fmt = 'wav';
  final text = TextEditingController();
  final player = AudioPlayer();
  File? out;
  bool busy = false;
  @override
  void initState() { super.initState(); Store.load().then((l) => setState(() { v = l; if (l.isNotEmpty) sel = l.first; })); }
  @override
  void dispose() { player.dispose(); super.dispose(); }

  Future<void> gen() async {
    if (sel == null || text.text.trim().isEmpty) { say(context, 'اختر صوتًا واكتب النص أولًا.'); return; }
    setState(() => busy = true);
    try {
      final f = await engine.synthesize(voiceId: sel!.id, text: text.text, language: lang, format: fmt);
      await player.setFilePath(f.path);
      setState(() => out = f);
      if (mounted) say(context, 'تم إنشاء الملف الصوتي.');
    } on VoiceEngineException catch (e) {
      if (mounted) say(context, e.userMessage);
    } catch (_) {
      if (mounted) say(context, 'حدث خطأ أثناء معالجة الصوت، يرجى المحاولة مرة أخرى.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('تحويل النص إلى كلام')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          DropdownButtonFormField<VoiceItem>(value: sel, decoration: const InputDecoration(labelText: 'الصوت'),
              items: [for (final x in v) DropdownMenuItem(value: x, child: Text(x.name))], onChanged: (x) => setState(() => sel = x)),
          DropdownButtonFormField<String>(value: lang, decoration: const InputDecoration(labelText: 'اللغة'),
              items: const [
                DropdownMenuItem(value: 'ar-IQ', child: Text('العربية (لهجة عراقية)')),
                DropdownMenuItem(value: 'ar', child: Text('العربية الفصحى')),
                DropdownMenuItem(value: 'ckb', child: Text('الكردية السورانية')),
                DropdownMenuItem(value: 'en', child: Text('English'))],
              onChanged: (x) => setState(() => lang = x!)),
          DropdownButtonFormField<String>(value: fmt, decoration: const InputDecoration(labelText: 'صيغة التصدير'),
              items: const [DropdownMenuItem(value: 'wav', child: Text('WAV')), DropdownMenuItem(value: 'mp3', child: Text('MP3'))],
              onChanged: (x) => setState(() => fmt = x!)),
          TextField(controller: text, minLines: 5, maxLines: 10, decoration: const InputDecoration(labelText: 'النص')),
          const SizedBox(height: 16),
          FilledButton(onPressed: busy ? null : gen, child: Text(busy ? 'جارٍ الإنشاء…' : 'إنشاء الملف الصوتي')),
          if (out != null) ...[
            const SizedBox(height: 16),
            StreamBuilder<PlayerState>(stream: player.playerStateStream, builder: (_, s) {
              final p = s.data?.playing ?? false;
              return OutlinedButton(onPressed: () => p ? player.pause() : player.play(), child: Text(p ? 'إيقاف مؤقت' : 'تشغيل'));
            }),
            StreamBuilder<Duration>(stream: player.positionStream, builder: (_, s) {
              final d = player.duration?.inMilliseconds ?? 1;
              final pos = (s.data?.inMilliseconds ?? 0).clamp(0, d).toDouble();
              return Slider(value: pos, max: d.toDouble(), label: 'موضع التشغيل',
                  semanticFormatterCallback: (x) => '${(x / d * 100).round()} بالمئة',
                  onChanged: (x) => player.seek(Duration(milliseconds: x.round())));
            }),
            OutlinedButton(onPressed: gen, child: const Text('إعادة التوليد')),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => Share.shareXFiles([XFile(out!.path)]), child: const Text('حفظ ومشاركة الملف')),
          ],
        ]),
      );
}

class Files extends StatelessWidget {
  const Files({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
      appBar: AppBar(title: const Text('الملفات')),
      body: const Center(child: Text('لا توجد ملفات مُنشأة بعد.', style: TextStyle(fontSize: 20))));
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('الإعدادات')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('تُشفّر الملفات أثناء النقل ولا تُشارك النماذج مع أي مستخدم.'),
          const SizedBox(height: 16),
          OutlinedButton(
              onPressed: () async {
                final yes = await showDialog<bool>(context: c, builder: (_) => AlertDialog(
                    title: const Text('حذف كل الأصوات نهائيًا؟'), content: const Text('لا يمكن التراجع.'),
                    actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف'))]));
                if (yes == true) {
                  for (final v in await Store.load()) { try { await engine.deleteVoice(v.id); } catch (_) {} }
                  await Store.save([]);
                  if (c.mounted) say(c, 'تم الحذف.');
                }
              },
              child: const Text('حذف كل التسجيلات والنماذج نهائيًا')),
        ]),
      );
}