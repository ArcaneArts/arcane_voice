import 'package:artifact/artifact.dart';

@artifact
class RealtimeTurnDetectionConfig {
  final int speechThresholdRms;
  final int speechStartMs;
  final int speechEndSilenceMs;
  final int preSpeechMs;
  final bool bargeInEnabled;

  const RealtimeTurnDetectionConfig({
    this.speechThresholdRms = 100,
    this.speechStartMs = 200,
    this.speechEndSilenceMs = 900,
    this.preSpeechMs = 300,
    this.bargeInEnabled = true,
  });
}
