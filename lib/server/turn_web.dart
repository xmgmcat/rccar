import 'dart:convert';
import 'package:http/http.dart' as http;

Future<Map> getTurnCredential(String host) async {
  var url = 'https://$host/api/turn?service=turn&username=flutter-webrtc';
  final res = await http.get(Uri.parse(url));
  if (res.statusCode == 200) {
    var data = json.decode(res.body);
    print('getTurnCredential:response => $data.');
    return data;
  }
  return {};
}
