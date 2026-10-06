import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/onboarding_page_data.dart';
import '../providers/onboarding_providers.dart';
import '../widgets/onboarding_illustrations.dart';
import '../widgets/onboarding_next_button.dart';

/// First-launch intro: swipeable slides that end in a "Get Started" button.
/// Finishing (or skipping) flips the onboarding flag; the router then moves
/// on to the login screen by itself (see `resolveRedirect`).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.pages = onboardingPages});

  final List<OnboardingPageData> pages;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;
  bool _finishing = false;

  bool get _isLast => _page == widget.pages.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _pageController.animateToPage(page, duration: const Duration(milliseconds: 450), curve: Curves.easeInOutCubic);
  }

  void _next() => _isLast ? _finish() : _goTo(_page + 1);

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    await ref.read(onboardingControllerProvider.notifier).complete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return PopScope(
      // Back steps to the previous slide; only the first slide lets the OS
      // leave the app.
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(_page - 1);
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Soft corner blob behind the header.
            Positioned(
              top: -150,
              left: -150,
              child: Container(
                width: 380,
                height: 380,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (dark ? AppColors.accentBgDark : AppColors.accentBg).withValues(alpha: 0.9),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _Header(showSkip: !_isLast, onSkip: _finish),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: widget.pages.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (context, i) => _SlideContent(data: widget.pages[i], active: i == _page),
                    ),
                  ),
                  _PageDots(count: widget.pages.length, current: _page),
                  const SizedBox(height: 22),
                  OnboardingNextButton(progress: (_page + 1) / widget.pages.length, isLast: _isLast, onPressed: _next),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.showSkip, required this.onSkip});

  final bool showSkip;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              gradient: const LinearGradient(colors: AppColors.gradientBrand, begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: const Icon(Icons.hub_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Text(
            AppConstants.appName,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
          ),
          const Spacer(),
          AnimatedOpacity(
            opacity: showSkip ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: IgnorePointer(
              ignoring: !showSkip,
              child: TextButton(
                onPressed: onSkip,
                child: Text(
                  'Skip',
                  style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideContent extends StatelessWidget {
  const _SlideContent({required this.data, required this.active});

  final OnboardingPageData data;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // The illustration takes whatever height the copy below leaves.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: OnboardingIllustration(type: data.illustration, active: active),
          ),
        ),
        // Fixed height so the dots and button never jump between slides;
        // scrollable so a large system font can't overflow it.
        SizedBox(
          height: 168,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(32, 12, 32, 0),
            child: AnimatedSlide(
              offset: active ? Offset.zero : const Offset(0, 0.08),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: active ? 1 : 0.35,
                duration: const Duration(milliseconds: 450),
                child: Column(
                  children: [
                    Text(
                      data.title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(fontSize: 26, color: theme.colorScheme.onSurface),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      data.subtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Page ${current + 1} of $count',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == current ? 28 : 8,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: i == current ? AppColors.accent : AppColors.accent.withValues(alpha: 0.22),
              ),
            ),
        ],
      ),
    );
  }
}
