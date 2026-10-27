import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'feedback.dart';

/// Vastra's tactile paper system: warm paper surfaces folded into raised,
/// inset and pressed forms, with copper for action and emphasis.
abstract final class Tone {
  static const canvas = Color(0xffebe4da);
  static const paper = Color(0xfff5efe7);
  static const paperHigh = Color(0xfffcf9f4);
  static const paperShade = Color(0xffdfd5c8);
  static const sunken = Color(0xffe7dfd4);
  static const muted = Color(0xffdad0c3);
  static const line = Color(0xffd3c7b8);
  static const ink = Color(0xff2e2925);
  static const inkSoft = Color(0xff6c6258);
  static const copper = Color(0xffb4673f);
  static const copperLight = Color(0xffd79b76);
  static const copperDeep = Color(0xff8b4628);
  static const copperWash = Color(0xfff3e1d4);
  static const error = Color(0xffad3f2a);
}

abstract final class Space {
  static const xs = 4.0, s = 8.0, m = 12.0, l = 16.0, xl = 24.0, xxl = 32.0, huge = 52.0;
}

abstract final class Radii {
  static const none = 0.0, xs = 4.0, s = 8.0, m = 16.0, l = 24.0;
}

abstract final class Motion {
  static const quick = Duration(milliseconds: 120);
  static const medium = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 380);
  static const ease = Curves.easeOutCubic;
  static const settle = Cubic(0.2, 0.9, 0.25, 1.05);
}

/// Shadows for elevation levels 0 (base) to 3 (high).
List<BoxShadow> elevation(int level, {Color tint = Colors.black}) => switch (level) {
  1 => [BoxShadow(color: tint.withValues(alpha: 0.08), offset: const Offset(0, 4), blurRadius: 8)],
  2 => [BoxShadow(color: tint.withValues(alpha: 0.12), offset: const Offset(0, 8), blurRadius: 16)],
  3 => [BoxShadow(color: tint.withValues(alpha: 0.16), offset: const Offset(0, 16), blurRadius: 24)],
  _ => const [],
};

enum Surface { base, raised, inset, pressed }

BoxDecoration paperDecoration({
  Surface surface = Surface.raised,
  int level = 1,
  double radius = Radii.s,
  Color color = Tone.paper,
  Color? border,
  double borderWidth = 1,
  List<BoxShadow>? glow,
}) {
  final Color light = Color.lerp(color, Tone.paperHigh, 0.7)!, dark = Color.lerp(color, Tone.paperShade, 0.75)!;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: border ?? (surface == Surface.inset || surface == Surface.pressed ? Tone.line : Colors.white.withValues(alpha: 0.7)),
      width: borderWidth,
    ),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: switch (surface) {
        // Light from the top left: raised paper catches it, inset paper is shaded by its rim.
        Surface.raised => [light, color, dark],
        Surface.base => [color, color],
        Surface.inset => [Color.lerp(Tone.sunken, Tone.paperShade, 0.6)!, Tone.sunken, Tone.sunken, light],
        Surface.pressed => [dark, Color.lerp(color, Tone.sunken, 0.5)!, light],
      },
      stops: surface == Surface.inset ? const [0, 0.18, 0.8, 1] : null,
    ),
    boxShadow: [...?glow, ...surface == Surface.raised || surface == Surface.base ? elevation(level) : const []],
  );
}

class Paper extends StatelessWidget {
  const Paper({
    super.key,
    required this.child,
    this.surface = Surface.raised,
    this.level = 1,
    this.radius = Radii.s,
    this.padding = const EdgeInsets.all(Space.l),
    this.color = Tone.paper,
    this.border,
    this.borderWidth = 1,
  });
  final Widget child;
  final Surface surface;
  final int level;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color? border;
  final double borderWidth;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: Motion.medium,
    curve: Motion.ease,
    padding: padding,
    decoration: paperDecoration(
      surface: surface,
      level: level,
      radius: radius,
      color: color,
      border: border,
      borderWidth: borderWidth,
    ),
    child: child,
  );
}

