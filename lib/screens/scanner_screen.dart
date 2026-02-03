import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: false,
  );

  // --- COLOR SCHEME (Royal Navy) ---
  final Color primaryColor = const Color(0xFF2B3A67);

  @override
  Widget build(BuildContext context) {
    // 1. Adjusted Scan Window Size
    final double scanWindowWidth = MediaQuery.of(context).size.width * 0.8;
    final double scanWindowHeight = 120;

    final double centerX = MediaQuery.of(context).size.width / 2;
    final double centerY = MediaQuery.of(context).size.height / 2;

    final Rect scanWindow = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: scanWindowWidth,
      height: scanWindowHeight,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Align Barcode in Box", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: primaryColor, // Royal Navy
        centerTitle: true,
        elevation: 4,
        iconTheme: const IconThemeData(color: Colors.white),
        // --- CURVED BOTTOM SHAPE ---
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        // ---------------------------
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            scanWindow: scanWindow,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  controller.stop();
                  Navigator.pop(context, barcode.rawValue);
                  break;
                }
              }
            },
          ),

          // 2. Overlay (Darkens background)
          CustomPaint(
            painter: ScannerOverlay(scanWindow: scanWindow),
            child: Container(),
          ),

          // 3. Green Border (Visual Guide)
          Positioned(
            left: (MediaQuery.of(context).size.width - scanWindowWidth) / 2,
            top: (MediaQuery.of(context).size.height - scanWindowHeight) / 2,
            child: Container(
              width: scanWindowWidth,
              height: scanWindowHeight,
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 3),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 10, spreadRadius: 2)
                  ]
              ),
            ),
          ),

          // 4. Flashlight Button
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(50.0),
              child: ValueListenableBuilder(
                valueListenable: controller,
                builder: (context, state, child) {
                  bool isTorchOn = state.torchState == TorchState.on;
                  return IconButton(
                    color: Colors.white,
                    icon: Icon(isTorchOn ? Icons.flash_on : Icons.flash_off, size: 40, color: isTorchOn ? Colors.yellow : Colors.white),
                    onPressed: () => controller.toggleTorch(),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScannerOverlay extends CustomPainter {
  final Rect scanWindow;
  ScannerOverlay({required this.scanWindow});

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()..addRRect(RRect.fromRectAndRadius(scanWindow, const Radius.circular(12)));

    final backgroundWithCutout = Path.combine(
      PathOperation.difference,
      backgroundPath,
      cutoutPath,
    );

    canvas.drawPath(backgroundWithCutout, Paint()..color = Colors.black.withOpacity(0.6)); // 60% opacity
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}