import 'package:fast_log/fast_log.dart' as fast_log;

export 'package:fast_log/fast_log.dart' show error, info, success, verbose;

void warning(String message) => fast_log.warn(message);
