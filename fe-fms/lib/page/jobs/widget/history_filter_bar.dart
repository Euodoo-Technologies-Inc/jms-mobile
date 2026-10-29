import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fms/core/theme/dispatch_palette.dart';
import 'package:fms/page/jobs/controller/jobs_controller.dart';
import 'package:fms/page/jobs/controller/history_filter_mixin.dart';

/// Self-contained filter bar for the History tab: a toggle header row,
/// collapsible search + date chips + type chips, and a sort toggle.
class HistoryFilterBar extends StatelessWidget {
  const HistoryFilterBar({super.key, required this.filteredCount});

  final int filteredCount;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<JobsController>();
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    final palette = context.dispatch;
    final borderColor = palette.cardBorder;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header row: result count + filter toggle + sort
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Obx(() {
            final isNewest =
                controller.historySortOrder.value == HistorySortOrder.newestFirst;
            final isVisible = controller.isHistoryFilterVisible.value;
            final hasFilters = controller.hasActiveHistoryFilters;
            return Row(
              children: [
                Text(
                  'Showing $filteredCount ${filteredCount == 1 ? 'job' : 'jobs'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const Spacer(),
                // Filter toggle button
                GestureDetector(
                  onTap: () => controller.isHistoryFilterVisible.value =
                      !isVisible,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: hasFilters
                          ? primary.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.filter_list,
                          size: 18,
                          color: hasFilters ? primary : palette.subtle,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Filter',
                          style: TextStyle(
                            color:
                                hasFilters ? primary : palette.subtle,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (hasFilters) ...[
                          const SizedBox(width: 2),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Sort toggle
                GestureDetector(
                  onTap: () {
                    controller.historySortOrder.value = isNewest
                        ? HistorySortOrder.oldestFirst
                        : HistorySortOrder.newestFirst;
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.swap_vert, size: 18, color: primary),
                      const SizedBox(width: 4),
                      Text(
                        isNewest ? 'Newest' : 'Oldest',
                        style: TextStyle(
                          color: primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ),

        // Collapsible filter section
        Obx(() {
          if (!controller.isHistoryFilterVisible.value) {
            return const SizedBox.shrink();
          }
          return _FilterBody(
            controller: controller,
            primary: primary,
            borderColor: borderColor,
          );
        }),

        const Divider(height: 1),
      ],
    );
  }
}

/// The collapsible body containing search, date chips, and type chips.
class _FilterBody extends StatelessWidget {
  const _FilterBody({
    required this.controller,
    required this.primary,
    required this.borderColor,
  });

  final JobsController controller;
  final Color primary;
  final Color borderColor;

  static const _jobTypes = {
    1: 'Line Int.',
    2: 'Recon.',
    3: 'SC',
    4: 'Disc.',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Search field
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: controller.historySearchController,
            onChanged: controller.updateHistorySearch,
            decoration: InputDecoration(
              hintText: 'Search jobs or customers...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: Obx(() {
                if (controller.historySearchQuery.value.isEmpty) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    controller.historySearchController.clear();
                    controller.updateHistorySearch('');
                    controller.historySearchQuery.value = '';
                  },
                );
              }),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ),

        // Date range chips
        SizedBox(
          height: 38,
          child: Obx(() {
            return ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: HistoryDateRange.values.map((range) {
                final selected = controller.historyDateRange.value == range;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _FilterChip(
                    label: _dateRangeLabel(range),
                    selected: selected,
                    primary: primary,
                    borderColor: borderColor,
                    onTap: () => controller.historyDateRange.value = range,
                  ),
                );
              }).toList(),
            );
          }),
        ),

        const SizedBox(height: 6),

        // Job type chips
        SizedBox(
          height: 38,
          child: Obx(() {
            return ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _FilterChip(
                    label: 'All',
                    selected: controller.historyTypeFilter.value == null,
                    primary: primary,
                    borderColor: borderColor,
                    onTap: () => controller.historyTypeFilter.value = null,
                  ),
                ),
                ..._jobTypes.entries.map((entry) {
                  final selected =
                      controller.historyTypeFilter.value == entry.key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _FilterChip(
                      label: entry.value,
                      selected: selected,
                      primary: primary,
                      borderColor: borderColor,
                      onTap: () =>
                          controller.historyTypeFilter.value = entry.key,
                    ),
                  );
                }),
              ],
            );
          }),
        ),

        const SizedBox(height: 8),
      ],
    );
  }

  String _dateRangeLabel(HistoryDateRange range) {
    switch (range) {
      case HistoryDateRange.all:
        return 'All';
      case HistoryDateRange.today:
        return 'Today';
      case HistoryDateRange.last7Days:
        return '7 days';
      case HistoryDateRange.last30Days:
        return '30 days';
      case HistoryDateRange.last90Days:
        return '90 days';
    }
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.primary,
    required this.borderColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color primary;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.dispatch;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? primary : palette.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? primary : borderColor,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : palette.subtle,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}
