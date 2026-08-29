import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../localization/app_strings.dart';
import '../../services/account_deletion_service.dart';
import '../../services/economy_service.dart';
import '../../services/firebase_session_service.dart';
import '../../services/player_profile_service.dart';
import '../../widgets/in_page_header.dart';

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
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
            final compact = constraints.maxHeight < 680 || keyboardOpen;
            final horizontal = constraints.maxWidth < 360 ? 12.0 : 20.0;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    keyboardOpen
                        ? 2
                        : compact
                        ? 6
                        : 12,
                    horizontal,
                    keyboardOpen
                        ? 4
                        : compact
                        ? 8
                        : 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!keyboardOpen)
                        InPageHeader(
                          title: context.tr('player_account'),
                          padding: EdgeInsets.only(bottom: compact ? 4 : 8),
                        ),
                      if (!keyboardOpen && !compact) ...[
                        _StatusCard(user: _user, compact: false),
                        const SizedBox(height: 10),
                      ],
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: _protected
                              ? _protectedCard(
                                  context,
                                  compact: compact,
                                  keyboardOpen: keyboardOpen,
                                )
                              : _accountForm(
                                  context,
                                  compact: compact,
                                  keyboardOpen: keyboardOpen,
                                ),
                        ),
                      ),
                      if (!keyboardOpen &&
                          (_error != null || _notice != null)) ...[
                        const SizedBox(height: 6),
                        _MessagePanel(
                          icon: _error != null
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
                          background: _error != null
                              ? scheme.errorContainer
                              : scheme.primaryContainer,
                          foreground: _error != null
                              ? scheme.onErrorContainer
                              : scheme.onPrimaryContainer,
                          text: _error ?? _notice!,
                          compact: compact,
                        ),
                      ],
                      if (!keyboardOpen) ...[
                        SizedBox(height: compact ? 4 : 8),
                        _AccountDataBar(
                          busy: _busy,
                          compact: compact,
                          onDelete: _deleteAccount,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _changeMode(bool signIn) {
    setState(() {
      _signInMode = signIn;
      _error = null;
      _notice = null;
      _confirm.clear();
    });
  }

  Widget _accountForm(
    BuildContext context, {
    required bool compact,
    required bool keyboardOpen,
  }) {
    final validEmail = RegExp(
      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
    ).hasMatch(_email.text.trim());
    final validPassword = _password.text.length >= 8;
    final matches = _signInMode || _password.text == _confirm.text;
    final canSubmit = validEmail && validPassword && matches && !_busy;
    final spacing = keyboardOpen
        ? 6.0
        : compact
        ? 8.0
        : 12.0;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(
          keyboardOpen
              ? 10
              : compact
              ? 12
              : 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!keyboardOpen) ...[
              Text(
                _signInMode
                    ? context.tr('sign_in_protected_account')
                    : context.tr('protect_current_guest'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: compact ? 18 : null,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 4),
                Text(
                  _signInMode
                      ? context.tr('sign_in_protected_account_body')
                      : context.tr('protect_current_guest_body'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              SizedBox(height: spacing),
              _AccountModeSelector(
                signInMode: _signInMode,
                enabled: !_busy,
                compact: compact,
                onChanged: _changeMode,
              ),
              SizedBox(height: spacing),
            ],
            TextField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: InputDecoration(
                isDense: compact,
                labelText: context.tr('email_address'),
                prefixIcon: const Icon(Icons.email_outlined),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            SizedBox(height: spacing),
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
                isDense: compact,
                labelText: context.tr('password'),
                helperText: keyboardOpen
                    ? null
                    : context.tr('password_min_chars'),
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _hidePassword
                      ? context.tr('show_password')
                      : context.tr('hide_password'),
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
              SizedBox(height: spacing),
              TextField(
                controller: _confirm,
                enabled: !_busy,
                obscureText: _hidePassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  isDense: compact,
                  labelText: context.tr('confirm_password'),
                  prefixIcon: const Icon(Icons.lock_reset_outlined),
                  border: const OutlineInputBorder(),
                  errorText: _confirm.text.isNotEmpty && !matches
                      ? context.tr('passwords_do_not_match')
                      : null,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: canSubmit ? (_) => _submit() : null,
              ),
            ],
            SizedBox(height: spacing),
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
                    ? context.tr('please_wait')
                    : _signInMode
                    ? context.tr('sign_in')
                    : context.tr('protect_account'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_signInMode && !keyboardOpen) ...[
              const SizedBox(height: 2),
              TextButton(
                onPressed: _busy || !validEmail ? null : _sendPasswordReset,
                child: Text(
                  context.tr('forgot_password'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!compact)
                Text(
                  context.tr('sign_in_switches_guest'),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _protectedCard(
    BuildContext context, {
    required bool compact,
    required bool keyboardOpen,
  }) {
    final user = _user!;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('account_protected'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: compact ? 18 : null,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              user.email ?? context.tr('protected_account'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: compact ? 4 : 8),
            ListTile(
              dense: compact,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                user.emailVerified
                    ? Icons.verified_user_outlined
                    : Icons.mark_email_unread_outlined,
              ),
              title: Text(
                user.emailVerified
                    ? context.tr('email_verified')
                    : context.tr('email_verification_required'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                user.emailVerified
                    ? context.tr('paid_coins_recoverable')
                    : context.tr('verify_email_before_buying'),
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!user.emailVerified) ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : _sendVerification,
                icon: const Icon(Icons.forward_to_inbox_outlined),
                label: Text(
                  context.tr('resend_verification_email'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(height: compact ? 4 : 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _refreshVerification,
                icon: const Icon(Icons.refresh),
                label: Text(
                  context.tr('verified_refresh'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            SizedBox(height: compact ? 2 : 6),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 2,
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : _sendPasswordReset,
                  icon: const Icon(Icons.password_outlined),
                  label: Text(context.tr('send_password_reset_email')),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _signOutToGuest,
                  icon: const Icon(Icons.logout_outlined),
                  label: Text(context.tr('sign_out_on_device')),
                ),
              ],
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
        if (!mounted) return;
        _notice = context.tr('protected_player_account_opened');
      } else {
        await FirebaseSessionService.protectCurrentAccount(
          email: _email.text,
          password: _password.text,
        );
        await _refreshServices();
        if (!mounted) return;
        _notice = context.tr('account_protected_verify_email');
      }
      _password.clear();
      _confirm.clear();
    } on FirebaseSessionException catch (error) {
      if (!mounted) return;
      _error = UserSafeError.message(context, error);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _sendVerification() => _run(
    FirebaseSessionService.sendVerificationEmail,
    context.tr('verification_email_sent'),
  );

  Future<void> _refreshVerification() => _run(
    () async {
      await FirebaseSessionService.reloadCurrentUser();
      await _refreshServices();
    },
    FirebaseSessionService.currentUser?.emailVerified == true
        ? context.tr('email_verified_notice')
        : context.tr('account_refreshed'),
  );

  Future<void> _sendPasswordReset() => _run(
    () => FirebaseSessionService.sendPasswordReset(_email.text),
    context.tr('password_reset_email_sent'),
  );

  Future<void> _signOutToGuest() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('sign_out_question')),
        content: Text(context.tr('sign_out_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.tr('sign_out')),
          ),
        ],
      ),
    );
    if (approved != true) return;
    if (!mounted) return;
    await _run(() async {
      await FirebaseSessionService.signOutToGuest();
      await _refreshServices();
      _email.clear();
      _password.clear();
      _confirm.clear();
    }, context.tr('guest_player_created'));
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
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            title: Text(
              context.tr('delete_player_account_question'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr('delete_player_account_warning'),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: confirmation,
                    autofocus: true,
                    autocorrect: false,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: context.tr('type_delete'),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  if (_protected) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: password,
                      obscureText: hidden,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: context.tr('current_password'),
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
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(context.tr('cancel')),
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
                child: Text(context.tr('delete_permanently')),
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
        SnackBar(content: Text(context.tr('player_account_deleted'))),
      );
    } on AccountDeletionException catch (error) {
      if (!mounted) return;
      _error = UserSafeError.message(context, error);
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
      if (!mounted) return;
      _error = UserSafeError.message(context, error);
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

class _AccountModeSelector extends StatelessWidget {
  const _AccountModeSelector({
    required this.signInMode,
    required this.enabled,
    required this.compact,
    required this.onChanged,
  });

  final bool signInMode;
  final bool enabled;
  final bool compact;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ModeTile(
            selected: !signInMode,
            enabled: enabled,
            icon: Icons.shield_outlined,
            label: context.tr('protect_current'),
            compact: compact,
            onTap: () => onChanged(false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ModeTile(
            selected: signInMode,
            enabled: enabled,
            icon: Icons.login_outlined,
            label: context.tr('sign_in'),
            compact: compact,
            onTap: () => onChanged(true),
          ),
        ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.selected,
    required this.enabled,
    required this.icon,
    required this.label,
    required this.compact,
    required this.onTap,
  });

  final bool selected;
  final bool enabled;
  final IconData icon;
  final String label;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.secondaryContainer : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 8 : 11,
          ),
          child: Row(
            children: [
              Icon(icon, size: compact ? 18 : 21),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 11 : 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: compact ? 16 : 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.user, required this.compact});

  final User? user;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final protected = user != null && !user!.isAnonymous;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: protected ? scheme.primaryContainer : scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: EdgeInsets.all(compact ? 10 : 14),
        child: Row(
          children: [
            Icon(
              protected ? Icons.shield : Icons.shield_outlined,
              size: compact ? 28 : 34,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    protected
                        ? context.tr('recoverable_account')
                        : context.tr('guest_account'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 2),
                    Text(
                      protected
                          ? context.tr('online_identity_linked', <Object>[
                              user?.email ?? context.tr('email_account'),
                            ])
                          : context.tr('guest_account_risk'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountDataBar extends StatelessWidget {
  const _AccountDataBar({
    required this.busy,
    required this.compact,
    required this.onDelete,
  });

  final bool busy;
  final bool compact;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: compact ? 42 : 50,
      child: OutlinedButton.icon(
        onPressed: busy ? null : onDelete,
        style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
        icon: const Icon(Icons.delete_forever_outlined),
        label: Text(
          context.tr('delete_player_account'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
    required this.compact,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 7 : 10,
        ),
        child: Row(
          children: [
            Icon(icon, color: foreground, size: compact ? 18 : 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