/// Paper that lifts under the pointer and sinks when pressed, with a quiet cue.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.cue = Cue.tap,
    this.level = 1,
    this.radius = Radii.s,
    this.padding = EdgeInsets.zero,
    this.color = Tone.paper,
    this.border,
    this.borderWidth = 1,
    this.semanticLabel,
  });
  final Widget child;
  final VoidCallback? onTap;
  final Cue cue;
  final int level;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color? border;
  final double borderWidth;
  final String? semanticLabel;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hover = false, _down = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _tap())},
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTap: enabled ? _tap : null,
          child: AnimatedScale(
            scale: _down ? 0.975 : 1,
            duration: Motion.quick,
            curve: Motion.ease,
            child: AnimatedContainer(
              duration: Motion.quick,
              curve: Motion.ease,
              padding: widget.padding,
              transform: Matrix4.translationValues(0, _hover && !_down ? -2 : 0, 0),
              decoration: paperDecoration(
                surface: _down ? Surface.pressed : (enabled ? Surface.raised : Surface.base),
                level: _down ? 0 : (_hover ? widget.level + 1 : widget.level).clamp(0, 3),
                radius: widget.radius,
                color: enabled ? widget.color : Tone.muted,
                border: widget.border,
                borderWidth: widget.borderWidth,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }

  void _tap() {
    FeedbackScope.of(context).play(widget.cue);
    widget.onTap?.call();
  }
}

/// The primary action: folded copper, which shows a pinwheel while [busy].
class CopperButton extends StatefulWidget {
  const CopperButton({super.key, required this.label, required this.onPressed, this.icon, this.busy = false, this.cue = Cue.tap, this.compact = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy, compact;
  final Cue cue;
  @override
  State<CopperButton> createState() => _CopperButtonState();
}

class _CopperButtonState extends State<CopperButton> {
  bool _down = false, _hover = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final pressed = _down || widget.busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _tap())},
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTap: enabled ? _tap : null,
          child: AnimatedContainer(
            duration: Motion.quick,
            curve: Motion.ease,
            height: widget.compact ? 36 : 44,
            padding: EdgeInsets.symmetric(horizontal: widget.compact ? Space.m : Space.l + 2),
            transform: Matrix4.translationValues(0, pressed ? 1.5 : (_hover ? -1 : 0), 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.xs),
              border: Border.all(color: pressed ? Tone.copperDeep : Tone.copperLight.withValues(alpha: 0.9)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: widget.onPressed == null
                    ? [Tone.copperLight.withValues(alpha: 0.55), Tone.copperLight.withValues(alpha: 0.45)]
                    : pressed
                    ? [Tone.copperDeep, Tone.copper]
                    : [Tone.copperLight, Tone.copper, Tone.copperDeep],
                stops: pressed || widget.onPressed == null ? null : const [0, 0.45, 1],
              ),
              boxShadow: pressed || widget.onPressed == null ? const [] : elevation(_hover ? 3 : 2, tint: Tone.copperDeep),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 18, color: Colors.white),
                  const SizedBox(width: Space.s),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: widget.compact ? 13 : 14,
                      shadows: [Shadow(color: Tone.copperDeep.withValues(alpha: 0.6), offset: const Offset(0, 1))],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: Motion.medium,
                  curve: Motion.ease,
                  child: widget.busy
                      ? const Padding(
                          padding: EdgeInsets.only(left: Space.s),
                          child: Pinwheel(size: 18, light: true),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _tap() {
    FeedbackScope.of(context).play(widget.cue);
    widget.onPressed?.call();
  }
}

/// The secondary action: raised paper outlined in copper.
class PaperButton extends StatelessWidget {
  const PaperButton({super.key, required this.label, required this.onPressed, this.icon, this.cue = Cue.tap, this.compact = false, this.selected = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Cue cue;
  final bool compact, selected;
  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onPressed,
    cue: cue,
    radius: Radii.xs,
    border: onPressed == null ? Tone.line : Tone.copper,
    borderWidth: selected ? 2 : 1.5,
    color: selected ? Tone.copperWash : Tone.paper,
    semanticLabel: label,
    padding: EdgeInsets.symmetric(horizontal: compact ? Space.m : Space.l, vertical: compact ? 7 : 11),
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 16 : 18, color: onPressed == null ? Tone.inkSoft : Tone.copper),
            const SizedBox(width: Space.s),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onPressed == null ? Tone.inkSoft : Tone.copper,
                fontWeight: FontWeight.w600,
                fontSize: compact ? 12.5 : 14,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A quiet copper icon on raised paper.
class PaperIconButton extends StatelessWidget {
  const PaperIconButton({super.key, required this.icon, required this.tooltip, required this.onPressed, this.active = false, this.cue = Cue.tap, this.size = 40});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final Cue cue;
  final double size;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Pressable(
      onTap: onPressed,
      cue: cue,
      radius: size / 2,
      semanticLabel: tooltip,
      color: active ? Tone.copperWash : Tone.paper,
      border: active ? Tone.copper : null,
      child: SizedBox.square(
        dimension: size,
        child: Icon(icon, size: size * 0.48, color: active ? Tone.copperDeep : Tone.copper),
      ),
    ),
  );
}

/// "FOUNDATIONS"-style heading: a raised paper label leading a long fold.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Row(
      children: [
        Paper(
          radius: Radii.none,
          level: 1,
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: 0.8, color: Tone.ink),
          ),
        ),
        Expanded(
          child: Container(
            height: 22,
            margin: const EdgeInsets.only(right: Space.s),
            decoration: paperDecoration(surface: Surface.raised, level: 0, radius: Radii.none),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// A small copper flag, notched at its tail: New, Sale, Limited.
class RibbonBadge extends StatelessWidget {
  const RibbonBadge(this.label, {super.key, this.color = Tone.copper});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: _RibbonClipper(),
    child: Container(
      padding: const EdgeInsets.fromLTRB(Space.s, 3, Space.m, 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(color, Colors.white, 0.2)!, color, Color.lerp(color, Colors.black, 0.15)!],
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3),
      ),
    ),
  );
}

class _RibbonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(4, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width - 6, size.height / 2)
    ..lineTo(size.width, size.height)
    ..lineTo(4, size.height)
    ..lineTo(0, size.height - 4)
    ..lineTo(0, 4)
    ..close();
  @override
  bool shouldReclip(_RibbonClipper oldClipper) => false;
}

