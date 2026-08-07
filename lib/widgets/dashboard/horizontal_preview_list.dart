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
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: builder,
      ),
    );
  }
}
