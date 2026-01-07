import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

/// Jogeset szekció widgetek
///
/// Újrahasználható szekció widgetek a jogeset megjelenítéshez:
/// - Normál szekció
/// - Kiemelt (highlighted) szekció
/// - Mobil oldal
/// - Mobil kiemelt oldal
class JogesetSectionWidgets {
  /// Normál szekció (desktop/tablet)
  static Widget buildSection({
    required String title,
    required String content,
    required bool isMobile,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: isMobile ? 12.0 : 18.0,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF202122),
          ),
        ),
        const SizedBox(height: 8),
        Html(
          data:
              '<div style="text-align: justify;">${_escapeHtml(content)}</div>',
          style: {
            "div": Style(
              fontSize: FontSize(isMobile ? 10.5 : 16.0),
              color: const Color(0xFF444444),
              lineHeight: const LineHeight(1.6),
              padding: HtmlPaddings.zero,
              margin: Margins.zero,
            ),
          },
        ),
      ],
    );
  }

  /// Kiemelt szekció (desktop/tablet)
  static Widget buildHighlightedSection({
    required String title,
    required String content,
    required Color color,
    required Color borderColor,
    required bool isMobile,
  }) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16.0 : 20.0),
      decoration: BoxDecoration(
        color: color,
        border: isMobile ? null : Border.all(color: borderColor, width: 2.0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: isMobile ? 12.0 : 18.0,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF202122),
            ),
          ),
          const SizedBox(height: 8),
          Html(
            data:
                '<div style="text-align: justify;">${_escapeHtml(content)}</div>',
            style: {
              "div": Style(
                fontSize: FontSize(isMobile ? 10.5 : 16.0),
                color: const Color(0xFF444444),
                lineHeight: const LineHeight(1.6),
                padding: HtmlPaddings.zero,
                margin: Margins.zero,
              ),
            },
          ),
        ],
      ),
    );
  }

  /// Mobil oldal widget (swipe-olható lapok számára)
  static Widget buildMobilePage({
    required String title,
    required String content,
    required bool isMobile,
    bool isItalic = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF202122),
          ),
        ),
        const SizedBox(height: 8),
        Html(
          data:
              '<div style="text-align: justify;">${_escapeHtml(content)}</div>',
          style: {
            "div": Style(
              fontSize: FontSize(10.5),
              color: const Color(0xFF444444),
              lineHeight: const LineHeight(1.6),
              padding: HtmlPaddings.zero,
              margin: Margins.zero,
              fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
            ),
          },
        ),
      ],
    );
  }

  /// Mobil kiemelt oldal widget
  static Widget buildMobilePageHighlighted({
    required String title,
    required String content,
    required Color color,
    required Color borderColor,
    required bool isMobile,
  }) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: color,
        border: isMobile ? null : Border.all(color: borderColor, width: 2.0),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12.0,
              fontWeight: FontWeight.w600,
              color: Color(0xFF202122),
            ),
          ),
          const SizedBox(height: 8),
          Html(
            data:
                '<div style="text-align: justify;">${_escapeHtml(content)}</div>',
            style: {
              "div": Style(
                fontSize: FontSize(10.0),
                color: const Color(0xFF444444),
                lineHeight: const LineHeight(1.6),
                padding: HtmlPaddings.zero,
                margin: Margins.zero,
              ),
            },
          ),
        ],
      ),
    );
  }

  /// HTML escape helper
  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}
