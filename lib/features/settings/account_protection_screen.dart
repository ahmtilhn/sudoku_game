import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/account_deletion_service.dart';
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
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

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
    _email.text = _user?.email ?? '';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Player account')),
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
                    _protectedCard(context)
                  else
                    _accountForm(context),
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
                  const SizedBox(height: 24),
                  Text(
                    'Account data',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: Icon(
                        Icons.delete_forever_outlined,
                        color: scheme.error,
                      ),
                      title: Text(
                        'Delete player account',
                        style: TextStyle(color: scheme.error),
                      ),
                      subtitle: const Text(
                        'Permanently removes the server wallet, purchases, Friend ID, friends, ratings and match history.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy ? null : _deleteAccount,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountForm(BuildContext context) {
    final validEmail = RegExp(
      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
    ).hasMatch(_email.text.trim());
    final validPassword = _password.text.length >= 8;
    final matches = _signInMode || _password.text == _confirm.text;
    final canSubmit = validEmail && validPassword && matches && !_busy;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _signInMode
                  ? 'Sign in to a protected account'
                  : 'Protect the current guest',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              _signInMode
                  ? 'Open the same server wallet, Friend ID and rating on this device.'
                  : 'Link email/password without changing the current Firebase UID, wallet, Friend ID, friends or rating.',
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.shield_outlined),
                  label: Text('Protect current'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.login_outlined),
                  label: Text('Sign in'),
                ),
              ],
              selected: <bool>{_signInMode},
              onSelectionChanged: _busy
                  ? null
                  : (values) => setState(() {
                      _signInMode = values.first;
                      _error = null;
                      _notice = null;
                      _confirm.clear();
                    }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
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
              controller: _password,
              enabled: !_busy,
              obscureText: _hidePassword,
              autofillHints: _signInMode
                  ? const [AutofillHints.password]
                  : const [AutofillHints.newPassword],
              textInputAction: _signInMode
                  ? TextInputAction.done
                  : TextInputAction.next,
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
                    _hidePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: _signInMode && canSubmit ? (_) => _submit() : null,
            ),
            if (!_signInMode) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                enabled: !_busy,
                obscureText: _hidePassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: const Icon(Icons.lock_reset_outlined),
                  border: const OutlineInputBorder(),
                  errorText: _confirm.text.isNotEmpty && !matches
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
              Text(
                'Signing in switches away from the current guest. Guest and protected wallets are never merged.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _protectedCard(BuildContext context) {
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
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(user.email ?? 'Protected account'),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                user.emailVerified
                    ? Icons.verified_user_outlined
                    : Icons.mark_email_unread_outlined,
              ),
              title: Text(
                user.emailVerified
                    ? 'Email verified'
                    : 'Email verification required',
              ),
              subtitle: Text(
                user.emailVerified
                    ? 'Paid Coin purchases can be recovered on another device.'
                    : 'Verify the email before buying Coins.',
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
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: _busy ? null : _sendPasswordReset,
              icon: const Icon(Icons.password_outlined),
              label: const Text('Send password reset email'),
            ),
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
    _setBusy(true);
    try {
      if (_signInMode) {
        await FirebaseSessionService.signInWithEmail(
          email: _email.text,
          password: _password.text,
        );
        await _refreshServices();
        _notice = 'Protected player account opened.';
      } else {
        await FirebaseSessionService.protectCurrentAccount(
          email: _email.text,
          password: _password.text,
        );
        await _refreshServices();
        _notice = 'Account protected. Check your inbox to verify the email.';
      }
      _password.clear();
      _confirm.clear();
    } on FirebaseSessionException catch (error) {
      _error = error.message;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _sendVerification() => _run(
    FirebaseSessionService.sendVerificationEmail,
    'Verification email sent.',
  );

  Future<void> _refreshVerification() => _run(
    () async {
      await FirebaseSessionService.reloadCurrentUser();
      await _refreshServices();
    },
    FirebaseSessionService.currentUser?.emailVerified == true
        ? 'Email verified.'
        : 'Account refreshed.',
  );

  Future<void> _sendPasswordReset() => _run(
    () => FirebaseSessionService.sendPasswordReset(_email.text),
    'Password reset email sent.',
  );

  Future<void> _signOutToGuest() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'The protected wallet remains on the account. This device will use a separate guest until you sign in again.',
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
    await _run(() async {
      await FirebaseSessionService.signOutToGuest();
      await _refreshServices();
      _email.clear();
      _password.clear();
      _confirm.clear();
    }, 'Guest player created.');
  }

  Future<void> _deleteAccount() async {
    final confirmation = TextEditingController();
    final password = TextEditingController();
    var hidden = true;
    final result = await showDialog<({String confirmation, String password})>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final valid =
              confirmation.text.trim().toUpperCase() == 'DELETE' &&
              (!_protected || password.text.length >= 8);
          return AlertDialog(
            title: const Text('Delete player account permanently?'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'This cannot be undone. Coin balance, purchases, Friend ID, friends, ratings, challenges and match history will be removed. Finish or forfeit any active online match first.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: confirmation,
                      autofocus: true,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Type DELETE',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    if (_protected) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: password,
                        obscureText: hidden,
                        decoration: InputDecoration(
                          labelText: 'Current password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setDialogState(() => hidden = !hidden),
                            icon: Icon(
                              hidden
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: valid
                    ? () => Navigator.of(dialogContext).pop((
                        confirmation: confirmation.text,
                        password: password.text,
                      ))
                    : null,
                child: const Text('Delete permanently'),
              ),
            ],
          );
        },
      ),
    );
    confirmation.dispose();
    password.dispose();
    if (result == null) return;

    _setBusy(true);
    try {
      await AccountDeletionService.instance.deleteCurrentAccount(
        password: _protected ? result.password : null,
      );
      await EconomyService.instance.refresh(showLoading: false);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Player account and server data deleted.'),
        ),
      );
    } on AccountDeletionException catch (error) {
      _error = error.message;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    _setBusy(true);
    try {
      await action();
      _notice = success;
    } on FirebaseSessionException catch (error) {
      _error = error.message;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _refreshServices() async {
    try {
      await PlayerProfileService.instance.load();
    } catch (_) {
      // Existing identity onboarding recreates/loads the profile when needed.
    }
    await EconomyService.instance.refresh(showLoading: false);
  }

  void _setBusy(bool value) {
    if (!mounted) return;
    setState(() {
      _busy = value;
      if (value) {
        _error = null;
        _notice = null;
      }
    });
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
            Icon(protected ? Icons.shield : Icons.shield_outlined, size: 38),
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
                        ? 'Online identity linked to ${user?.email ?? 'an email account'}.'
                        : 'Deleting the app or changing devices can make this guest inaccessible. Protect it before buying Coins.',
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
            Expanded(
              child: Text(text, style: TextStyle(color: foreground)),
            ),
          ],
        ),
      ),
    );
  }
}
