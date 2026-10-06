import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Height of every screen's top bar — matches the Allocations header.
const double kBrandAppBarHeight = 64;

/// The brand-gradient decoration used behind every top bar (and the
/// Allocations header, which has its own layout): the panel's
/// `--gradient-brand`, top-left to bottom-right, with a soft shadow.
const BoxDecoration brandHeaderDecoration = BoxDecoration(
  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppColors.gradientBrand),
  boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
);

/// An [AppBar] with the brand-gradient background — every screen's top bar
/// goes through this, so the whole app reads as one product. White title
/// and icons come from `AppTheme`'s `appBarTheme`, so they apply here and
/// to any plain `AppBar` alike; this only adds the gradient and the
/// shared height.
AppBar brandAppBar({
  Key? key,
  Widget? title,
  List<Widget>? actions,
  Widget? leading,
  PreferredSizeWidget? bottom,
  bool automaticallyImplyLeading = true,
}) {
  return AppBar(
    key: key,
    title: title,
    actions: actions,
    leading: leading,
    bottom: bottom,
    automaticallyImplyLeading: automaticallyImplyLeading,
    toolbarHeight: kBrandAppBarHeight,
    flexibleSpace: const DecoratedBox(decoration: brandHeaderDecoration, child: SizedBox.expand()),
  );
}
