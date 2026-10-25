class Device {
  final String id;
  final String name;
  final String host;
  final int port;
  final String mac;
  final String broadcast;

  /// Hash SHA-256 da chave pública do certificado do agente (vem do QR).
  final String pin;

  /// Credencial própria deste celular, revogável no PC. O token fica no
  /// armazenamento seguro, nunca no JSON das preferências.
  final String deviceId;
  final String token;

  const Device({
    required this.id,
    required this.name,
    required this.host,
    this.port = 41100,
    this.mac = '',
    this.broadcast = '255.255.255.255',
    this.pin = '',
    this.deviceId = '',
    this.token = '',
  });

  /// Sem pareamento só dá para ligar (Wake-on-LAN não precisa de credencial).
  bool get paired => pin.isNotEmpty && deviceId.isNotEmpty && token.isNotEmpty;

  String get shortPin => pin.length < 16
      ? pin
      : '${pin.substring(0, 4)} ${pin.substring(4, 8)} ${pin.substring(8, 12)} ${pin.substring(12, 16)}';

  Device copyWith({
    String? name,
    String? host,
    int? port,
    String? mac,
    String? broadcast,
    String? pin,
    String? deviceId,
    String? token,
  }) => Device(
    id: id,
    name: name ?? this.name,
    host: host ?? this.host,
    port: port ?? this.port,
    mac: mac ?? this.mac,
    broadcast: broadcast ?? this.broadcast,
    pin: pin ?? this.pin,
    deviceId: deviceId ?? this.deviceId,
    token: token ?? this.token,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'mac': mac,
    'broadcast': broadcast,
    'pin': pin,
    'device_id': deviceId,
  };

  factory Device.fromJson(Map<String, dynamic> j, {String token = ''}) => Device(
    id: j['id'] as String,
    name: j['name'] as String,
    host: j['host'] as String,
    port: j['port'] as int? ?? 41100,
    mac: j['mac'] as String? ?? '',
    broadcast: j['broadcast'] as String? ?? '255.255.255.255',
    pin: j['pin'] as String? ?? '',
    deviceId: j['device_id'] as String? ?? '',
    token: token,
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

/// Uso do PC (GET /api/stats). Campos nulos: o sistema não expõe (ex.:
/// temperaturas no Windows) e o medidor correspondente é escondido.
class PcStats {
  final String cpuName;
  final double cpuPercent;
  final int cpuThreads;
  final int memUsed, memTotal, diskUsed, diskTotal;
  final double? cpuTemp;
  final GpuStats? gpu;
  final Duration uptime;

  PcStats.fromJson(Map<String, dynamic> j)
    : cpuName = j['cpu_name'] as String? ?? '',
      cpuPercent = (j['cpu_percent'] as num? ?? 0).toDouble(),
      cpuThreads = j['cpu_threads'] as int? ?? 0,
      memUsed = j['mem_used'] as int? ?? 0,
      memTotal = j['mem_total'] as int? ?? 0,
      diskUsed = j['disk_used'] as int? ?? 0,
      diskTotal = j['disk_total'] as int? ?? 0,
      cpuTemp = (j['cpu_temp'] as num?)?.toDouble(),
      gpu = j['gpu'] == null ? null : GpuStats.fromJson(j['gpu'] as Map<String, dynamic>),
      uptime = Duration(seconds: j['uptime_seconds'] as int? ?? 0);

  double get memFraction => memTotal == 0 ? 0 : memUsed / memTotal;
  double get diskFraction => diskTotal == 0 ? 0 : diskUsed / diskTotal;
}

class GpuStats {
  final String name;
  final double percent;
  final int vramUsed, vramTotal;
  final double? temp;

  GpuStats.fromJson(Map<String, dynamic> j)
    : name = j['name'] as String? ?? 'GPU',
      percent = (j['percent'] as num? ?? 0).toDouble(),
      vramUsed = j['vram_used'] as int? ?? 0,
      vramTotal = j['vram_total'] as int? ?? 0,
      temp = (j['temp'] as num?)?.toDouble();

  double get vramFraction => vramTotal == 0 ? 0 : vramUsed / vramTotal;
}

/// O que está tocando no PC (GET /api/media).
class MediaState {
  final bool available;
  final String player, status, title, artist, album, artId;
  final int positionMs, durationMs;
  final bool canSeek, canControl;
  final double? volume;
  final bool? muted;

  MediaState.fromJson(Map<String, dynamic> j)
    : available = j['available'] as bool? ?? false,
      player = j['player'] as String? ?? '',
      status = j['status'] as String? ?? 'stopped',
      title = j['title'] as String? ?? '',
      artist = j['artist'] as String? ?? '',
      album = j['album'] as String? ?? '',
      artId = j['art_id'] as String? ?? '',
      positionMs = j['position_ms'] as int? ?? 0,
      durationMs = j['duration_ms'] as int? ?? 0,
      canSeek = j['can_seek'] as bool? ?? false,
      canControl = j['can_control'] as bool? ?? false,
      volume = (j['volume'] as num?)?.toDouble(),
      muted = j['muted'] as bool?;

  bool get playing => status == 'playing';
}
