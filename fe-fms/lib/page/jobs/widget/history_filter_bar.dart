import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fms/core/theme/dispatch_palette.dart';
import 'package:fms/core/theme/motion.dart';
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
        // Tighter than before: the chips' 48dp targets carry their own inset.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
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
                // Filter toggle — Material chip for the 48dp target + ripple.
                ActionChip(
                  tooltip: isVisible ? 'Hide filters' : 'Show filters',
                  onPressed: () =>
                      controller.isHistoryFilterVisible.value = !isVisible,
                  avatar: Icon(
                    Icons.filter_list,
                    size: 18,
                    color: hasFilters ? primary : palette.subtle,
                  ),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Filter'),
                      if (hasFilters) ...[
                        const SizedBox(width: 4),
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
                  labelStyle: TextStyle(
                    color: hasFilters ? primary : palette.subtle,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: hasFilters
                      ? primary.withValues(alpha: 0.1)
                      : Colors.transparent,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 4),
                // Sort toggle
                ActionChip(
                  tooltip: isNewest ? 'Sort oldest first' : 'Sort newest first',
                  onPressed: () {
                    controller.historySortOrder.value = isNewest
                        ? HistorySortOrder.oldestFirst
                        : HistorySortOrder.newestFirst;
                  },
                  avatar: Icon(Icons.swap_vert, size: 18, color: primary),
                  label: Text(isNewest ? 'Newest' : 'Oldest'),
                  labelStyle: TextStyle(
                    color: primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: Colors.transparent,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            );
          }),
        ),

        // Collapsible filter section — grows open and shut.
        Obx(() => MotionSize(
              alignment: Alignment.topCenter,
              child: controller.isHistoryFilterVisible.value
                  ? _FilterBody(
                      controller: controller,
                      primary: primary,
                      borderColor: borderColor,
                    )
                  : const SizedBox(width: double.infinity),
            )),

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
    1: 'Line interruption',
    2: 'Reconnection',
    3: 'Short circuit',
    4: 'Disconnection',
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
                  tooltip: 'Clear search',
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

        // Date range chips. The row grows with text size so the chips
        // don't clip.
        SizedBox(
          height: MediaQuery.textScalerOf(context).scale(48),
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
          height: MediaQuery.textScalerOf(context).scale(48),
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
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: primary,
      backgroundColor: palette.card,
      side: BorderSide(color: selected ? primary : borderColor),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        color: selected ? Colors.white : palette.subtle,
        fontSize: 13,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
    );
  }
}
