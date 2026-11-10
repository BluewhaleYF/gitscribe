import 'package:flutter/material.dart';

import '../models.dart';

/// A small colored status badge (M/A/D/R/C/?) for a file change.
class ChangeStatusBadge extends StatelessWidget {
  const ChangeStatusBadge({super.key, required this.type, this.size = 20});

  final ChangeType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final badge = _badgeFor(type);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: badge.color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Text(
        badge.label,
        style: TextStyle(
          fontSize: size * 0.55,
          fontWeight: FontWeight.w700,
          color: badge.color,
        ),
      ),
    );
  }
}

class _Badge {
  const _Badge(this.label, this.color);

  final String label;
  final Color color;
}

_Badge _badgeFor(ChangeType type) {
  switch (type) {
    case ChangeType.added:
      return const _Badge('A', Color(0xFF16A34A));
    case ChangeType.modified:
      return const _Badge('M', Color(0xFFD97706));
    case ChangeType.deleted:
      return const _Badge('D', Color(0xFFDC2626));
    case ChangeType.renamed:
      return const _Badge('R', Color(0xFF7C3AED));
    case ChangeType.copied:
      return const _Badge('C', Color(0xFF0D9488));
    case ChangeType.untracked:
      return const _Badge('?', Color(0xFF64748B));
    case ChangeType.unknown:
      return const _Badge('?', Color(0xFF64748B));
  }
}
