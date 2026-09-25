import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_services.dart';
import '../../core/settings_service.dart';
import '../../services/metadata/image_format.dart';

/// Spec §5/§39/§40/§41: location toggles, upload endpoint & timeouts, and
/// a Network Tests panel driving the server's X-Simulate header (§38) to
/// exercise 400/401/413/500/timeout/slow-network without needing a real
/// flaky connection.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsService _settings;
  late TextEditingController _urlCtrl;
  late TextEditingController _tokenCtrl;
  String _connectivityLabel = 'Checking…';
  String? _healthResult;

  @override
  void initState() {
    super.initState();
    _settings = context.read<AppServices>().settings;
    _urlCtrl = TextEditingController(text: _settings.serverBaseUrl);
    _tokenCtrl = TextEditingController(text: _settings.apiToken);
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    setState(() => _connectivityLabel = result.map((r) => r.name).join(', '));
  }

  Future<void> _checkHealth() async {
    final services = context.read<AppServices>();
    setState(() => _healthResult = 'Checking…');
    final ok = await services.uploadService.checkHealth();
    setState(() => _healthResult = ok ? 'Server reachable ✓' : 'Server NOT reachable ✗');
  }

  Future<void> _simulate(String header) async {
    final services = context.read<AppServices>();
    setState(() => _healthResult = 'Sending X-Simulate: $header …');
    final sw = Stopwatch()..start();
    final result = await services.uploadService.uploadBase64(
      imageBytes: const [0xFF, 0xD8, 0xFF, 0xD9], // minimal stub; simulate short-circuits before validation
      fileName: 'sim.jpg',
      format: ImageFormat.jpeg,
      simulateHeader: header,
    );
    sw.stop();
    setState(() => _healthResult =
        'X-Simulate $header → status=${result.statusCode} error=${result.errorCode ?? '-'} time=${sw.elapsedMilliseconds}ms');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Location', [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Location metadata'),
              subtitle: const Text('Embed GPS into captured images'),
              value: _settings.locationMetadataEnabled,
              onChanged: (v) async { await _settings.setLocationMetadataEnabled(v); setState(() {}); },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Require location before capture'),
              value: _settings.requireLocation,
              onChanged: (v) async { await _settings.setRequireLocation(v); setState(() {}); },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Maximum location age'),
              subtitle: Text('${_settings.maxLocationAgeSeconds} seconds'),
              trailing: SizedBox(
                width: 160,
                child: Slider(
                  value: _settings.maxLocationAgeSeconds.toDouble(),
                  min: 5, max: 120, divisions: 23,
                  onChanged: (v) async { await _settings.setMaxLocationAgeSeconds(v.round()); setState(() {}); },
                ),
              ),
            ),
          ]),
          _section('Server', [
            TextField(controller: _urlCtrl, decoration: const InputDecoration(labelText: 'Server base URL'), onSubmitted: (v) => _settings.setServerBaseUrl(v)),
            const SizedBox(height: 8),
            TextField(controller: _tokenCtrl, decoration: const InputDecoration(labelText: 'API token (optional)'), onSubmitted: (v) => _settings.setApiToken(v)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () async { await _settings.setServerBaseUrl(_urlCtrl.text); await _settings.setApiToken(_tokenCtrl.text); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved'))); }, child: const Text('Save'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton(onPressed: _checkHealth, child: const Text('Check /api/health'))),
            ]),
          ]),
          _section('Timeouts & Retries', [
            _numberRow('Connect timeout (s)', _settings.connectTimeoutSeconds, (v) => _settings.setConnectTimeoutSeconds(v)),
            _numberRow('Send timeout (s)', _settings.sendTimeoutSeconds, (v) => _settings.setSendTimeoutSeconds(v)),
            _numberRow('Receive timeout (s)', _settings.receiveTimeoutSeconds, (v) => _settings.setReceiveTimeoutSeconds(v)),
            _numberRow('Max upload retries', _settings.maxUploadRetries, (v) => _settings.setMaxUploadRetries(v)),
          ]),
          _section('Network Tests', [
            Text('Connectivity: $_connectivityLabel', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Text('Requires the server started with SIMULATE=true.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final h in ['400', '401', '413', '500', 'slow:2000', 'timeout'])
                OutlinedButton(onPressed: () => _simulate(h), child: Text(h)),
            ]),
            if (_healthResult != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_healthResult!)),
          ]),
        ],
      ),
    );
  }

  Widget _numberRow(String label, int value, Future<void> Function(int) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label)),
        IconButton(icon: const Icon(Icons.remove), onPressed: () async { await onChanged((value - 1).clamp(0, 999)); setState(() {}); }),
        Text('$value'),
        IconButton(icon: const Icon(Icons.add), onPressed: () async { await onChanged(value + 1); setState(() {}); }),
      ]),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...children,
        ]),
      ),
    );
  }
}
