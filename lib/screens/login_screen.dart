import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/auth_service.dart';

/// Entrar ou criar conta (Google ou e-mail e senha).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth, required this.onSignedIn});
  final AuthService auth;

  /// Chamado após login/cadastro, com se o usuário aceitou os termos nesta tela.
  final Future<void> Function({required bool acceptedTerms}) onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _accepted = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {required bool needsTerms}) async {
    if (needsTerms && !_accepted) {
      setState(() => _error = 'Para continuar, aceite a política de privacidade.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await widget.onSignedIn(acceptedTerms: _accepted);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Erro inesperado: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitEmail() async {
    if (!_form.currentState!.validate()) return;
    await _run(
      () => _creating
          ? widget.auth.createAccount(_name.text, _email.text, _password.text)
          : widget.auth.signInWithEmail(_email.text, _password.text),
      needsTerms: _creating,
    );
  }

  Future<void> _reset() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Digite seu e-mail acima para recuperar a senha.');
      return;
    }
    try {
      await widget.auth.sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enviamos um link de recuperação para $email.')));
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
            children: [
              Icon(Icons.directions_run, size: 56, color: c.primary),
              const SizedBox(height: 12),
              Text('Fast run', textAlign: TextAlign.center, style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Seu plano de corrida, ajustado toda semana.', textAlign: TextAlign.center, style: t.bodyLarge),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _busy ? null : () => _run(widget.auth.signInWithGoogle, needsTerms: _creating),
                icon: const Icon(Icons.account_circle),
                label: const Text('Continuar com Google'),
              ),
              const SizedBox(height: 20),
              Row(children: [
                const Expanded(child: Divider()),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('ou com e-mail', style: t.bodySmall)),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 16),
              if (_creating) ...[
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(labelText: 'Nome', border: OutlineInputBorder()),
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Informe seu nome' : null,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
                validator: (v) => RegExp(r'^\S+@\S+\.\S+$').hasMatch((v ?? '').trim()) ? null : 'E-mail inválido',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: !_showPassword,
                autofillHints: [_creating ? AutofillHints.newPassword : AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Senha',
                  helperText: _creating ? 'Pelo menos 8 caracteres' : null,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? 'Ocultar senha' : 'Mostrar senha',
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                    icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
                validator: (v) => (v ?? '').length < (_creating ? 8 : 1) ? (_creating ? 'Use pelo menos 8 caracteres' : 'Informe a senha') : null,
                onFieldSubmitted: (_) => _submitEmail(),
              ),
              if (_creating) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _accepted,
                  onChanged: (v) => setState(() => _accepted = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text.rich(TextSpan(children: [
                    const TextSpan(text: 'Li e aceito a '),
                    TextSpan(
                      text: 'política de privacidade',
                      style: TextStyle(color: c.primary, decoration: TextDecoration.underline),
                      recognizer: TapGestureRecognizer()..onTap = () => _showPolicy(context),
                    ),
                    const TextSpan(text: ' e o uso dos meus dados de treino para montar o plano.'),
                  ])),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: c.error)),
              ],
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _busy ? null : _submitEmail,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_creating ? 'Criar conta' : 'Entrar'),
              ),
              const SizedBox(height: 8),
              if (!_creating) TextButton(onPressed: _busy ? null : _reset, child: const Text('Esqueci minha senha')),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _creating = !_creating;
                          _error = null;
                        }),
                child: Text(_creating ? 'Já tenho conta: entrar' : 'Não tem conta? Criar conta'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPolicy(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Política de privacidade'),
        content: const SelectableText(
          'Resumo: lemos seus treinos do Health Connect e dos arquivos que você importar para mostrar estatísticas e '
          'montar seu plano. Seu objetivo, plano e treinos importados ficam na sua conta (Google Firebase). '
          'Para gerar o plano com IA, um resumo dos treinos (sem localização) é enviado ao nosso servidor e à '
          'Anthropic. Você pode excluir a conta e os dados a qualquer momento.\n\nTexto completo:\n${AppConfig.privacyUrl}',
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(const ClipboardData(text: AppConfig.privacyUrl)),
            child: const Text('Copiar link'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
        ],
      ),
    );
  }
}

/// Mostrada após login com Google na primeira vez (aceite ainda não registrado).
class TermsGate extends StatefulWidget {
  const TermsGate({super.key, required this.onAccept, required this.onDecline});
  final Future<void> Function() onAccept;
  final VoidCallback onDecline;

  @override
  State<TermsGate> createState() => _TermsGateState();
}

class _TermsGateState extends State<TermsGate> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 24),
            Text('Antes de começar', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const Text(
              'O Fast run usa seus dados de treino (Health Connect e arquivos importados) para mostrar estatísticas e '
              'montar seu plano. Objetivo, plano e treinos importados ficam salvos na sua conta. Para gerar o plano com '
              'IA, um resumo dos treinos, sem localização, é enviado ao nosso servidor e à Anthropic.',
            ),
            const SizedBox(height: 12),
            SelectableText('Política completa: ${AppConfig.privacyUrl}', style: t.bodySmall),
            const Spacer(),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      await widget.onAccept();
                    },
              child: const Text('Aceito e quero continuar'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _busy ? null : widget.onDecline, child: const Text('Não aceito (sair)')),
          ]),
        ),
      ),
    );
  }
}
