import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/external_url_launcher.dart';
import '../../../data/services/moji_weather_service.dart';
import '../../../data/services/weather_api_config.dart';

class WeatherApiSettingsScreen extends StatefulWidget {
  const WeatherApiSettingsScreen({super.key});

  @override
  State<WeatherApiSettingsScreen> createState() =>
      _WeatherApiSettingsScreenState();
}

class _WeatherApiSettingsScreenState extends State<WeatherApiSettingsScreen> {
  late final TextEditingController _keyController;
  bool _obscureKey = true;
  bool _isSaving = false;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(
      text: WeatherApiConfigStore.hasApiKey ? WeatherApiConfigStore.apiKey : '',
    );
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    setState(() => _isSaving = true);
    try {
      await WeatherApiConfigStore.save(_keyController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_keyController.text.trim().isEmpty
              ? '已清除天气 API Key'
              : '天气 API Key 已保存'),
        ),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    final result = await MojiWeatherService.testConnection(
      apiKey: _keyController.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? Colors.green : Colors.red,
        ),
      );
      setState(() => _isTesting = false);
    }
  }

  Future<void> _clearKey() async {
    _keyController.clear();
    await _saveKey();
  }

  Future<void> _openWebPage(String url) async {
    final opened = await ExternalUrlLauncher.open(url);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开网页，请检查浏览器是否可用')),
      );
    }
  }

  Widget _buildLink(String title, String subtitle, String url) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(AppIcons.open_in_new, color: Color(0xFF1E88E5)),
      title: Text(title),
      subtitle: Text(subtitle,
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
      trailing: const Icon(AppIcons.chevron_right, size: 18),
      onTap: () => _openWebPage(url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isConfigured = _keyController.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('天气服务设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _keyController,
            obscureText: _obscureKey,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '墨迹天气 API Key（可选）',
              hintText: '留空使用匿名请求',
              prefixIcon: const Icon(AppIcons.key_outlined),
              suffixIcon: IconButton(
                tooltip: _obscureKey ? '显示 Key' : '隐藏 Key',
                icon: Icon(_obscureKey
                    ? AppIcons.visibility_outlined
                    : AppIcons.visibility_off_outlined),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                isConfigured
                    ? AppIcons.check_circle_outline
                    : AppIcons.info_outline,
                size: 19,
                color: isConfigured ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(isConfigured
                    ? '已配置，将使用墨迹天气实时和历史数据'
                    : '未配置 Key，将尝试墨迹天气匿名查询'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _isSaving || _isTesting ? null : _saveKey,
            icon: const Icon(AppIcons.save_outlined),
            label: const Text('保存 Key'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isSaving || _isTesting ? null : _testConnection,
            icon: _isTesting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(AppIcons.network_check_outlined),
            label: const Text('测试连接（北京）'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed:
                _isSaving || _isTesting || !isConfigured ? null : _clearKey,
            icon: const Icon(AppIcons.delete_outline),
            label: const Text('清除本机 Key'),
          ),
          const SizedBox(height: 12),
          Text(
            '接口地址和请求参数已按 ApiZero 墨迹天气协议固定。Key 为可选项，未配置时使用匿名请求；如配置 Key，仅保存于本机安全存储。历史天气快照按城市和日期保存在本机。',
            style: TextStyle(
                fontSize: 12, color: colors.onSurfaceVariant, height: 1.45),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          const Text('详细配置教程',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          const Text('1. ApiZero 墨迹天气接口支持匿名调用，个人使用可直接测试。',
              style: TextStyle(height: 1.5)),
          const SizedBox(height: 10),
          const Text('2. 如匿名额度不足，申请个人 Key 后粘贴到上方保存。',
              style: TextStyle(height: 1.5)),
          const SizedBox(height: 10),
          const Text('3. 测试成功后，环境行情会按当前城市读取实时天气，并保存可用的历史快照。',
              style: TextStyle(height: 1.5)),
          const SizedBox(height: 16),
          const Text('相关网页',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          _buildLink('ApiZero 墨迹天气接口文档', '查看实况、历史天气和返回字段',
              'https://apizero.cn/aidocs/moji-weather/raw.md'),
          _buildLink('ApiZero 墨迹天气说明页', '查看接口额度、状态和在线调试',
              'https://apizero.cn/aidocs/moji-weather'),
          _buildLink('ApiZero Key 管理', '申请或管理个人 API Key',
              'https://apizero.cn/account/keys'),
        ],
      ),
    );
  }
}
