import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// Provides a shared [AnimationController] to all descendant [ShimmerBox]
/// widgets so they pulse in sync.
class ShimmerProvider extends StatefulWidget {
  const ShimmerProvider({super.key, required this.child});

  final Widget child;

  @override
  State<ShimmerProvider> createState() => _ShimmerProviderState();
}

class _ShimmerProviderState extends State<ShimmerProvider>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Motion.long * 2);
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Motion.standard),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Under reduce motion the placeholder holds still instead of pulsing
    // forever; setting the value also stops a running pulse.
    if (Motion.reduced(context)) {
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ShimmerData(animation: _animation, child: widget.child);
  }
}

class _ShimmerData extends InheritedWidget {
  const _ShimmerData({required this.animation, required super.child});

  final Animation<double> animation;

  static Animation<double>? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_ShimmerData>()?.animation;
  }

  @override
  bool updateShouldNotify(_ShimmerData oldWidget) =>
      animation != oldWidget.animation;
}

/// A rectangular placeholder box with a pulsing opacity animation.
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final animation = _ShimmerData.of(context);
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;

    if (animation == null) {
      // Fallback when no ShimmerProvider is above — static placeholder.
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      );
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color.withValues(alpha: animation.value),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Composite skeleton widgets
// ---------------------------------------------------------------------------

/// Mimics the 3-column stat card row on the home screen.
class SkeletonStatCards extends StatelessWidget {
  const SkeletonStatCards({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (i) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 12),
            child: const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: 64, height: 14),
                    SizedBox(height: 10),
                    ShimmerBox(width: 40, height: 24),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// A full-width placeholder for the map area.
class SkeletonMapPlaceholder extends StatelessWidget {
  const SkeletonMapPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    final animation = _ShimmerData.of(context);

    Widget content = Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Icon(
          Icons.map_outlined,
          size: 48,
          color: color.withValues(alpha: 0.6),
        ),
      ),
    );

    if (animation != null) {
      content = AnimatedBuilder(
        animation: animation,
        builder: (context, _) => Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: animation.value * 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Icon(
              Icons.map_outlined,
              size: 48,
              color: color.withValues(alpha: animation.value),
            ),
          ),
        ),
      );
    }

    return content;
  }
}

/// Mimics a single job card in the Jobs list.
class SkeletonJobCard extends StatelessWidget {
  const SkeletonJobCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerBox(width: 180, height: 16),
            SizedBox(height: 10),
            ShimmerBox(width: 140, height: 12),
            SizedBox(height: 8),
            ShimmerBox(width: 220, height: 12),
            SizedBox(height: 12),
            Row(
              children: [
                ShimmerBox(width: 80, height: 24, borderRadius: 12),
                SizedBox(width: 8),
                ShimmerBox(width: 60, height: 24, borderRadius: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Mimics a single vehicle card in the Vehicles list.
class SkeletonVehicleCard extends StatelessWidget {
  const SkeletonVehicleCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: ListTile(
        leading: ShimmerBox(width: 36, height: 36, borderRadius: 8),
        title: ShimmerBox(width: 120, height: 14),
        subtitle: ShimmerBox(width: 80, height: 12),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShimmerBox(width: 32, height: 32, borderRadius: 16),
            SizedBox(width: 8),
            ShimmerBox(width: 32, height: 32, borderRadius: 16),
          ],
        ),
      ),
    );
  }
}

/// Mimics the profile page layout during loading.
class SkeletonProfile extends StatelessWidget {
  const SkeletonProfile({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16.0),
      child: Column(
        children: [
          SizedBox(height: 16),
          // Avatar circle
          ShimmerBox(width: 80, height: 80, borderRadius: 40),
          SizedBox(height: 20),
          // Name
          ShimmerBox(width: 160, height: 18),
          SizedBox(height: 10),
          // Email
          ShimmerBox(width: 200, height: 14),
          SizedBox(height: 24),
          // Subscription card
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerBox(width: 120, height: 14),
                  SizedBox(height: 10),
                  ShimmerBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
