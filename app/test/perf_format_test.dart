import 'package:flutter_test/flutter_test.dart';
import 'package:velksync/ui/perf.dart';

void main() {
  test('nome do processador sem sufixos redundantes', () {
    expect(shortCpuName('AMD Ryzen 7 5700X 8-Core Processor'), 'AMD Ryzen 7 5700X');
    expect(shortCpuName('Intel(R) Core(TM) i7-9700K CPU @ 3.60GHz'), 'Intel Core i7-9700K');
    expect(shortCpuName('AMD Ryzen 9 7950X3D 16-Core Processor'), 'AMD Ryzen 9 7950X3D');
    expect(shortCpuName('Apple M2'), 'Apple M2');
  });

  test('formatação de bytes e tempo ligado', () {
    expect(formatBytes(1745059840), '1.6 GB');
    expect(formatBytes(510940672000), '476 GB');
    expect(formatUptime(const Duration(seconds: 6016)), '1 h 40 min');
    expect(formatUptime(const Duration(days: 2, hours: 7)), '2 d 7 h');
  });
}