/// The origami pinwheel spinner.
class Pinwheel extends StatefulWidget {
  const Pinwheel({super.key, this.size = 40, this.light = false});
  final double size;
  final bool light;
  @override
  State<Pinwheel> createState() => _PinwheelState();
}

class _PinwheelState extends State<Pinwheel> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    child: RotationTransition(
      turns: _spin,
      child: CustomPaint(size: Size.square(widget.size), painter: _PinwheelPainter(widget.light)),
    ),
  );
}

class _PinwheelPainter extends CustomPainter {
  _PinwheelPainter(this.light);
  final bool light;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final tip = c + Offset(math.cos(a), math.sin(a)) * r;
      final side = c + Offset(math.cos(a + 0.62), math.sin(a + 0.62)) * r * 0.55;
      final blade = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(side.dx, side.dy)
        ..close();
      final base = light ? Colors.white : Tone.copper;
      canvas.drawPath(
        blade,
        Paint()..color = i.isEven ? base : Color.lerp(base, light ? Tone.copperWash : Tone.copperDeep, 0.45)!,
      );
    }
  }

  @override
  bool shouldRepaint(_PinwheelPainter oldDelegate) => oldDelegate.light != light;
}

/// Copper progress folded into an inset track, labelled on an arrow tag.
class CopperProgress extends StatelessWidget {
  const CopperProgress({super.key, required this.value, required this.label});
  final double? value;
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    value: value == null ? null : '${(value! * 100).round()}%',
    child: Container(
      height: 26,
      padding: const EdgeInsets.all(3),
      decoration: paperDecoration(surface: Surface.inset, radius: Radii.xs),
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(end: value ?? 0.35),
              duration: Motion.slow,
              curve: Motion.ease,
              builder: (context, v, _) => ClipPath(
                clipper: _ArrowClipper(),
                child: Container(
                  width: math.max(64, box.maxWidth * v),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Tone.copperLight, Tone.copper],
                    ),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: Space.s),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ArrowClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..lineTo(size.width - 8, 0)
    ..lineTo(size.width, size.height / 2)
    ..lineTo(size.width - 8, size.height)
    ..lineTo(0, size.height)
    ..close();
  @override
  bool shouldReclip(_ArrowClipper oldClipper) => false;
}

