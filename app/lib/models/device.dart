class Device {
  final String id;
  final String name;
  final String host;
  final int port;
  final String token;
  final String mac;
  final String broadcast;

  const Device({
    required this.id,
    required this.name,
    required this.host,
    this.port = 41100,
    required this.token,
    this.mac = '',
    this.broadcast = '255.255.255.255',
  });

  Device copyWith({String? name, String? host, int? port, String? token, String? mac, String? broadcast}) => Device(
    id: id,
    name: name ?? this.name,
    host: host ?? this.host,
    port: port ?? this.port,
    token: token ?? this.token,
    mac: mac ?? this.mac,
    broadcast: broadcast ?? this.broadcast,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'token': token,
    'mac': mac,
    'broadcast': broadcast,
  };

  factory Device.fromJson(Map<String, dynamic> j) => Device(
    id: j['id'] as String,
    name: j['name'] as String,
    host: j['host'] as String,
    port: j['port'] as int? ?? 41100,
    token: j['token'] as String,
    mac: j['mac'] as String? ?? '',
    broadcast: j['broadcast'] as String? ?? '255.255.255.255',
  );
}

class AgentInfo {
  final String name;
  final String hostname;
  final String os;
  final String mac;
  final bool allowShell;

  AgentInfo.fromJson(Map<String, dynamic> j)
    : name = j['name'] as String? ?? '',
      hostname = j['hostname'] as String? ?? '',
      os = j['os'] as String? ?? '',
      mac = j['mac'] as String? ?? '',
      allowShell = j['allow_shell'] as bool? ?? false;

  String get osLabel => switch (os) {
    'windows' => 'Windows',
    'linux' => 'Linux',
    _ => os,
  };
}

class PresetCommand {
  final String id;
  final String name;

  PresetCommand.fromJson(Map<String, dynamic> j) : id = j['id'] as String, name = j['name'] as String;
}

class RunResult {
  final int exitCode;
  final String output;
  final int durationMs;
  final bool timedOut;

  RunResult.fromJson(Map<String, dynamic> j)
    : exitCode = j['exit_code'] as int? ?? -1,
      output = j['output'] as String? ?? '',
      durationMs = j['duration_ms'] as int? ?? 0,
      timedOut = j['timed_out'] as bool? ?? false;

  bool get ok => exitCode == 0 && !timedOut;
}

/// Something the PC asked the phone to do (sent with `velksync-agent send`).
class PcEvent {
  final String type;
  final String text;
  final String url;

  PcEvent.fromJson(Map<String, dynamic> j)
    : type = j['type'] as String? ?? '',
      text = j['text'] as String? ?? '',
      url = j['url'] as String? ?? '';
}
