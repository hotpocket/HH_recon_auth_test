import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'auth_screen.dart';
import 'bluetooth_test.dart';

class LauncherScreen extends StatelessWidget {
  const LauncherScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Launcher'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.rocket_launch,
                  size: 80,
                  color: Colors.blue,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Choose a Test',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Select which test you would like to run',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AuthScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.security),
                    label: const Text(
                      'Authentication Test',
                      style: TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // Check if running on a native platform (iOS, Android, Linux, macOS, Windows)
                      try {
                        // Platform.isXxx throws on web, so we use it to detect native platforms
                        if (Platform.isAndroid ||
                            Platform.isIOS ||
                            Platform.isLinux ||
                            Platform.isMacOS ||
                            Platform.isWindows) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ScanApp(),
                            ),
                          );
                        } else {
                          // Should not reach here, but fallback to dialog
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title:
                                    const Text('Bluetooth Test Not Available'),
                                content: const Text(
                                  'The Bluetooth test only works in a native environment (Linux, Android, iOS, Mac, Windows). '
                                  'Please run this app natively to test Bluetooth functionality.',
                                ),
                                actions: <Widget>[
                                  TextButton(
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                    },
                                    child: const Text('OK'),
                                  ),
                                ],
                              );
                            },
                          );
                        }
                      } catch (e) {
                        // Platform throws on web, so we show the dialog
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: const Text('Bluetooth Test Not Available'),
                              content: const Text(
                                'The Bluetooth test only works in a native environment (Linux, Android, iOS, Mac, Windows). '
                                'Please run this app natively to test Bluetooth functionality.',
                              ),
                              actions: <Widget>[
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                  child: const Text('OK'),
                                ),
                              ],
                            );
                          },
                        );
                      }
                    },
                    icon: const Icon(Icons.bluetooth),
                    label: const Text(
                      'Bluetooth Test',
                      style: TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
