import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() => runApp(const ScanApp());

class ScanApp extends StatefulWidget {
  const ScanApp({super.key});
  @override
  State<ScanApp> createState() => _ScanAppState();
}

class _ScanAppState extends State<ScanApp> {
  final List<ScanResult> _devices = [];

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  void _startScan() {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    FlutterBluePlus.scanResults.listen((results) {
      setState(() => _devices.addAll(results));
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('BLE Scanner')),
        body: ListView.builder(
          itemCount: _devices.length,
          itemBuilder: (ctx, i) {
            final d = _devices[i].device;
            return ListTile(
              title: Text(d.platformName.isEmpty ? 'Unknown' : d.platformName),
              subtitle: Text(d.remoteId.toString()),
            );
          },
        ),
      ),
    );
  }
}
