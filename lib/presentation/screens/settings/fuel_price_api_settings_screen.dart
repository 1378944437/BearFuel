import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/external_url_launcher.dart';
import '../../../data/services/apizero_fuel_price_service.dart';
import '../../../data/services/fuel_price_api_config.dart';

class FuelPriceApiSettingsScreen extends StatefulWidget {
  const FuelPriceApiSettingsScreen({super.key});

  @override
  State<FuelPriceApiSettingsScreen> createState() =>
      _FuelPriceApiSettingsScreenState();
}

class _FuelPriceApiSettingsScreenState
    extends State<FuelPriceApiSettingsScreen> {
  late final TextEditingController _keyController;
  bool _obscureKey = true;
  bool _isSaving = false;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(
      text: FuelPriceApiConfigStore.hasApiKey
          ? FuelPriceApiConfigStore.apiKey
          : '',
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
      await FuelPriceApiConfigStore.save(_keyController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_keyController.text.trim().isEmpty
              ? '已清除 ApiZero Key'
              : 'ApiZero Key 已保存'),
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

  Future<void> _clearKey() async {
    _keyController.clear();
    await _saveKey();
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    final result = await ApiZeroFuelPriceService.testConnection(
      province: '北京',
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

  Future<void> _openWebPage(String url) async {
    final opened = await ExternalUrlLauncher.open(url);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开网页，请检查浏览器是否可用')),
      );
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
            backgroundColor: const Color(0xFF1E88E5),
            child: Text('$number',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(description,
                    style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                        height: 1.45)),
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
      leading: Icon(icon, color: const Color(0xFF1E88E5)),
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
      appBar: AppBar(title: const Text('实时油价服务设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _keyController,
            obscureText: _obscureKey,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'ApiZero 油价 API Key（可选）',
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
                    : AppIcons.warning_amber,
                size: 19,
                color: isConfigured ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isConfigured
                      ? '已配置，将使用 ApiZero 实时油价与调价服务'
                      : '未配置 Key，将尝试 ApiZero 匿名查询',
                  style: TextStyle(
                    color: isConfigured ? colors.onSurface : Colors.orange[800],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _isSaving || _isTesting ? null : _saveKey,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
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
            '当前油价使用 ApiZero oil-price，调价预测、国际原油和调价日历使用 oil-price-forecast。接口地址和请求参数按官方协议固定。Key 为可选项，未配置时使用匿名请求；如配置 Key，仅保存于本机安全存储，不会写入源码或编译包。自动查询间隔 30 分钟，手动更新至少间隔 1 分钟。',
            style: TextStyle(
                fontSize: 12, color: colors.onSurfaceVariant, height: 1.45),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          const Text('详细配置教程',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          _buildGuideStep(
            number: 1,
            title: '注册并登录 ApiZero',
            description: '打开 ApiZero 油价文档或 API 商城，注册并登录个人账号。',
          ),
          _buildGuideStep(
            number: 2,
            title: '可选：申请或查看 ApiZero Key',
            description:
                'ApiZero 支持匿名请求；如匿名额度不足，可在任一油价接口页面申请个人 API Key。不要把 Key 发布到截图、源码或公共仓库。',
          ),
          _buildGuideStep(
            number: 3,
            title: '可选：回到本页保存 Key',
            description: '如已申请 Key，将其粘贴到上方输入框并保存；留空也可以直接使用匿名查询。',
          ),
          _buildGuideStep(
            number: 4,
            title: '手动验证结果',
            description: '回到实时油价页面点击刷新。若失败，页面会显示 HTTP 状态、业务码或具体返回字段错误。',
          ),
          const SizedBox(height: 8),
          const Text('相关网页',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          _buildWebLink(
            icon: AppIcons.menu_book_outlined,
            title: 'ApiZero 当前省级油价接口文档',
            subtitle: '查看 92/95/98/0 号油价字段和请求方式',
            url: 'https://apizero.cn/aidocs/oil-price/raw.md',
          ),
          _buildWebLink(
            icon: AppIcons.event_note_outlined,
            title: 'ApiZero 调价预测接口文档',
            subtitle: '查看国际原油、调价预测和调价日历字段',
            url: 'https://apizero.cn/aidocs/oil-price-forecast/raw.md',
          ),
          _buildWebLink(
            icon: AppIcons.home_outlined,
            title: 'ApiZero API 商城',
            subtitle: '查看接口状态、额度和在线调试',
            url: 'https://apizero.cn/marketplace/oil-price-forecast',
          ),
        ],
      ),
    );
  }
}
