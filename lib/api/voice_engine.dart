import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// واجهة المحرك: استبدل التنفيذ بأي مزوّد حقيقي دون تغيير الواجهة.
abstract class VoiceEngine {
  Future<String> createVoice({required File sample, required String name});
  Future<File> synthesize({required String voiceId, required String text, required String language, required String format});
  Future<void> deleteVoice(String voiceId);
}

class VoiceEngineException implements Exception {
  final String userMessage; // رسالة عربية واضحة للمستخدم
  VoiceEngineException(this.userMessage);
  @override
  String toString() => userMessage;
}

/// تنفيذ HTTP عام. ضع عنوان خادمك في --dart-define=API_BASE=https://...
/// الخادم يجب أن يربط مفاتيح المزوّد (لا تضع المفاتيح داخل التطبيق).
class HttpVoiceEngine implements VoiceEngine {
  static const base = String.fromEnvironment('API_BASE');
  void _check() {
    if (base.isEmpty) {
      throw VoiceEngineException('لم يتم ربط محرك الاستنساخ بعد. يرجى ضبط عنوان الخادم.');
    }
  }

  @override
  Future<String> createVoice({required File sample, required String name}) async {
    _check();
    final req = http.MultipartRequest('POST', Uri.parse('$base/v1/voices'))
      ..fields['name'] = name
      ..fields['consent'] = 'true'
      ..files.add(await http.MultipartFile.fromPath('sample', sample.path));
    final res = await http.Response.fromStream(await req.send());
    if (res.statusCode != 200) {
      throw VoiceEngineException('لم نتمكن من إنشاء النموذج الصوتي، حاول تسجيل عينة أطول.');
    }
    return jsonDecode(res.body)['voice_id'] as String;
  }

  @override
  Future<File> synthesize({required String voiceId, required String text, required String language, required String format}) async {
    _check();
    final res = await http.post(Uri.parse('$base/v1/tts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'voice_id': voiceId, 'text': text, 'language': language, 'format': format}));
    if (res.statusCode != 200) {
      throw VoiceEngineException('حدث خطأ أثناء معالجة الصوت، يرجى المحاولة مرة أخرى.');
    }
    final f = File('${Directory.systemTemp.path}/out_${DateTime.now().millisecondsSinceEpoch}.$format');
    await f.writeAsBytes(res.bodyBytes);
    return f;
  }

  @override
  Future<void> deleteVoice(String voiceId) async {
    _check();
    await http.delete(Uri.parse('$base/v1/voices/$voiceId'));
  }
}