/// A four-step process line: done steps are filled, the active one is ringed.
class StepTrack extends StatelessWidget {
  const StepTrack({super.key, required this.steps, required this.active});
  final List<String> steps;
  final int active;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < steps.length; i++)
        Expanded(
          child: Column(
            children: [
              SizedBox(
                height: 18,
                child: Row(
                  children: [
                    Expanded(child: Container(height: 2, color: i == 0 ? Colors.transparent : (i <= active ? Tone.copper : Tone.line))),
                    AnimatedContainer(
                      duration: Motion.medium,
                      curve: Motion.settle,
                      width: i == active ? 18 : 12,
                      height: i == active ? 18 : 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < active ? Tone.copper : Tone.paper,
                        border: Border.all(color: i <= active ? Tone.copper : Tone.line, width: i == active ? 3 : 1.5),
                        boxShadow: i == active ? [BoxShadow(color: Tone.copperLight.withValues(alpha: 0.5), blurRadius: 8)] : null,
                      ),
                    ),
                    Expanded(child: Container(height: 2, color: i == steps.length - 1 ? Colors.transparent : (i < active ? Tone.copper : Tone.line))),
                  ],
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                steps[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: i == active ? FontWeight.w600 : FontWeight.w400,
                  color: i <= active ? Tone.ink : Tone.inkSoft,
                ),
              ),
              Text(
                i < active ? '(Done)' : (i == active ? '(Active)' : '(Pending)'),
                style: const TextStyle(fontSize: 10.5, color: Tone.inkSoft),
              ),
            ],
          ),
        ),
    ],
  );
}

/// A paper label holding a path, with the current place in copper.
class Breadcrumbs extends StatelessWidget {
  const Breadcrumbs(this.items, {super.key});
  final List<String> items;
  @override
  Widget build(BuildContext context) => Paper(
    radius: Radii.xs,
    level: 0,
    padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 6),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Text(
            items[i],
            style: TextStyle(
              fontSize: 12,
              color: i == items.length - 1 ? Tone.copper : Tone.ink,
              fontWeight: i == items.length - 1 ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          if (i < items.length - 1) const Icon(Icons.chevron_right, size: 15, color: Tone.inkSoft),
        ],
      ],
    ),
  );
}

/// Numbered pages, the current one pressed into the paper.
class Pagination extends StatelessWidget {
  const Pagination({super.key, required this.page, required this.pages, required this.onPage});
  final int page, pages;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) {
    final first = (page - 2).clamp(0, math.max(0, pages - 5)).toInt();
    return Paper(
      radius: Radii.xs,
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Previous page',
            onPressed: page == 0 ? null : () => _go(context, page - 1),
            icon: const Icon(Icons.chevron_left, color: Tone.copper),
          ),
          for (var i = first; i < math.min(pages, first + 5); i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Semantics(
                button: true,
                selected: i == page,
                label: 'Page ${i + 1}',
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.xs),
                  onTap: i == page ? null : () => _go(context, i),
                  child: AnimatedContainer(
                    duration: Motion.quick,
                    width: 32,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: i == page ? paperDecoration(surface: Surface.inset, radius: Radii.xs, border: Tone.copper) : null,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: i == page ? FontWeight.w600 : FontWeight.w400,
                        color: i == page ? Tone.copper : Tone.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Next page',
            onPressed: page >= pages - 1 ? null : () => _go(context, page + 1),
            icon: const Icon(Icons.chevron_right, color: Tone.copper),
          ),
        ],
      ),
    );
  }

  void _go(BuildContext context, int value) {
    FeedbackScope.of(context).play(Cue.tap);
    onPage(value);
  }
}

/// A circular raised portrait framed in a copper ring.
class PaperAvatar extends StatelessWidget {
  const PaperAvatar(this.label, {super.key, this.size = 52});
  final String label;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: Tone.copper, width: 3),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Tone.paperHigh, Tone.paper, Tone.paperShade],
      ),
      boxShadow: elevation(1),
    ),
    child: Text(
      label.trim().isEmpty ? '?' : label.trim().characters.first.toUpperCase(),
      style: TextStyle(fontSize: size * 0.4, color: Tone.copper, fontWeight: FontWeight.w600),
    ),
  );
}

