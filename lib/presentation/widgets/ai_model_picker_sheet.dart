import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';

/// AI 模型多选底部面板。
///
/// [fetched] 为接口返回（或候选）的完整模型清单；
/// [initiallySelected] 为已保存的模型集合；返回用户勾选的模型列表。
Future<List<String>?> showAiModelPickerSheet(
  BuildContext context, {
  required List<String> fetched,
  required Set<String> initiallySelected,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      final colors = Theme.of(sheetCtx).colorScheme;
      final queryController = TextEditingController();
      final selected = {
        for (final m in fetched) m: initiallySelected.contains(m),
      };
      return DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        expand: false,
        builder: (innerCtx, scrollController) {
          return StatefulBuilder(
            builder: (innerCtx, setSheetState) {
              final query = queryController.text.trim().toLowerCase();
              final visible = fetched
                  .where(
                    (m) => query.isEmpty || m.toLowerCase().contains(query),
                  )
                  .toList();
              final checkedCount = selected.values.where((v) => v).length;
              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(sheetCtx).cardColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Text(
                            '选择要保存的模型（已选 $checkedCount）',
                            style: Theme.of(innerCtx).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(AppIcons.close, size: 18),
                            onPressed: () => Navigator.pop(sheetCtx),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: queryController,
                              onChanged: (_) => setSheetState(() {}),
                              decoration: const InputDecoration(
                                hintText: '搜索模型',
                                prefixIcon: Icon(AppIcons.search, size: 18),
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setSheetState(() {
                              final allChecked =
                                  visible.isNotEmpty &&
                                  visible.every((m) => selected[m] == true);
                              for (final m in visible) {
                                selected[m] = !allChecked;
                              }
                            }),
                            child: const Text('全选/反选'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: visible.isEmpty
                          ? Center(
                              child: Text(
                                '没有匹配的模型',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: visible.length,
                              itemBuilder: (innerCtx, index) {
                                final model = visible[index];
                                final isChecked = selected[model] == true;
                                return CheckboxListTile(
                                  dense: true,
                                  value: isChecked,
                                  title: Text(
                                    model,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  onChanged: (v) => setSheetState(
                                    () => selected[model] = v ?? false,
                                  ),
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF5A24),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            final picked = fetched
                                .where((m) => selected[m] == true)
                                .toList();
                            Navigator.pop(sheetCtx, picked);
                          },
                          child: const Text('保存所选模型'),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );
}
