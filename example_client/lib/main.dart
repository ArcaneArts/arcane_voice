import 'package:arcane_voice/arcane_voice.dart';
import 'package:example_client/call_screen.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ArcanaApp());

Future<String> execSecretCodeClientTool() async => "yolo42";

class ArcanaApp extends StatefulWidget {
  const ArcanaApp({super.key});

  @override
  State<ArcanaApp> createState() => _ArcanaAppState();
}

class _ArcanaAppState extends State<ArcanaApp> {
  late CallSessionController controller;

  @override
  void initState() {
    ClientToolRegistry clientToolRegistry = ClientToolRegistry(
      tools: <ClientTool>[
        ClientTool.jsonSchema(
          name: "secretCode",
          description:
              "Return the secret access code for smoke testing client-side tool calling.",
          parameters: <String, Object?>{
            "type": "object",
            "properties": <String, Object?>{},
            "required": <String>[],
          },
          execute: (_) async => execSecretCodeClientTool(),
        ),
      ],
    );
    controller = CallSessionController(clientToolRegistry: clientToolRegistry);
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: "Arcana Voice Proxy",
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0E7490),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF081018),
      useMaterial3: true,
    ),
    home: ArcanaCallScreen(controller: controller),
  );
}
