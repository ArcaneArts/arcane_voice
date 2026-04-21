import 'package:arcane_voice/arcane_voice.dart';
import 'package:flutter/material.dart';

class ArcanaCallScreen extends StatefulWidget {
  final CallSessionController? controller;

  const ArcanaCallScreen({super.key, this.controller});

  @override
  State<ArcanaCallScreen> createState() => _ArcanaCallScreenState();
}

class _ArcanaCallScreenState extends State<ArcanaCallScreen> {
  late final CallSessionController controller;

  @override
  void initState() {
    controller = widget.controller ?? CallSessionController();
    super.initState();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text("Arcana Voice Proxy")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            CallStatusCard(controller: controller),
            const SizedBox(height: 16),
            Expanded(child: TranscriptPanel(controller: controller)),
          ],
        ),
      ),
      floatingActionButton: CallActionDock(controller: controller),
    ),
  );
}

class CallStatusCard extends StatelessWidget {
  final CallSessionController controller;

  const CallStatusCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            controller.sessionState.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          SelectableText(
            controller.serverUrl,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          ProviderSelector(controller: controller),
          if (controller.provider == RealtimeProviderCatalog.elevenLabsId) ...<
            Widget
          >[
            const SizedBox(height: 12),
            ElevenLabsAgentIdField(controller: controller),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              Chip(label: Text("Provider: ${controller.provider}")),
              Chip(label: Text("Model: ${controller.model}")),
              Chip(label: Text(controller.muted ? "Muted" : "Mic live")),
            ],
          ),
          const SizedBox(height: 12),
          VoiceSelector(controller: controller),
          if (controller.lastError.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              controller.lastError,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
  );
}

class TranscriptPanel extends StatelessWidget {
  final CallSessionController controller;

  const TranscriptPanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    List<TranscriptEntry> entries = controller.transcriptEntries
        .where((entry) => entry.text.isNotEmpty || !entry.pending)
        .toList();
    if (entries.isEmpty) {
      return Card(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              "Start a call to stream microphone audio to the proxy server and hear provider audio streamed back.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }

    return Card(
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: entries.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) =>
            TranscriptEntryTile(entry: entries[index]),
      ),
    );
  }
}

class TranscriptEntryTile extends StatelessWidget {
  final TranscriptEntry entry;

  const TranscriptEntryTile({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    Color labelColor = switch (entry.speaker) {
      TranscriptSpeaker.user => const Color(0xFF7DD3FC),
      TranscriptSpeaker.assistant => const Color(0xFFFCD34D),
      TranscriptSpeaker.system => const Color(0xFFA7F3D0),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                entry.speaker.label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: labelColor),
              ),
              if (entry.pending) ...<Widget>[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(entry.text),
        ],
      ),
    );
  }
}

class ProviderSelector extends StatelessWidget {
  final CallSessionController controller;

  const ProviderSelector({super.key, required this.controller});

  @override
  Widget build(BuildContext context) =>
      SegmentedButton<RealtimeProviderDefinition>(
    segments: <ButtonSegment<RealtimeProviderDefinition>>[
      for (RealtimeProviderDefinition provider in RealtimeProviderCatalog.all)
        ButtonSegment<RealtimeProviderDefinition>(
          value: provider,
          label: Text(provider.label),
        ),
    ],
    selected: <RealtimeProviderDefinition>{controller.providerOption},
    onSelectionChanged: controller.callActive || controller.connecting
        ? null
        : (selection) {
            if (selection.isEmpty) return;
            controller.onProviderChanged(selection.first);
          },
  );
}

class VoiceSelector extends StatelessWidget {
  final CallSessionController controller;

  const VoiceSelector({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (controller.provider == RealtimeProviderCatalog.elevenLabsId) {
      return const SizedBox.shrink();
    }

    return DropdownButtonFormField<String>(
      key: ValueKey<String>("${controller.provider}-${controller.voice}"),
      initialValue: controller.voice,
      decoration: const InputDecoration(
        labelText: "Voice",
        border: OutlineInputBorder(),
      ),
      items: <DropdownMenuItem<String>>[
        for (String voice in controller.availableVoices)
          DropdownMenuItem<String>(value: voice, child: Text(voice)),
      ],
      onChanged: controller.callActive || controller.connecting
          ? null
          : (selectedVoice) {
              if (selectedVoice == null) return;
              controller.onVoiceChanged(selectedVoice);
            },
    );
  }
}

class ElevenLabsAgentIdField extends StatelessWidget {
  final CallSessionController controller;

  const ElevenLabsAgentIdField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey<String>(
      "elevenlabs-agent-${controller.provider}-${controller.elevenLabsAgentId}",
    ),
    initialValue: controller.elevenLabsAgentId,
    enabled: !controller.callActive && !controller.connecting,
    decoration: const InputDecoration(
      labelText: "ElevenLabs Agent ID",
      hintText: "agent_...",
      border: OutlineInputBorder(),
    ),
    onChanged: controller.onElevenLabsAgentIdChanged,
  );
}

class CallActionDock extends StatelessWidget {
  final CallSessionController controller;

  const CallActionDock({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      FloatingActionButton.small(
        heroTag: "mute",
        onPressed: controller.callActive ? controller.onMutePressed : null,
        child: Icon(controller.muted ? Icons.mic_off : Icons.mic),
      ),
      const SizedBox(width: 12),
      FloatingActionButton.extended(
        heroTag: "call",
        onPressed: controller.onPrimaryActionPressed,
        icon: Icon(controller.canStart ? Icons.call : Icons.call_end),
        label: Text(controller.canStart ? "Start" : "Stop"),
      ),
    ],
  );
}
