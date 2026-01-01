import 'dart:ui';
import 'package:flutter/material.dart';

/// Shows a polished startup summary dialog with a subtle blur and scale/fade
/// transition. Use the helper `showStartupSummaryDialog` to display it.
Future<void> showStartupSummaryDialog(
  BuildContext context, {
  required String title,
  required List<Widget> items,
  required String actionLabel,
  required VoidCallback onAction,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Startup summary',
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (ctx, anim1, anim2) {
      // The pageBuilder must return the widget to show; animation handled in
      // transitionBuilder below, but we still build the dialog contents here.
      return SafeArea(
        child: Builder(
          builder: (innerCtx) => Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16.0),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 520),
                      decoration: BoxDecoration(
                        // Prefer DialogTheme.backgroundColor when available; fall back
                        // to colorScheme.surface. Avoid using the deprecated
                        // Theme.of(...).dialogBackgroundColor getter.
                        color: (Theme.of(innerCtx).dialogTheme.backgroundColor ?? Theme.of(innerCtx).colorScheme.surface)
                            .withAlpha((0.95 * 255).round()),
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(title, style: Theme.of(innerCtx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.of(innerCtx).pop(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Flexible(child: Column(mainAxisSize: MainAxisSize.min, children: items)),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(onPressed: () => Navigator.of(innerCtx).pop(), child: const Text('Cerrar')),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () {
                                  // Close dialog first, then run the action.
                                  Navigator.of(innerCtx).pop();
                                  // Defer to next microtask so the pop animation can start.
                                  Future.microtask(onAction);
                                },
                                child: Text(actionLabel),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim1, anim2, child) {
      final curved = Curves.easeOut.transform(anim1.value);
      return Opacity(
        opacity: curved,
        child: Transform.scale(
          scale: 0.95 + 0.05 * curved,
          child: child,
        ),
      );
    },
  );
}