/// Wavy placeholder lines that shimmer while details load.
class SkeletonRows extends StatefulWidget {
  const SkeletonRows({super.key, this.rows = 3});
  final int rows;
  @override
  State<SkeletonRows> createState() => _SkeletonRowsState();
}

class _SkeletonRowsState extends State<SkeletonRows> with SingleTickerProviderStateMixin {
  late final _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Column(
      children: [
        for (var i = 0; i < widget.rows; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Paper(
              surface: Surface.base,
              level: 0,
              radius: Radii.xs,
              padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
              child: AnimatedBuilder(
                animation: _wave,
                builder: (context, _) => CustomPaint(size: const Size(double.infinity, 26), painter: _WavePainter(_wave.value, i)),
              ),
            ),
          ),
      ],
    ),
  );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.t, this.row);
  final double t;
  final int row;
  @override
  void paint(Canvas canvas, Size size) {
    for (final (y, width) in [(7.0, 0.62 - row * 0.06), (19.0, 0.86 - row * 0.04)]) {
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width * width; x += 4) {
        path.lineTo(x, y + math.sin(x / 9 + t * 2 * math.pi) * 1.6);
      }
      final shimmer = (math.sin(t * 2 * math.pi + row) + 1) / 2;
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.lerp(Tone.line, Tone.paperShade, shimmer)!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) => oldDelegate.t != t;
}

/// The open paper box: nothing here yet, and the one action that fills it.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.message, this.action, this.onAction});
  final String title, message;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Paper(
    level: 1,
    padding: const EdgeInsets.all(Space.xxl),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ExcludeSemantics(child: CustomPaint(size: Size(120, 96), painter: _BoxPainter())),
        const SizedBox(height: Space.l),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: Space.s),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Tone.inkSoft)),
        if (action != null) ...[
          const SizedBox(height: Space.l),
          CopperButton(label: action!, icon: Icons.add, onPressed: onAction, compact: true),
        ],
      ],
    ),
  );
}

class _BoxPainter extends CustomPainter {
  const _BoxPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final stroke = Paint()
      ..color = Tone.copper
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = Tone.copperWash;
    final front = Path()
      ..moveTo(w * 0.18, h * 0.42)
      ..lineTo(w * 0.5, h * 0.56)
      ..lineTo(w * 0.5, h)
      ..lineTo(w * 0.18, h * 0.86)
      ..close();
    final side = Path()
      ..moveTo(w * 0.5, h * 0.56)
      ..lineTo(w * 0.82, h * 0.42)
      ..lineTo(w * 0.82, h * 0.86)
      ..lineTo(w * 0.5, h)
      ..close();
    final flapLeft = Path()
      ..moveTo(w * 0.18, h * 0.42)
      ..lineTo(w * 0.02, h * 0.22)
      ..lineTo(w * 0.34, h * 0.08)
      ..lineTo(w * 0.5, h * 0.28)
      ..close();
    final flapRight = Path()
      ..moveTo(w * 0.82, h * 0.42)
      ..lineTo(w * 0.98, h * 0.22)
      ..lineTo(w * 0.66, h * 0.08)
      ..lineTo(w * 0.5, h * 0.28)
      ..close();
    for (final p in [flapLeft, flapRight, front, side]) {
      canvas
        ..drawPath(p, fill)
        ..drawPath(p, stroke);
    }
    canvas.drawLine(Offset(w * 0.18, h * 0.42), Offset(w * 0.5, h * 0.28), stroke);
    canvas.drawLine(Offset(w * 0.82, h * 0.42), Offset(w * 0.5, h * 0.28), stroke);
  }

  @override
  bool shouldRepaint(_BoxPainter oldDelegate) => false;
}

/// A copper-bordered notice with a megaphone: "Important Update: …".
class AlertBanner extends StatelessWidget {
  const AlertBanner({super.key, required this.title, required this.message, this.icon = Icons.campaign_outlined, this.actions = const []});
  final String title, message;
  final IconData icon;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Paper(
    border: Tone.copper,
    borderWidth: 2,
    level: 2,
    radius: Radii.xs,
    padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Space.m,
      runSpacing: Space.s,
      children: [
        Icon(icon, color: Tone.copper),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '$title ', style: const TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: message),
            ],
          ),
        ),
        ...actions,
      ],
    ),
  );
}

