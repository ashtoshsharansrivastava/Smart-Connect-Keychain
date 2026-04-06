import 'package:http/http.dart' as http;
import 'dart:convert';

class TelegramService {
  // This function takes the saved keys and fires the message
  static Future<bool> sendMessage({
    required String botToken,
    required String chatId,
    required String message,
  }) async {
    if (botToken.isEmpty || chatId.isEmpty) return false;

    final String url = 'https://api.telegram.org/bot$botToken/sendMessage';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'chat_id': chatId, 'text': message}),
      );

      if (response.statusCode == 200) {
        print("Success: Message sent to $chatId");
        return true;
      } else {
        print("Failed: ${response.body}");
        return false;
      }
    } catch (e) {
      print("Network Error: $e");
      return false;
    }
  }
}
