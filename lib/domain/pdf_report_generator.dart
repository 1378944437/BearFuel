import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';

/// PDF 审计报告生成与导出引擎
class PdfReportGenerator {
  /// 将高清晰度渲染图像封装为标准 A4 PDF 审计报告文档
  static Future<File> generatePdfFromImage({
    required Uint8List imageBytes,
    required String fileName,
    Directory? outputDirectory,
  }) async {
    final pdf = pw.Document(
      title: '车辆全寿命用车成本审计报告',
      author: 'BearFuel',
    );

    final image = pw.MemoryImage(imageBytes);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(12),
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Image(
              image,
              fit: pw.BoxFit.contain,
            ),
          );
        },
      ),
    );

    final dir = outputDirectory ?? await getTemporaryDirectory();
    final cleanFileName =
        fileName.endsWith('.pdf') ? fileName : '$fileName.pdf';
    final file = File('${dir.path}/$cleanFileName');
    await file.writeAsBytes(await pdf.save());
    return file;
  }
}