/// An input pressed into the paper, ringed in glowing copper when focused.
class PaperField extends StatefulWidget {
  const PaperField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.error,
    this.enabled = true,
    this.autofocus = false,
    this.keyboardType,
    this.maxLength,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
  });
  final TextEditingController controller;
  final String label;
  final String? hint, helper, error;
  final bool enabled, autofocus;
  final TextInputType? keyboardType;
  final int? maxLength;
  final int maxLines;
  final IconData? prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged, onSubmitted;
  @override
  State<PaperField> createState() => _PaperFieldState();
}

class _PaperFieldState extends State<PaperField> {
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus, error = widget.error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: Motion.medium,
          curve: Motion.ease,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.xs),
            boxShadow: focused || error
                ? [BoxShadow(color: (error ? Tone.error : Tone.copperLight).withValues(alpha: 0.45), blurRadius: 12, spreadRadius: 1)]
                : const [],
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            enabled: widget.enabled,
            autofocus: widget.autofocus,
            keyboardType: widget.keyboardType,
            maxLength: widget.maxLength,
            maxLines: widget.maxLines,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              counterText: '',
              prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon, color: Tone.copper),
              suffixIcon: widget.suffix,
              enabledBorder: error ? _border(Tone.error, 2) : null,
            ),
          ),
        ),
        AnimatedSize(
          duration: Motion.medium,
          curve: Motion.ease,
          alignment: Alignment.topLeft,
          child: widget.error != null || widget.helper != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 6, left: 2),
                  child: Text(
                    widget.error ?? widget.helper!,
                    style: TextStyle(fontSize: 12, color: error ? Tone.error : Tone.inkSoft),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

OutlineInputBorder _border(Color color, double width) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(Radii.xs),
  borderSide: BorderSide(color: color, width: width),
);

ThemeData paperTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Tone.copper,
    primary: Tone.copper,
    onPrimary: Colors.white,
    secondary: Tone.copperDeep,
    surface: Tone.paper,
    onSurface: Tone.ink,
    error: Tone.error,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Inter',
    colorScheme: scheme,
    scaffoldBackgroundColor: Tone.canvas,
    canvasColor: Tone.canvas,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Tone.copperWash.withValues(alpha: 0.5),
    hoverColor: Tone.copperWash.withValues(alpha: 0.4),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontWeight: FontWeight.w700, color: Tone.ink, letterSpacing: -0.5),
      headlineMedium: TextStyle(fontWeight: FontWeight.w600, color: Tone.ink, letterSpacing: -0.3),
      titleLarge: TextStyle(fontWeight: FontWeight.w600, color: Tone.ink),
      bodyMedium: TextStyle(color: Tone.ink, height: 1.45),
      bodySmall: TextStyle(color: Tone.inkSoft),
    ).apply(bodyColor: Tone.ink, displayColor: Tone.ink),
    iconTheme: const IconThemeData(color: Tone.copper, size: 22),
    appBarTheme: const AppBarTheme(
      backgroundColor: Tone.canvas,
      foregroundColor: Tone.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Tone.sunken,
      labelStyle: const TextStyle(color: Tone.inkSoft),
      floatingLabelStyle: const TextStyle(color: Tone.copper),
      hintStyle: TextStyle(color: Tone.inkSoft.withValues(alpha: 0.7)),
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 14),
      border: _border(Tone.line, 1),
      enabledBorder: _border(Tone.line, 1),
      focusedBorder: _border(Tone.copper, 2),
      errorBorder: _border(Tone.error, 2),
      focusedErrorBorder: _border(Tone.error, 2),
      disabledBorder: _border(Tone.line.withValues(alpha: 0.6), 1),
    ),
    checkboxTheme: CheckboxThemeData(
      side: const BorderSide(color: Tone.copper, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xs)),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Tone.copperWash : Tone.paper),
      checkColor: const WidgetStatePropertyAll(Tone.copper),
    ),
    radioTheme: const RadioThemeData(fillColor: WidgetStatePropertyAll(Tone.copper)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Tone.paperHigh : Tone.paper),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Tone.copper : Tone.muted),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Tone.copperDeep : Tone.line),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Tone.copper,
      inactiveTrackColor: Tone.line,
      thumbColor: Tone.copper,
      overlayColor: Color(0x33b4673f),
      valueIndicatorColor: Tone.paper,
      valueIndicatorTextStyle: TextStyle(color: Tone.ink),
      tickMarkShape: RoundSliderTickMarkShape(tickMarkRadius: 1.5),
      activeTickMarkColor: Tone.copperDeep,
      inactiveTickMarkColor: Tone.inkSoft,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: paperDecoration(level: 2, radius: Radii.xs, border: Tone.line),
      textStyle: const TextStyle(color: Tone.ink, fontSize: 12),
      waitDuration: const Duration(milliseconds: 400),
    ),
    dividerTheme: const DividerThemeData(color: Tone.line, thickness: 1),
    chipTheme: ChipThemeData(
      backgroundColor: Tone.paper,
      selectedColor: Tone.copperWash,
      side: const BorderSide(color: Tone.line),
      labelStyle: const TextStyle(color: Tone.ink, fontSize: 12.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xs)),
      checkmarkColor: Tone.copper,
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      menuStyle: MenuStyle(backgroundColor: WidgetStatePropertyAll(Tone.paper)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Tone.paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.s)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

