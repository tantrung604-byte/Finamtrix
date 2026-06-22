import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class OllamaService {
  static final OllamaService instance = OllamaService._init();
  OllamaService._init();

  // Default local Ollama URL
  static const String _defaultBaseUrl = 'http://localhost:11434/api';
  static const String _defaultModel = 'llama3.2:1b';

  Future<String?> generateLocalResponse(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('ollama_base_url') ?? _defaultBaseUrl;
    final model = prefs.getString('ollama_model') ?? _defaultModel;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': model,
          'prompt': prompt,
          'stream': false,
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['response'] as String;
      } else {
        print('Ollama Error: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Ollama Exception: $e');
      return null;
    }
  }

  /// Streams the response for a better UI experience
  Stream<String> streamLocalResponse(String prompt) async* {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('ollama_base_url') ?? _defaultBaseUrl;
    final model = prefs.getString('ollama_model') ?? _defaultModel;

    try {
      final request = http.Request('POST', Uri.parse('$baseUrl/generate'))
        ..body = jsonEncode({
          'model': model,
          'prompt': prompt,
          'stream': true,
        });

      final response = await http.Client().send(request);

      if (response.statusCode == 200) {
        await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
          if (line.trim().isEmpty) continue;
          final json = jsonDecode(line);
          final chunk = json['response'] as String;
          yield chunk;
          if (json['done'] == true) break;
        }
      }
    } catch (e) {
      print('Ollama Stream Exception: $e');
    }
  }
}
