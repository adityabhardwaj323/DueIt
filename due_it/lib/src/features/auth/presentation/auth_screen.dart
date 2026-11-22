import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

const _authCallbackUrl = 'com.dueit.due_it://auth-callback';

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isLogin = true;
  bool _obscurePassword = true;

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both email and password')),
      );
      return;
    }
    if (!email.contains('@') ||
        !email.substring(email.indexOf('@') + 1).contains('.')) {
      _showMessage('Enter a valid email address.', isError: true);
      return;
    }
    if (!_isLogin && password.length < 6) {
      _showMessage('Password must be at least 6 characters.', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isLogin) {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      } else {
        final response = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: kIsWeb ? null : _authCallbackUrl,
        );
        if (!mounted) return;

        if (response.session != null) {
          _showMessage('Account created. You are now signed in.');
        } else if (response.user?.identities?.isEmpty ?? false) {
          _showMessage(
            'We could not create a new account with this email. Try signing in, '
            'or check that you used the correct address.',
            isError: true,
          );
        } else {
          setState(() => _isLogin = true);
          _showMessage(
            'Check your email for a confirmation link. Confirm your address '
            'before signing in.',
          );
        }
      }
    } on AuthException catch (error) {
      if (mounted) {
        final message = switch (error.code) {
          'over_email_send_rate_limit' || 'over_request_rate_limit' =>
            'Too many confirmation emails have been requested. Wait before '
                'trying again, then use the newest email. If you already have '
                'an account, switch to Sign In.',
          'email_not_confirmed' =>
            'Please confirm your email before signing in. You can request a '
                'new confirmation email below.',
          'user_not_found' || 'invalid_credentials' when _isLogin =>
            'No matching account was found. Check the email address and '
                'password. If you just signed up, confirm your email first.',
          _ => error.message,
        };
        _showMessage(message, isError: true);
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Could not complete authentication. Check your connection and try again. ($error)',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final launched = await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : 'com.dueit.due_it://auth-callback',
        // Some Google Workspace accounts require the full userinfo email
        // scope to return the account email during Supabase's callback.
        scopes:
            'openid email profile https://www.googleapis.com/auth/userinfo.email',
      );
      if (!launched && mounted) {
        _showMessage(
          'Could not open Google sign-in. Please try again.',
          isError: true,
        );
      }
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Google sign-in failed. Check your connection and try again. ($error)',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendConfirmation() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showMessage('Enter your email address first.', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: kIsWeb ? null : _authCallbackUrl,
      );
      if (mounted) {
        _showMessage(
          'If this address needs confirmation, a new email has been sent.',
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        final message =
            error.code == 'over_email_send_rate_limit' ||
                error.code == 'over_request_rate_limit'
            ? 'Too many confirmation emails have been requested. Wait before '
                  'trying again, then check your inbox and spam folder.'
            : error.message;
        _showMessage(message, isError: true);
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Could not resend the email. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showMessage('Enter your email address first.', isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: kIsWeb ? null : 'com.dueit.due_it://reset-password',
      );
      if (mounted) {
        _showMessage(
          'If an account exists for that email, a reset link has been sent.',
        );
      }
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } catch (_) {
      if (mounted)
        _showMessage(
          'Could not request a password reset. Try again.',
          isError: true,
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // App Logo / Icon Header
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 42,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'DueIt',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isLogin
                      ? 'Sign in to access your notes, tasks & dues'
                      : 'Create an account to get started',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 32),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: 'Email Address',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 20,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          obscureText: _obscurePassword,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _isLoading ? null : _submit,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isLogin ? 'Sign In' : 'Create Account',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                'or continue with',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _signInWithGoogle,
                          icon: const Text(
                            'G',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF4285F4),
                            ),
                          ),
                          label: const Text('Continue with Google'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            side: BorderSide(color: theme.colorScheme.outlineVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isLogin = !_isLogin;
                    });
                  },
                  child: Text(
                    _isLogin
                        ? 'Don\'t have an account? Sign Up'
                        : 'Already have an account? Sign In',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                if (_isLogin)
                  TextButton(
                    onPressed: _isLoading ? null : _resendConfirmation,
                    child: Text(
                      'Resend confirmation email',
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                  ),
                if (_isLogin)
                  TextButton(
                    onPressed: _isLoading ? null : _forgotPassword,
                    child: Text(
                      'Forgot password?',
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key, required this.onComplete});
  final VoidCallback onComplete;

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _save() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'Use at least 8 characters for your password.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'The passwords do not match.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _password.text),
      );
      if (mounted) widget.onComplete();
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Password update failed. Reopen the newest reset link and try again.',
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose a new password')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _confirm,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _save,
                child: Text(_loading ? 'Saving…' : 'Update password'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
