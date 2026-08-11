import 'package:flutter/material.dart';

class InPageHeader extends StatelessWidget {
  const InPageHeader({
    super.key,
    this.title,
    this.actions = const <Widget>[],
    this.showBack = true,
    this.leading,
    this.padding = const EdgeInsets.fromLTRB(4, 0, 4, 10),
  });

  final String? title;
  final List<Widget> actions;
  final bool showBack;
  final Widget? leading;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final canPop = showBack && Navigator.of(context).canPop();
    final titleWidget = title == null
        ? const Spacer()
        : Expanded(
            child: Text(
              title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
          );

    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (leading != null)
            leading!
          else if (canPop)
            IconButton.filledTonal(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          if (canPop || leading != null) const SizedBox(width: 8),
          titleWidget,
          ...actions,
        ],
      ),
    );
  }
}
