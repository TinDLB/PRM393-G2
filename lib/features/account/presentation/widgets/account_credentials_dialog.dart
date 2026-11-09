import 'package:flutter/material.dart';

import '../../repository/account_repository.dart';

class AccountCredentialsDialog extends StatefulWidget {
  const AccountCredentialsDialog({
    super.key,
    required this.repository,
    this.createAccount = false,
    this.fullScreen = false,
  });

  final AccountRepository repository;
  final bool createAccount;
  final bool fullScreen;

  @override
  State<AccountCredentialsDialog> createState() =>
      _AccountCredentialsDialogState();
}

class _AccountCredentialsDialogState extends State<AccountCredentialsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _resetTokenController = TextEditingController();
  final _newPasswordController = TextEditingController();
  bool _isRegistering = false;
  bool _isResettingPassword = false;
  bool _resetRequested = false;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _isRegistering = widget.createAccount;
    widget.repository.addListener(_onRepositoryChanged);
  }

  void _onRepositoryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.repository.removeListener(_onRepositoryChanged);
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _resetTokenController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    if (_isResettingPassword && !_resetRequested) {
      await widget.repository.requestPasswordReset(
        _emailController.text.trim(),
      );
      if (widget.repository.errorMessage == null) {
        _resetRequested = true;
        _successMessage = 'Nếu email thuộc tài khoản hợp lệ, mã đặt lại đã được gửi. Hãy kiểm tra hộp thư và thư rác.';
      }
    } else if (_isResettingPassword) {
      await widget.repository.resetPassword(
        email: _emailController.text.trim(),
        token: _resetTokenController.text.trim(),
        newPassword: _newPasswordController.text,
      );
      if (widget.repository.errorMessage == null) {
        _isResettingPassword = false;
        _resetRequested = false;
        _isRegistering = false;
        _successMessage = 'Đổi mật khẩu thành công. Hãy đăng nhập lại.';
      }
    } else if (_isRegistering) {
      await widget.repository.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _nameController.text.trim(),
      );
      if (widget.repository.errorMessage == null) {
        _nameController.clear();
        _emailController.clear();
        _passwordController.clear();
        _successMessage = 'Tạo tài khoản thành công. Chọn “Đã có tài khoản? Đăng nhập” để đăng nhập.';
      }
    } else {
      await widget.repository.signInWithPassword(
        _emailController.text.trim(),
        _passwordController.text,
      );
    }
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (widget.repository.currentUser != null && !widget.fullScreen) {
      Navigator.of(context).pop();
    } else if (widget.repository.currentUser == null) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final titleText = _isResettingPassword
        ? 'Đặt lại mật khẩu'
        : _isRegistering
        ? 'Tạo tài khoản'
        : 'Đăng nhập';
    final title = Text(titleText);
    final form = Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_successMessage case final message?) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, color: colors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(color: colors.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_isRegistering && !_isResettingPassword) ...[
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Tên hiển thị'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Nhập tên hiển thị.'
                  : null,
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (value) {
              final email = value?.trim() ?? '';
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                return 'Nhập địa chỉ email hợp lệ.';
              }
              return null;
            },
          ),
          if (!_isResettingPassword) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              autofillHints: [
                _isRegistering
                    ? AutofillHints.newPassword
                    : AutofillHints.password,
              ],
              decoration: InputDecoration(
                labelText: 'Mật khẩu',
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) => (value ?? '').length < 8
                  ? 'Mật khẩu cần ít nhất 8 ký tự.'
                  : null,
            ),
          ],
          if (_isResettingPassword && _resetRequested) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _resetTokenController,
              decoration: const InputDecoration(
                labelText: 'Mã đặt lại từ email',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Nhập mã đã nhận qua email.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _newPasswordController,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'Mật khẩu mới'),
              validator: (value) => (value ?? '').length < 8
                  ? 'Mật khẩu cần ít nhất 8 ký tự.'
                  : null,
            ),
          ],
          if (widget.repository.errorMessage case final error?) ...[
            const SizedBox(height: 12),
            Text(error, style: TextStyle(color: colors.error)),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_isResettingPassword && !_isRegistering)
                  TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => setState(() {
                            _isResettingPassword = true;
                            _resetRequested = false;
                            _successMessage = null;
                          }),
                    child: const Text('Quên mật khẩu?'),
                  ),
                if (!_isResettingPassword)
                  TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => setState(() {
                            _isRegistering = !_isRegistering;
                            _successMessage = null;
                          }),
                    child: Text(
                      _isRegistering
                          ? 'Đã có tài khoản? Đăng nhập'
                          : 'Chưa có tài khoản? Đăng ký',
                    ),
                  ),
                if (_isResettingPassword)
                  TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => setState(() {
                            _isResettingPassword = false;
                            _resetRequested = false;
                            _successMessage = null;
                          }),
                    child: const Text('Quay lại đăng nhập'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    final submitButton = FilledButton(
      onPressed: _isSubmitting ? null : _submit,
      child: _isSubmitting
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              _isResettingPassword
                  ? _resetRequested
                        ? 'Đổi mật khẩu'
                        : 'Gửi mã đặt lại'
                  : _isRegistering
                  ? 'Đăng ký'
                  : 'Đăng nhập',
            ),
    );

    if (widget.fullScreen) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tài khoản')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              size: 38,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          titleText,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isResettingPassword
                              ? 'Nhập email đã đăng ký để khôi phục quyền truy cập.'
                              : _isRegistering
                              ? 'Tạo tài khoản để lưu video và quản lý kênh của bạn.'
                              : 'Đăng nhập để tiếp tục xem và đồng bộ thư viện video.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        form,
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: submitButton,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      title: title,
      content: SingleChildScrollView(child: form),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        submitButton,
      ],
    );
  }
}
