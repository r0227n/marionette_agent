import 'package:marionette_agent/src/protocol/protocol.dart';

Request request(
  String command, {
  String session = 'a',
  Json params = const {},
  int ms = 2000,
}) => Request(
  requestId: 'test',
  session: session,
  command: command,
  params: command == 'screenshot'
      ? {'platform': 'android', 'device': 'test-pairing', ...params}
      : params,
  deadline: DateTime.now().add(Duration(milliseconds: ms)),
);