/// Gives every paper control access to sound and haptic feedback.
class FeedbackScope extends InheritedNotifier<UiFeedback> {
  const FeedbackScope({super.key, required UiFeedback feedback, required super.child}) : super(notifier: feedback);
  static UiFeedback of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FeedbackScope>()?.notifier ?? _silent;
  static final _silent = UiFeedback.silent();
}

/// Opens a dialog that unfolds like a letter from its envelope.
Future<T?> showPaperDialog<T>(BuildContext context, {required WidgetBuilder builder, bool dismissible = true}) {
  final feedback = FeedbackScope.of(context)..play(Cue.open);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Close',
    barrierColor: Tone.ink.withValues(alpha: 0.28),
    transitionDuration: Motion.slow,
    pageBuilder: (context, _, _) => SafeArea(child: Builder(builder: builder)),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Motion.settle, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: const Interval(0, 0.6)),
        child: AnimatedBuilder(
          animation: curved,
          child: child,
          builder: (context, child) => Transform(
            alignment: Alignment.topCenter,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateX((1 - curved.value) * -0.35)
              ..scaleByDouble(0.94 + 0.06 * curved.value, 0.94 + 0.06 * curved.value, 1, 1)
              ..translateByDouble(0, (1 - curved.value) * 24, 0, 1),
            child: child,
          ),
        ),
      );
    },
  ).whenComplete(() => feedback.play(Cue.close));
}

