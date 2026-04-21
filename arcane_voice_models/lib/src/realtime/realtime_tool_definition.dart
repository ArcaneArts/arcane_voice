import 'package:artifact/artifact.dart';

@artifact
class RealtimeToolDefinition {
  final String name;
  final String description;
  final String parametersJson;

  const RealtimeToolDefinition({
    required this.name,
    required this.description,
    required this.parametersJson,
  });
}
