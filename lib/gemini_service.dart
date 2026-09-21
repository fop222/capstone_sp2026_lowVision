import 'dart:convert';
import 'package:http/http.dart' as http;

// Make sure your API key is inserted here
const String _apiKey = 'YOUR_API_KEY_HERE';

Future<List<Map<String, dynamic>>> generateRecipeSuggestions(
    List<String> ingredients) async {
  if (ingredients.isEmpty) return [];

  final url = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=$_apiKey',
  );

  final promptText = '''
You are a creative chef. Given these available ingredients: ${ingredients.join(', ')}.
Suggest 2 to 3 practical recipes that can be made using these items.

Return ONLY a raw JSON array of objects with no markdown formatting or code blocks.
Each object must have:
- "title": string
- "description": string
- "ingredients": list of strings
- "instructions": list of strings
''';

  final requestBody = jsonEncode({
    "contents": [
      {
        "role": "user",
        "parts": [
          {"text": promptText}
        ]
      }
    ],
    "generationConfig": {
      "temperature": 0.7,
      "responseMimeType": "application/json"
    }
  });

  try {
    print('[Gemini] Requesting gemini-3.6-flash...');
    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: requestBody,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      print('[Gemini] HTTP ${response.statusCode}: ${response.body}');
      return [];
    }

    final data = jsonDecode(response.body);
    final textContent =
        data['candidates']?[0]?['content']?['parts']?[0]?['text'];

    if (textContent == null) {
      print('[Gemini] Empty response text received.');
      return [];
    }

    // Parse the JSON array returned by Gemini
    final List<dynamic> jsonList = jsonDecode(textContent);
    return jsonList.cast<Map<String, dynamic>>();
  } catch (e) {
    print('[Gemini] Exception during API call: $e');
    return [];
  }
}