/// The paper sheet a dialog is written on, with its envelope fold behind.
class PaperSheet extends StatelessWidget {
  const PaperSheet({super.key, required this.child, this.maxWidth = 560, this.padding = const EdgeInsets.all(Space.xl)});
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Space.l),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Material(
          type: MaterialType.transparency,
          child: DecoratedBox(
            decoration: paperDecoration(level: 3, radius: Radii.s, color: Tone.paper),
            child: CustomPaint(
              painter: const _EnvelopeFold(),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

class _EnvelopeFold extends CustomPainter {
  const _EnvelopeFold();
  @override
  void paint(Canvas canvas, Size size) {
    final fold = Paint()
      ..color = Tone.paperShade.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    final depth = math.min(70.0, size.height * 0.18);
    canvas
      ..drawLine(const Offset(0, 0), Offset(size.width / 2, depth), fold)
      ..drawLine(Offset(size.width, 0), Offset(size.width / 2, depth), fold);
  }

  @override
  bool shouldRepaint(_EnvelopeFold oldDelegate) => false;
}

enum ToastKind { success, info, warning, error }

/// A stack of paper notes, newest at the bottom, that fold away by themselves.
class ToastHost extends StatefulWidget {
  const ToastHost({super.key, required this.child});
  final Widget child;
  static ToastHostState of(BuildContext context) => context.findAncestorStateOfType<ToastHostState>()!;
  @override
  State<ToastHost> createState() => ToastHostState();
}

class _Toast {
  _Toast(this.kind, this.message);
  final ToastKind kind;
  final String message;
  final key = UniqueKey();
}

class ToastHostState extends State<ToastHost> {
  final _toasts = <_Toast>[];

  void show(ToastKind kind, String message) {
    final toast = _Toast(kind, message);
    setState(() {
      _toasts.add(toast);
      if (_toasts.length > 3) _toasts.removeAt(0);
    });
    if (kind == ToastKind.success) FeedbackScope.of(context).play(Cue.success);
    if (kind == ToastKind.error) FeedbackScope.of(context).play(Cue.error);
    Timer(Duration(milliseconds: 2600 + message.length * 25), () {
      if (mounted) setState(() => _toasts.remove(toast));
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 880;
    return Stack(
      children: [
        widget.child,
        Positioned(
          right: Space.l,
          left: wide ? null : Space.l,
          bottom: wide ? Space.xl : 92,
          child: SafeArea(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final t in _toasts)
                    TweenAnimationBuilder<double>(
                      key: t.key,
                      tween: Tween(begin: 0, end: 1),
                      duration: Motion.medium,
                      curve: Motion.settle,
                      builder: (context, v, child) => Opacity(
                        opacity: v.clamp(0, 1),
                        child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: child),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: Space.s),
                        child: Semantics(
                          liveRegion: true,
                          child: Material(
                            type: MaterialType.transparency,
                            child: Container(
                              decoration: paperDecoration(level: 2, radius: Radii.xs),
                              child: IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Container(
                                      width: 4,
                                      color: t.kind == ToastKind.error || t.kind == ToastKind.warning ? Tone.error : Tone.copper,
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 10),
                                        child: Text.rich(
                                          TextSpan(
                                            children: [
                                              TextSpan(
                                                text: '${switch (t.kind) {
                                                  ToastKind.success => 'Success',
                                                  ToastKind.info => 'Info',
                                                  ToastKind.warning => 'Warning',
                                                  ToastKind.error => 'Error',
                                                }}: ',
                                                style: const TextStyle(fontWeight: FontWeight.w600),
                                              ),
                                              TextSpan(text: t.message),
                                            ],
                                          ),
                                          style: const TextStyle(fontSize: 13.5),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Folder tabs: the chosen tab rises forward, ringed in copper.
class FolderTabs extends StatelessWidget {
  const FolderTabs({super.key, required this.labels, required this.selected, required this.onSelect});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < labels.length; i++)
          Semantics(
            selected: i == selected,
            button: true,
            label: labels[i],
            excludeSemantics: true,
            child: GestureDetector(
              onTap: i == selected
                  ? null
                  : () {
                      FeedbackScope.of(context).play(Cue.toggle);
                      onSelect(i);
                    },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: Motion.medium,
                  curve: Motion.ease,
                  margin: const EdgeInsets.only(right: 3),
                  padding: EdgeInsets.symmetric(horizontal: Space.l + 2, vertical: i == selected ? 11 : 9),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.s)),
                    border: Border.all(color: i == selected ? Tone.copper : Tone.line, width: i == selected ? 2 : 1),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: i == selected ? [Tone.paperHigh, Tone.paper] : [Tone.muted, Color.lerp(Tone.muted, Tone.paperShade, 0.5)!],
                    ),
                    boxShadow: i == selected ? elevation(1) : null,
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontWeight: i == selected ? FontWeight.w600 : FontWeight.w500,
                      color: i == selected ? Tone.copper : Tone.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Fades the old page out and the new one up, for moving between sections.
class FadeThrough extends StatelessWidget {
  const FadeThrough({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: Motion.slow,
    switchInCurve: const Interval(0.3, 1, curve: Motion.ease),
    switchOutCurve: const Interval(0.6, 1, curve: Curves.easeIn),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(scale: Tween(begin: 0.985, end: 1.0).animate(animation), child: child),
    ),
    child: child,
  );
}

/// Rises into place a moment after the item before it.
class Arrive extends StatelessWidget {
  const Arrive({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Motion.slow + Duration(milliseconds: 40 * math.min(index, 10)),
    curve: Interval(math.min(index, 10) * 0.06, 1, curve: Motion.ease),
    builder: (context, v, child) => Opacity(
      opacity: v,
      child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: child),
    ),
    child: child,
  );
}
