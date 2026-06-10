import 'package:cycle/core/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatBytes scales to a sensible unit', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(27 * 1024 * 1024), '27 MB');
    expect(formatBytes(806010913), '769 MB'); // ~Switzerland
    expect(formatBytes(1213366043), '1.1 GB'); // ~Austria, one decimal for GB
    expect(formatBytes(2918998898), '2.7 GB'); // ~Alps
  });
}
