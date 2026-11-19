import 'package:flutter/material.dart';

class HorizontalPreviewList extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) builder;

  const HorizontalPreviewList({
    super.key,
    required this.itemCount,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ v1.7.1 WEB: en pantallas anchas las cards crecen (176px de alto)
    // — la altura del listado se adapta para no recortarlas.
    final isWide = MediaQuery.of(context).size.width > 700;
    return SizedBox(
      height: isWide ? 188 : 164,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: builder,
      ),
    );
  }
}
