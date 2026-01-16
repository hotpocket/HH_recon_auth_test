import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class ScanApp extends StatefulWidget {
  const ScanApp({super.key});
  @override
  State<ScanApp> createState() => _ScanAppState();
}

class _ScanAppState extends State<ScanApp> {
  final List<ScanResult> _devices = [];
  bool _isScanning = false;
  String _status = 'Initializing Bluetooth...';
  bool _bluetoothEnabled = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _status = 'Requesting permissions...';
    });

    // Request Bluetooth permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    // Check if all permissions are granted
    bool allGranted = true;
    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        allGranted = false;
      }
    });

    if (allGranted) {
      _initializeBluetooth();
    } else {
      setState(() {
        _status =
            'Permissions denied. Please grant Bluetooth and Location permissions in Settings.';
      });
    }
  }

  Future<void> _initializeBluetooth() async {
    // Check current Bluetooth state
    var state = await FlutterBluePlus.adapterState.first;
    _updateBluetoothState(state);

    // Listen to Bluetooth state changes
    FlutterBluePlus.adapterState.listen((state) {
      if (mounted) {
        _updateBluetoothState(state);
      }
    });
  }

  void _updateBluetoothState(BluetoothAdapterState state) {
    setState(() {
      _bluetoothEnabled = state == BluetoothAdapterState.on;
      if (_bluetoothEnabled) {
        _status = 'Bluetooth enabled. Starting scan...';
        _startScan();
      } else {
        _status = 'Bluetooth is disabled. Please enable Bluetooth in Settings.';
        _isScanning = false;
      }
    });
  }

  void _startScan() {
    if (!_bluetoothEnabled) {
      return;
    }

    setState(() {
      _isScanning = true;
      _status = 'Scanning for devices...';
    });

    // Clear previous devices
    _devices.clear();

    // Start scanning
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    // Listen to scan results
    FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          _devices.clear();
          _devices.addAll(results);
          if (results.isNotEmpty) {
            _status = 'Found ${results.length} device(s)';
          }
        });
      }
    });

    // Listen to scanning state
    FlutterBluePlus.isScanning.listen((isScanning) {
      if (mounted) {
        setState(() {
          _isScanning = isScanning;
          if (!isScanning && _devices.isEmpty) {
            _status =
                'No devices found. Make sure Bluetooth is enabled and devices are in range.';
          } else if (!isScanning && _devices.isNotEmpty) {
            _status = 'Scan completed. Found ${_devices.length} device(s).';
          }
        });
      }
    });
  }

  void _refreshScan() {
    if (!_isScanning && _bluetoothEnabled) {
      _startScan();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Scanner'),
        actions: [
          if (_bluetoothEnabled)
            IconButton(
              icon: Icon(_isScanning ? Icons.stop : Icons.refresh),
              onPressed: _refreshScan,
            ),
        ],
      ),
      body: _bluetoothEnabled
          ? _devices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.bluetooth_searching,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        _status,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      if (_isScanning) ...[
                        const SizedBox(height: 16),
                        const CircularProgressIndicator(),
                      ],
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    _refreshScan();
                    await Future.delayed(const Duration(seconds: 10));
                  },
                  child: ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (ctx, i) {
                      final d = _devices[i].device;
                      final rssi = _devices[i].rssi;
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: ListTile(
                          leading: const Icon(Icons.bluetooth),
                          title: Text(
                            d.platformName.isNotEmpty
                                ? d.platformName
                                : 'Unknown Device',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ID: ${d.remoteId.toString()}'),
                              Text('RSSI: $rssi dBm'),
                            ],
                          ),
                          trailing: Text(
                            '$rssi dBm',
                            style: TextStyle(
                              color: rssi > -50
                                  ? Colors.green
                                  : rssi > -70
                                      ? Colors.orange
                                      : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.bluetooth_disabled,
                        size: 64, color: Colors.orange),
                    const SizedBox(height: 16),
                    Text(
                      _status,
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        // Try to enable Bluetooth
                        FlutterBluePlus.turnOn();
                      },
                      child: const Text('Enable Bluetooth'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
