import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';

import '../../../data/services/amap_location_service.dart';
import '../../../data/services/amap_key_store.dart';
import '../../../core/utils/external_url_launcher.dart';

class AmapKeySettingsScreen extends StatefulWidget {
  const AmapKeySettingsScreen({super.key});

  @override
  State<AmapKeySettingsScreen> createState() => _AmapKeySettingsScreenState();
}

class _AmapKeySettingsScreenState extends State<AmapKeySettingsScreen> {
  late final TextEditingController _keyController;
  bool _obscureKey = true;
  bool _isSaving = false;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(
      text: AmapKeyStore.hasUserKey ? AmapKeyStore.currentKey : '',
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
      await AmapKeyStore.save(_keyController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _keyController.text.trim().isEmpty ? '已清除高德 Key' : '高德 Key 已保存',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _clearKey() async {
    _keyController.clear();
    await _saveKey();
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    final result = await AmapLocationService.testConnection(
      key: _keyController.text,
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

  Future<void> _openWebPage(String url) async {
    final opened = await ExternalUrlLauncher.open(url);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开网页，请检查浏览器是否可用')));
    }
  }

  Widget _buildGuideStep({
    required int number,
    required String title,
    required String description,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: const Color(0xFFFF5A24),
            child: Text(
              '$number',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebLink({
    required IconData icon,
    required String title,
    required String subtitle,
    required String url,
  }) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: const Color(0xFFFF5A24)),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
      ),
      trailing: const Icon(AppIcons.open_in_new, size: 18),
      onTap: () => _openWebPage(url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isConfigured = _keyController.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('地图服务设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _keyController,
            obscureText: _obscureKey,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '高德 Web 服务 Key',
              hintText: '请输入个人申请的 Web 服务 Key',
              prefixIcon: const Icon(AppIcons.key_outlined),
              suffixIcon: IconButton(
                tooltip: _obscureKey ? '显示 Key' : '隐藏 Key',
                icon: Icon(
                  _obscureKey
                      ? AppIcons.visibility_outlined
                      : AppIcons.visibility_off_outlined,
                ),
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
                size: 18,
                color: isConfigured ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Text(isConfigured ? '已配置，将使用高德真实地址和加油站数据' : '未配置，地图不显示真实服务数据'),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _isSaving || _isTesting ? null : _saveKey,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppIcons.save_outlined),
            label: const Text('保存 Key'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isSaving || _isTesting ? null : _testConnection,
            icon: _isTesting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppIcons.network_check_outlined),
            label: const Text('测试连接'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isSaving || _isTesting || !isConfigured
                ? null
                : _clearKey,
            icon: const Icon(AppIcons.delete_outline),
            label: const Text('清除本机 Key'),
          ),
          const SizedBox(height: 12),
          Text(
            'Key 保存在本机安全存储中。高德 Key 仍应在控制台设置调用额度和安全限制。',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            '详细配置教程',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          _buildGuideStep(
            number: 1,
            title: '注册并完成个人认证',
            description: '打开高德开放平台，使用手机号注册并按页面提示完成个人开发者认证。',
          ),
          _buildGuideStep(
            number: 2,
            title: '创建应用',
            description: '进入控制台的“应用管理”，点击“创建新应用”，应用名称可填写 BearFuel。',
          ),
          _buildGuideStep(
            number: 3,
            title: '添加 Web 服务 Key',
            description: '进入刚创建的应用，点击“添加 Key”。服务平台选择“Web 服务”，提交后复制 Key。',
          ),
          _buildGuideStep(
            number: 4,
            title: '回到本页保存并验证',
            description: '将复制的 Key 粘贴到上方输入框并保存。返回地图选站后，应用会请求真实地址和周边加油站数据。',
          ),
          const SizedBox(height: 8),
          const Text(
            '相关网页',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          _buildWebLink(
            icon: AppIcons.dashboard_outlined,
            title: '高德开放平台控制台',
            subtitle: '注册、认证、创建应用和查看 Key',
            url: 'https://console.amap.com/',
          ),
          _buildWebLink(
            icon: AppIcons.menu_book_outlined,
            title: 'Web 服务 Key 申请教程',
            subtitle: '高德官方创建应用与 Key 指引',
            url: 'https://lbs.amap.com/api/webservice/create-project-and-key',
          ),
          _buildWebLink(
            icon: AppIcons.verified_user_outlined,
            title: '个人开发者认证说明',
            subtitle: '高德官方认证帮助页面',
            url: 'https://lbs.amap.com/faq/account/certification/39670',
          ),
          _buildWebLink(
            icon: AppIcons.gavel_outlined,
            title: '高德开放平台服务协议',
            subtitle: '使用前请了解服务范围与调用限制',
            url: 'https://lbs.amap.com/pages/terms/',
          ),
        ],
      ),
    );
  }
}
