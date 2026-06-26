import 'package:flutter/material.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_auth/at_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _loading = false;
  String? _error;

  static const _namespace = 'fynn';
  static const _rootDomain = 'root.atsign.org';
  static const _registrarUrl = 'my.atsign.com';
  static const _registrarApiKey = '5f93a2fa-2e3b-4332-9924-c29cc6e164ba';

  Future<void> _setupAtClient(String atsign, AuthResponse response) async {
    final appDir = await getApplicationSupportDirectory();
    final prefs = AtClientPreference()
      ..rootDomain = _rootDomain
      ..namespace = _namespace
      ..hiveStoragePath = '${appDir.path}/hive'
      ..commitLogPath = '${appDir.path}/commitLog';

    await AtClientManager.getInstance().setCurrentAtSign(
      atsign,
      _namespace,
      prefs,
      atChops: response.atChops,
      atLookUp: response.atLookUp,
    );
  }

  void _setError(String? msg) => setState(() => _error = msg);
  void _setLoading(bool v) => setState(() => _loading = v);

  // ── 1. Login from Keychain ──────────────────────────────────────────────

  Future<void> _loginFromKeychain() async {
    _setError(null);
    _setLoading(true);
    try {
      final atsigns = await KeychainStorage().getAllAtsigns();
      if (!mounted) return;
      if (atsigns.isEmpty) {
        _setError(
          'No @signs found in keychain. Upload a .atKeys file or register a new @sign.',
        );
        return;
      }

      final authReq = await AtSignSelectionDialog.show(
        context,
        existingAtSigns: atsigns,
      );
      if (authReq == null || !mounted) return;

      final atsign = authReq.atSign;
      final authRequest = AtAuthRequest(atsign, atKeysIo: KeychainAtKeysIo());
      final response = await PkamDialog.show(context, request: authRequest);
      if (response == null || !mounted) return;

      await _setupAtClient(atsign, response);
      _goHome();
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  // ── 2. Register new @sign (Registrar flow) ──────────────────────────────

  Future<void> _registerNewAtsign() async {
    _setError(null);
    _setLoading(true);
    try {
      final registrar = RegistrarService(
        registrarUrl: _registrarUrl,
        apiKey: _registrarApiKey,
      );

      if (!mounted) return;
      final authReq = await AtSignSelectionDialog.show(context);
      if (authReq == null || !mounted) return;

      final atsign = authReq.atSign;
      final onboardingRequest = AtOnboardingRequest(atsign);

      final cramKey = await RegistrarCramDialog.show(
        context,
        onboardingRequest,
        registrar: registrar,
      );
      if (cramKey == null || !mounted) return;

      final response = await CramDialog.show(
        context,
        request: onboardingRequest,
        cramKey: cramKey,
      );
      if (response == null || !mounted) return;

      await _setupAtClient(atsign, response);
      _goHome();
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  // ── 3. APKAM enrollment ─────────────────────────────────────────────────

  Future<void> _apkamEnrollment() async {
    _setError(null);
    _setLoading(true);
    try {
      if (!mounted) return;
      final authReq = await AtSignSelectionDialog.show(context);
      if (authReq == null || !mounted) return;

      final atsign = authReq.atSign;
      final enrollmentResponse = await ApkamActivationDialog.show(
        context,
        atSign: atsign,
        rootDomain: AtRootDomain.atsignDomain,
        appName: 'Fynn',
        deviceName: 'this_device',
        namespaces: {_namespace: 'rw'},
      );
      if (enrollmentResponse == null || !mounted) return;

      final authRequest = AtAuthRequest(
        atsign,
        atAuthKeys: enrollmentResponse.atAuthKeys,
      );
      final response = await PkamDialog.show(context, request: authRequest);
      if (response == null || !mounted) return;

      await _setupAtClient(atsign, response);
      _goHome();
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  // ── 4. Login via .atKeys file ───────────────────────────────────────────

  Future<void> _loginWithFile() async {
    _setError(null);
    _setLoading(true);
    try {
      if (!mounted) return;
      final fileIo = await AtKeysFileDialog.show(context);
      if (fileIo == null || !mounted) return;

      // Ask user for @sign — FileAtKeysIo doesn't expose the file path
      final controller = TextEditingController();
      final atsignInput = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text(
            'Enter Your @sign',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: '@alice',
              hintStyle: TextStyle(color: Colors.white38),
            ),
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (atsignInput == null || atsignInput.isEmpty || !mounted) return;

      final atsign = atsignInput.startsWith('@')
          ? atsignInput
          : '@$atsignInput';

      final authRequest = AtAuthRequest(atsign, atKeysIo: fileIo);
      final response = await PkamDialog.show(
        context,
        request: authRequest,
        backupKeys: [KeychainAtKeysIo()],
      );
      if (response == null || !mounted) return;

      await _setupAtClient(atsign, response);
      _goHome();
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Fynn',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF3B82F6),
                              letterSpacing: -0.5,
                            ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 36),

                  Text(
                    'Sign In',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Choose how you\'d like to authenticate.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white60,
                        ),
                  ),

                  const SizedBox(height: 32),

                  if (_error != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Colors.redAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_loading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: CircularProgressIndicator(
                          color: Color(0xFF3B82F6),
                        ),
                      ),
                    )
                  else ...[
                    _AuthOption(
                      icon: Icons.lock_outline_rounded,
                      title: 'Sign in with saved @sign',
                      subtitle: 'Use an @sign already on this device',
                      onTap: _loginFromKeychain,
                    ),
                    const SizedBox(height: 12),
                    _AuthOption(
                      icon: Icons.upload_file_rounded,
                      title: 'Upload .atKeys file',
                      subtitle: 'Select your @sign_key.atKeys backup file',
                      onTap: _loginWithFile,
                    ),
                    const SizedBox(height: 12),
                    _AuthOption(
                      icon: Icons.add_circle_outline_rounded,
                      title: 'Register a new @sign',
                      subtitle: 'Create and activate an @sign via the registrar',
                      onTap: _registerNewAtsign,
                    ),
                    const SizedBox(height: 12),
                    _AuthOption(
                      icon: Icons.devices_rounded,
                      title: 'Authorize this device (APKAM)',
                      subtitle: 'Approve access from an already-authorized device',
                      onTap: _apkamEnrollment,
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
}

class _AuthOption extends StatelessWidget {
  const _AuthOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFF3B82F6), size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white38,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
