import 'package:flutter/material.dart';

@immutable
class ResponsiveMetrics {
  const ResponsiveMetrics._({
    required this.width,
    required this.height,
    required this.textScale,
    required this.viewInsets,
    required this.viewPadding,
  });

  factory ResponsiveMetrics.of(BuildContext context) {
    final media = MediaQuery.of(context);
    return ResponsiveMetrics._(
      width: media.size.width,
      height: media.size.height,
      textScale: media.textScaler.scale(1),
      viewInsets: media.viewInsets,
      viewPadding: media.viewPadding,
    );
  }

  final double width;
  final double height;
  final double textScale;
  final EdgeInsets viewInsets;
  final EdgeInsets viewPadding;

  bool get isTiny => width < 360;
  bool get isPhone => width < 600;
  bool get isTablet => width >= 600;
  bool get isLargeTablet => width >= 800;
  bool get isShort => height < 620;
  bool get hasLargeText => textScale >= 1.3;
  bool get hasVeryLargeText => textScale >= 1.7;
  bool get keyboardVisible => viewInsets.bottom > 0;

  double get pagePadding => isTiny ? 12 : isTablet ? 24 : 16;
  double get contentMaxWidth => isLargeTablet ? 920 : isTablet ? 760 : 680;
}

Future<T?> showAdaptiveBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = true,
  bool useSafeArea = true,
  bool isScrollControlled = true,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? backgroundColor,
  Color? barrierColor,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  RouteSettings? routeSettings,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    showDragHandle: showDragHandle,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: backgroundColor,
    barrierColor: barrierColor,
    elevation: elevation,
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: constraints,
    routeSettings: routeSettings,
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      return AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(bottom: 12),
            child: builder(sheetContext),
          ),
        ),
      );
    },
  );
}

class AdaptiveActionGroup extends StatelessWidget {
  const AdaptiveActionGroup({
    super.key,
    required this.children,
    this.spacing = 8,
    this.runSpacing = 8,
    this.stretchOnCompact = true,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final bool stretchOnCompact;

  @override
  Widget build(BuildContext context) {
    final metrics = ResponsiveMetrics.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 480 ||
            metrics.hasLargeText ||
            metrics.isTiny;
        if (!compact) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) SizedBox(width: spacing),
                children[index],
              ],
            ],
          );
        }
        if (!stretchOnCompact) {
          return Wrap(
            spacing: spacing,
            runSpacing: runSpacing,
            alignment: WrapAlignment.end,
            children: children,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) SizedBox(height: runSpacing),
              children[index],
            ],
          ],
        );
      },
    );
  }
}

class ResponsiveConstrainedContent extends StatelessWidget {
  const ResponsiveConstrainedContent({
    super.key,
    required this.child,
    this.padding,
    this.maxWidth,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final metrics = ResponsiveMetrics.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? metrics.contentMaxWidth,
        ),
        child: Padding(
          padding: padding ?? EdgeInsets.all(metrics.pagePadding),
          child: child,
        ),
      ),
    );
  }
}
