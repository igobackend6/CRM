import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/auth_state.dart';
import '../../domain/login_phone_normalizer.dart';
import '../providers/auth_providers.dart';
import '../widgets/mascot_state.dart';
import '../widgets/robot_scene.dart';

/// Animated Login Screen featuring the interactive winter Robot Mascot
/// and responsive Email / Phone segmented authentication.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _phoneFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _isPhoneMode = true;
  bool _obscurePassword = true;
  MascotState _mascotState = MascotState.idle;

  @override
  void initState() {
    super.initState();

    _phoneFocusNode.addListener(_handleFocusChange);
    _emailFocusNode.addListener(_handleFocusChange);
    _passwordFocusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (!mounted) return;
    if (_passwordFocusNode.hasFocus) {
      setState(() => _mascotState = MascotState.passwordFocus);
    } else if (_phoneFocusNode.hasFocus || _emailFocusNode.hasFocus) {
      setState(() => _mascotState = MascotState.emailFocus);
    } else {
      if (_mascotState != MascotState.error && _mascotState != MascotState.success) {
        setState(() => _mascotState = MascotState.idle);
      }
    }
  }

  @override
  void dispose() {
    _phoneFocusNode.removeListener(_handleFocusChange);
    _emailFocusNode.removeListener(_handleFocusChange);
    _passwordFocusNode.removeListener(_handleFocusChange);

    _phoneFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();

    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _switchMode(bool isPhone) {
    if (_isPhoneMode == isPhone) return;
    ref.read(authControllerProvider.notifier).clearError();
    setState(() {
      _isPhoneMode = isPhone;
      _mascotState = MascotState.idle;
    });
    FocusScope.of(context).unfocus();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    if (_isPhoneMode) {
      ref.read(authControllerProvider.notifier).signIn(
            phone: normalizeLoginPhone(_phoneController.text),
            password: _passwordController.text,
          );
    } else {
      ref.read(authControllerProvider.notifier).signInWithEmail(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    }
  }

  String? _validatePhone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 'Mobile number is required.';
    if (digits.length != 10) return 'Enter a 10-digit mobile number.';
    return null;
  }

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Email address is required.';
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) return 'Enter a valid email address.';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Listen to auth state transitions to trigger mascot celebrations or error shake
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next.status == AuthStatus.error) {
        setState(() => _mascotState = MascotState.error);
      } else if (next.status == AuthStatus.authenticated) {
        setState(() => _mascotState = MascotState.success);
      }
    });

    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.status == AuthStatus.authenticating;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Top Animated Winter Scene with Robot Mascot (edge-to-edge)
            RobotScene(
              state: _mascotState,
              height: 240,
              showCaption: false,
              onErrorCompleted: () {
                if (mounted && _mascotState == MascotState.error) {
                  setState(() => _mascotState = MascotState.idle);
                }
              },
            ),

            // 2. Form Pane on unified white background
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.xl,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Hero Caption below the Robot Animation
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF0FD),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFBFDBFE)),
                            ),
                            child: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.bolt, size: 13, color: Color(0xFF1D4ED8)),
                                  SizedBox(width: 4),
                                  Text(
                                    'EVERY LEAD, EVERY CALL • ONE CLEAR PIPELINE',
                                    style: TextStyle(
                                      color: Color(0xFF1D4ED8),
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Brand Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF0FD),
                                borderRadius: BorderRadius.circular(8),
                              ),
                                    child: const Icon(
                                      Icons.hub_outlined,
                                      size: 18,
                                      color: Color(0xFF1D4ED8),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    AppConstants.appName.toUpperCase(),
                                    style: const TextStyle(
                                      color: Color(0xFF1D4ED8),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),

                              // Welcome Heading
                              const Text(
                                'Welcome back',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  color: Color(0xFF1F2430),
                                ),
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'Enter your details to access your workspace',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF8A93A6),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),

                              // Mode Toggle (Phone / Email Segmented Pill)
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _SegmentPill(
                                        title: 'Phone',
                                        icon: Icons.phone_outlined,
                                        isActive: _isPhoneMode,
                                        onTap: () => _switchMode(true),
                                      ),
                                    ),
                                    Expanded(
                                      child: _SegmentPill(
                                        title: 'Email',
                                        icon: Icons.email_outlined,
                                        isActive: !_isPhoneMode,
                                        onTap: () => _switchMode(false),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),

                              // Error Message Banner (matches spec styling)
                              if (authState.status == AuthStatus.error &&
                                  authState.errorMessage != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.sm,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFDECEA),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFE53935).withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline,
                                        size: 18,
                                        color: Color(0xFFE53935),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          authState.errorMessage!,
                                          style: const TextStyle(
                                            color: Color(0xFFE53935),
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                              ],

                              // Active Input Field (Phone or Email)
                              if (_isPhoneMode)
                                TextFormField(
                                  controller: _phoneController,
                                  focusNode: _phoneFocusNode,
                                  enabled: !isLoading,
                                  keyboardType: TextInputType.phone,
                                  autofillHints: const [AutofillHints.telephoneNumber],
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(10),
                                  ],
                                  decoration: InputDecoration(
                                    labelText: 'Mobile number',
                                    prefixText: '+91  ',
                                    prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFC),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF1D4ED8),
                                        width: 1.8,
                                      ),
                                    ),
                                  ),
                                  validator: _validatePhone,
                                )
                              else
                                TextFormField(
                                  controller: _emailController,
                                  focusNode: _emailFocusNode,
                                  enabled: !isLoading,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email],
                                  decoration: InputDecoration(
                                    labelText: 'Email address',
                                    prefixIcon: const Icon(Icons.email_outlined, size: 20),
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFC),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF1D4ED8),
                                        width: 1.8,
                                      ),
                                    ),
                                  ),
                                  validator: _validateEmail,
                                ),
                              const SizedBox(height: AppSpacing.sm + 4),

                              // Password Field
                              TextFormField(
                                controller: _passwordController,
                                focusNode: _passwordFocusNode,
                                enabled: !isLoading,
                                obscureText: _obscurePassword,
                                autofillHints: const [AutofillHints.password],
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      size: 20,
                                      color: const Color(0xFF8A93A6),
                                    ),
                                    onPressed: () {
                                      setState(() => _obscurePassword = !_obscurePassword);
                                    },
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF1D4ED8),
                                      width: 1.8,
                                    ),
                                  ),
                                ),
                                validator: _validatePassword,
                                onFieldSubmitted: (_) => _submit(),
                              ),
                              const SizedBox(height: AppSpacing.md + 4),

                              // Submit Button
                              Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x3D1D4ED8),
                                      blurRadius: 12,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: isLoading ? null : _submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    foregroundColor: Colors.white,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        )
                                      : const Text(
                                          'Sign in',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),

                              // Admin Reset Note
                              const Text(
                                'Forgot password? Ask your admin to reset it.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF8A93A6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }

class _SegmentPill extends StatelessWidget {
  const _SegmentPill({
    required this.title,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isActive
              ? const [
                  BoxShadow(
                    color: Color(0x18000000),
                    blurRadius: 4,
                    offset: Offset(0, 1.5),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: isActive ? const Color(0xFF1F2430) : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? const Color(0xFF1F2430) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
