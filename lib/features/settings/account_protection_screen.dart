import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/economy_service.dart';
import '../../services/firebase_session_service.dart';
import '../../services/player_profile_service.dart';

class AccountProtectionScreen extends StatefulWidget {
  const AccountProtectionScreen({super.key});

  @override
  State<AccountProtectionScreen> createState() =>
      _AccountProtectionScreenState();
}

class _AccountProtectionScreenState extends State<AccountProtectionScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _signInMode = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;
  String? _notice;

  User? get _user => FirebaseSessionService.currentUser;
  bool get _protected => _user != null && !_user!.isAnonymous;

  @override
  void initState() {
    super.initState();
    _emailController.text = _user?.email ?? '';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Protect player account')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  constraints.maxWidth < 360 ? 12 : 20,
                  12,
                  constraints.maxWidth < 360 ? 12 : 20,
                  32,
                ),
                children: [
                  _StatusCard(user: _user),
                  const SizedBox(height: 16),
                  if (_protected)
                    _buildProtectedAccount(context)
                  else
                    _buildAccountForm(context),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _MessagePanel(
                      icon: Icons.error_outline,
                      background: scheme.errorContainer,
                      foreground: scheme.onErrorContainer,
                      text: _error!,
                    ),
                  ],
                  if (_notice != null) ...[
                    const SizedBox(height: 12),
                    _MessagePanel(
                      icon: Icons.check_circle_outline,
                      background: scheme.primaryContainer,
                      foreground: scheme.onPrimaryContainer,
                      text: _notice!,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountForm(BuildContext context) {
    final validEmail = _emailController.text.trim().contains('@');
    final validPassword = _passwordController.text.length >= 8;
    final passwordsMatch =
        _signInMode || _passwordController.text == _confirmController.text;
    final canSubmit = validEmail && validPassword && passwordsMatch && !_busy;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _signInMode ? 'Sign in to a protected account' : 'Keep this account',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              _signInMode
                  ? 'Use the email and password you linked before. This device will open that account and its server wallet.'
                  : 'Link an email and password to the current player ID. Your Coin wallet, friends, rating and match history remain attached to the same Firebase account after reinstall or device change.',
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  icon: Icon(Icons.shield_outlined),
                  label: Text('Protect current'),
                ),
                ButtonSegment<bool>(
                  value: true,
                  icon: Icon(Icons.login_outlined),
                  label: Text('Sign in'),
                ),
              ],
              selected: <bool>{_signInMode},
              onSelectionChanged: _busy
                  ? null
                  : (selection) {
                      setState(() {
                        _signInMode = selection.first;
                        _error = null;
                        _notice = null;
                        _confirmController.clear();
                      });
                    },
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _emailController,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Email address',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              enabled: !_busy,
              obscureText: _hidePassword,
              autofillHints: _signInMode
                  ? const [AutofillHints.password]
                  : const [AutofillHints.newPassword],
              textInputAction:
                  _signInMode ? TextInputAction.done : TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: 'At least 8 characters',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _hidePassword ? 'Show password' : 'Hide password',
                  onPressed: () =>
                      setState(() => _hidePassword = !_hidePassword),
                  icon: Icon(
                    _hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: _signInMode && canSubmit ? (_) => _submit() : null,
            ),
            if (!_signInMode) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _confirmController,
                enabled: !_busy,
                obscureText: _hidePassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: const Icon(Icons.lock_reset_outlined),
                  border: const OutlineInputBorder(),
                  errorText: _confirmController.text.isNotEmpty && !passwordsMatch
                      ? 'Passwords do not match.'
                      : null,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: canSubmit ? (_) => _submit() : null,
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: canSubmit ? _submit : null,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_signInMode ? Icons.login : Icons.shield),
              label: Text(
                _busy
                    ? 'Please wait…'
                    : _signInMode
                        ? 'Sign in'
                        : 'Protect this player account',
              ),
            ),
            if (_signInMode) ...[
              const SizedBox(height: 6),
              TextButton(
                onPressed: _busy || !validEmail ? null : _sendPasswordReset,
                child: const Text('Forgot password?'),
              ),
              const SizedBox(height: 4),
              Text(
                'Signing in switches this device from the current guest player to the protected account. Guest and protected wallets are not merged.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProtectedAccount(BuildContext context) {
    final user = _user!;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Account protected',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(user.email ?? 'Email account'),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                user.emailVerified
                    ? Icons.verified_user_outlined
                    : Icons.mark_email_unread_outlined,
              ),
              title: Text(
                user.emailVerified ? 'Email verified' : 'Verify your email',
              ),
              subtitle: Text(
                user.emailVerified
                    ? 'This player account can be recovered on another device.'
                    : 'Open the message from Firebase and tap the verification link.',
              ),
            ),
            if (!user.emailVerified) ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : _sendVerification,
                icon: const Icon(Icons.forward_to_inbox_outlined),
                label: const Text('Resend verification email'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _refreshVerification,
                icon: const Icon(Icons.refresh),
                label: const Text('I verified it — refresh'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _busy ? null : _sendPasswordReset,
              icon: const Icon(Icons.password_outlined),
              label: const Text('Send password reset email'),
            ),
            const Divider(height: 28),
            TextButton.icon(
              onPressed: _busy ? null : _signOutToGuest,
              icon: const Icon(Icons.logout_outlined),
              label: const Text('Sign out on this device'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      if (_signInMode) {
        await FirebaseSessionService.signInWithEmail(
          email: _emailController.text,
          password: _passwordController.text,
        );
        await _refreshAccountServices();
        if (!mounted) return;
        setState(() {
          _notice = 'Protected player account opened.';
          _emailController.text = _user?.email ?? _emailController.text;
        });
      } else {
        await FirebaseSessionService.protectCurrentAccount(
          email: _emailController.text,
          password: _passwordController.text,
        );
        await _refreshAccountServices();
        if (!mounted) return;
        setState(() {
          _notice = 'Account protected. Check your inbox to verify the email.';
        });
      }
      _passwordController.clear();
      _confirmController.clear();
    } on FirebaseSessionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendVerification() async {
    await _runAccountAction(
      FirebaseSessionService.sendVerificationEmail,
      'Verification email sent.',
    );
  }

  Future<void> _refreshVerification() async {
    await _runAccountAction(
      FirebaseSessionService.reloadCurrentUser,
      FirebaseSessionService.currentUser?.emailVerified == true
          ? 'Email verified.'
          : 'Account refreshed.',
    );
  }

  Future<void> _sendPasswordReset() async {
    await _runAccountAction(
      () => FirebaseSessionService.sendPasswordReset(_emailController.text),
      'Password reset email sent.',
    );
  }

  Future<void> _signOutToGuest() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'The protected wallet remains on the account. This device will create a separate guest player until you sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    await _runAccountAction(() async {
      await FirebaseSessionService.signOutToGuest();
      await _refreshAccountServices();
      if (mounted) {
        _emailController.clear();
        _passwordController.clear();
        _confirmController.clear();
      }
    }, 'Guest player created.');
  }

  Future<void> _runAccountAction(
    Future<void> Function() action,
    String success,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      if (mounted) setState(() => _notice = success);
    } on FirebaseSessionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshAccountServices() async {
    try {
      await PlayerProfileService.instance.load();
    } catch (_) {
      // Profile creation/onboarding is retried by the existing identity gate.
    }
    await EconomyService.instance.refresh(showLoading: false);
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.user});

  final User? user;

  @override
  Widget build(BuildContext context) {
    final protected = user != null && !user!.isAnonymous;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: protected ? scheme.primaryContainer : scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              protected ? Icons.shield : Icons.shield_outlined,
              size: 38,
              color: protected
                  ? scheme.onPrimaryContainer
                  : scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    protected ? 'Recoverable account' : 'Guest account',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    protected
                        ? 'Your online identity is linked to ${user?.email ?? 'an email account'}.'
                        : 'Deleting the app or changing devices can make this anonymous Firebase player inaccessible. Protect it before buying Coins.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.text,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: foreground))),
          ],
        ),
      ),
    );
  }
}
