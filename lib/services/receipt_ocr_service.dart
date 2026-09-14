import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRBox {
  final String text;
  final Rect rect;

  OCRBox({required this.text, required this.rect});

  double get yCenter => rect.top + rect.height / 2.0;
}

class ReceiptOcrService {
  static final _textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);

  static Future<List<OCRBox>> recognizeImage(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

    List<OCRBox> boxes = [];
    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        boxes.add(OCRBox(
          text: line.text,
          rect: line.boundingBox,
        ));
      }
    }
    return boxes;
  }

  static String alignBoxesToText(List<OCRBox> boxes, {double yThresholdRatio = 0.5}) {
    if (boxes.isEmpty) return '';

    boxes.sort((a, b) => a.rect.top.compareTo(b.rect.top));

    List<List<OCRBox>> lines = [];
    for (var box in boxes) {
      bool assigned = false;
      for (var line in lines) {
        var ref = line.first;
        double threshold = ref.rect.height * yThresholdRatio;
        if ((box.yCenter - ref.yCenter).abs() <= threshold) {
          line.add(box);
          assigned = true;
          break;
        }
      }
      if (!assigned) {
        lines.add([box]);
      }
    }

    List<String> textLines = [];
    for (var line in lines) {
      line.sort((a, b) => a.rect.left.compareTo(b.rect.left));
      String rowText = line.map((b) => b.text.trim()).where((t) => t.isNotEmpty).join('  ');
      if (rowText.isNotEmpty) {
        textLines.add(rowText);
      }
    }
    return textLines.join('\n');
  }

  static void dispose() {
    _textRecognizer.close();
  }
}
