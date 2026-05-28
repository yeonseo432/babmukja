import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _appMaxWidth = 430.0;

void main() {
  runApp(const SnuMealsApp());
}

class SnuMealsApp extends StatelessWidget {
  const SnuMealsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '서울대 학식',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B6B4B),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7F5),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: Color(0xFFE4E7E2)),
          ),
        ),
        useMaterial3: true,
      ),
      home: const MealsHomePage(),
    );
  }
}

class MealsHomePage extends StatefulWidget {
  const MealsHomePage({super.key});

  @override
  State<MealsHomePage> createState() => _MealsHomePageState();
}

class _MealsHomePageState extends State<MealsHomePage> {
  late var _selectedDate = _dateOnly(DateTime.now());
  late Future<AppData> _dataFuture = AppData.load(_selectedDate);
  late final Future<CafeteriaOrder> _orderFuture = CafeteriaOrderStore.load();
  var _selectedMeal = _defaultMealKey();
  var _tabIndex = 0;
  CafeteriaOrder? _order;

  static String _defaultMealKey() {
    final hour = DateTime.now().hour;
    if (hour < 10) return 'breakfast';
    if (hour < 16) return 'lunch';
    return 'dinner';
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  void _changeDate(int days) {
    final nextDate = _selectedDate.add(Duration(days: days));
    setState(() {
      _selectedDate = nextDate;
      _dataFuture = AppData.load(_selectedDate);
    });
  }

  void _goToday() {
    setState(() {
      _selectedDate = _dateOnly(DateTime.now());
      _dataFuture = AppData.load(_selectedDate);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppData>(
      future: _dataFuture,
      builder: (context, snapshot) {
        return FutureBuilder<CafeteriaOrder>(
          future: _orderFuture,
          builder: (context, orderSnapshot) {
            if (snapshot.hasData && orderSnapshot.hasData && _order == null) {
              _order = orderSnapshot.data;
            }

            if (!snapshot.hasData || _order == null) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final data = snapshot.data!;
            final order = _syncOrderWithData(_order!, data);
            final isToday = _isSameDate(
              _selectedDate,
              _dateOnly(DateTime.now()),
            );
            return Scaffold(
              appBar: AppBar(
                titleSpacing: 0,
                title: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _appMaxWidth),
                    child: DateHeader(
                      selectedDate: _selectedDate,
                      onPrevious: () => _changeDate(-1),
                      onNext: () => _changeDate(1),
                    ),
                  ),
                ),
              ),
              body: Stack(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: _appMaxWidth),
                      child: _tabIndex == 0
                          ? DailyMenusView(
                              data: data,
                              order: order.daily,
                              selectedMeal: _selectedMeal,
                              floatingActionVisible: !isToday,
                              onMealChanged: (value) {
                                setState(() => _selectedMeal = value);
                              },
                              onEditOrder: () => _editOrder(
                                title: '오늘 메뉴 순서',
                                ids: order.daily,
                                namesById: data.dailyNamesById,
                                apply: (ids) =>
                                    _saveOrder(order.copyWith(daily: ids)),
                              ),
                            )
                          : FixedMenusView(
                              items: data.fixedMenus,
                              order: order.fixed,
                              selectedMeal: _selectedMeal,
                              floatingActionVisible: !isToday,
                              onMealChanged: (value) {
                                setState(() => _selectedMeal = value);
                              },
                              onEditOrder: () => _editOrder(
                                title: '고정 메뉴 순서',
                                ids: order.fixed,
                                namesById: data.fixedNamesById,
                                apply: (ids) =>
                                    _saveOrder(order.copyWith(fixed: ids)),
                              ),
                            ),
                    ),
                  ),
                  if (!isToday)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Center(
                        child: TodayFloatingButton(onPressed: _goToday),
                      ),
                    ),
                ],
              ),
              bottomNavigationBar: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _appMaxWidth),
                  child: NavigationBar(
                    selectedIndex: _tabIndex,
                    onDestinationSelected: (value) {
                      setState(() => _tabIndex = value);
                    },
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.restaurant_menu_outlined),
                        selectedIcon: Icon(Icons.restaurant_menu),
                        label: '오늘 메뉴',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.photo_outlined),
                        selectedIcon: Icon(Icons.photo),
                        label: '고정 메뉴',
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveOrder(CafeteriaOrder nextOrder) async {
    await CafeteriaOrderStore.save(nextOrder);
    setState(() => _order = nextOrder);
  }

  CafeteriaOrder _syncOrderWithData(CafeteriaOrder order, AppData data) {
    final synced = order.withKnownIds(
      dailyIds: data.dailyNamesById.keys,
      fixedIds: data.fixedNamesById.keys,
    );
    if (synced == order) {
      return order;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _saveOrder(synced);
    });
    return synced;
  }

  Future<void> _editOrder({
    required String title,
    required List<String> ids,
    required Map<String, String> namesById,
    required Future<void> Function(List<String>) apply,
  }) async {
    final nextIds = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return OrderEditorSheet(title: title, ids: ids, namesById: namesById);
      },
    );
    if (nextIds != null) {
      await apply(nextIds);
    }
  }
}

class OrderEditorSheet extends StatefulWidget {
  const OrderEditorSheet({
    super.key,
    required this.title,
    required this.ids,
    required this.namesById,
  });

  final String title;
  final List<String> ids;
  final Map<String, String> namesById;

  @override
  State<OrderEditorSheet> createState() => _OrderEditorSheetState();
}

class _OrderEditorSheetState extends State<OrderEditorSheet> {
  late final _ids = widget.ids.where(widget.namesById.containsKey).toList();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(_ids),
                    child: const Text('완료'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ReorderableListView.builder(
                scrollController: scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                buildDefaultDragHandles: false,
                itemCount: _ids.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final id = _ids.removeAt(oldIndex);
                    _ids.insert(newIndex, id);
                  });
                },
                itemBuilder: (context, index) {
                  final id = _ids[index];
                  return ListTile(
                    key: ValueKey(id),
                    title: Text(widget.namesById[id] ?? id),
                    trailing: ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class TodayFloatingButton extends StatelessWidget {
  const TodayFloatingButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: FilledButton.tonalIcon(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: onPressed,
        icon: const Icon(Icons.today_outlined, size: 18),
        label: const Text('오늘로 돌아가기'),
      ),
    );
  }
}

class DateHeader extends StatelessWidget {
  const DateHeader({
    super.key,
    required this.selectedDate,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime selectedDate;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
            tooltip: '전날',
          ),
          Expanded(
            child: Center(
              child: Text(
                _dateHeaderLabel(selectedDate),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            tooltip: '다음날',
          ),
        ],
      ),
    );
  }
}

class DailyMenusView extends StatelessWidget {
  const DailyMenusView({
    super.key,
    required this.data,
    required this.order,
    required this.selectedMeal,
    required this.floatingActionVisible,
    required this.onMealChanged,
    required this.onEditOrder,
  });

  final AppData data;
  final List<String> order;
  final String selectedMeal;
  final bool floatingActionVisible;
  final ValueChanged<String> onMealChanged;
  final VoidCallback onEditOrder;

  @override
  Widget build(BuildContext context) {
    final entries = _sortByOrder(
      data.dailyMenus.where((entry) {
        final meal = entry.meals[selectedMeal];
        return meal != null && meal.sections.isNotEmpty;
      }).toList(),
      order,
      (entry) => entry.cafeteria.id,
    );

    return Column(
      children: [
        MealSelector(
          selectedMeal: selectedMeal,
          onChanged: onMealChanged,
          onEditOrder: onEditOrder,
        ),
        Expanded(
          child: entries.isEmpty
              ? const EmptyMenusMessage()
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    floatingActionVisible ? 88 : 24,
                  ),
                  itemBuilder: (context, index) {
                    return CafeteriaCard(
                      entry: entries[index],
                      mealKey: selectedMeal,
                    );
                  },
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemCount: entries.length,
                ),
        ),
      ],
    );
  }
}

class EmptyMenusMessage extends StatelessWidget {
  const EmptyMenusMessage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '식단 데이터가 없습니다.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF69736D)),
        ),
      ),
    );
  }
}

class MealSelector extends StatelessWidget {
  const MealSelector({
    super.key,
    required this.selectedMeal,
    required this.onChanged,
    required this.onEditOrder,
  });

  final String selectedMeal;
  final ValueChanged<String> onChanged;
  final VoidCallback onEditOrder;

  @override
  Widget build(BuildContext context) {
    const labels = {'breakfast': '아침', 'lunch': '점심', 'dinner': '저녁'};

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: SegmentedButton<String>(
                segments: labels.entries
                    .map(
                      (entry) => ButtonSegment(
                        value: entry.key,
                        label: Text(entry.value),
                      ),
                    )
                    .toList(),
                selected: {selectedMeal},
                showSelectedIcon: false,
                onSelectionChanged: (values) => onChanged(values.first),
              ),
            ),
          ),
          IconButton(
            onPressed: onEditOrder,
            icon: const Icon(Icons.tune),
            tooltip: '식당 순서 편집',
          ),
        ],
      ),
    );
  }
}

class CafeteriaCard extends StatelessWidget {
  const CafeteriaCard({super.key, required this.entry, required this.mealKey});

  final DailyMenuEntry entry;
  final String mealKey;

  @override
  Widget build(BuildContext context) {
    final meal = entry.meals[mealKey]!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    entry.cafeteria.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (meal.hoursLabel != null) ...[
              const SizedBox(height: 4),
              OperatingHoursText(meal.hoursLabel!),
            ],
            const SizedBox(height: 12),
            for (final section in meal.sections) ...[
              if (section.title != 'general') ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        section.title,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: const Color(0xFF0B6B4B),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (section.price != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          '${_formatPrice(section.price!)}원',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              SectionItemsView(items: section.items, section: section),
              for (final note in section.notes) NoteText(note),
              if (section != meal.sections.last) const SizedBox(height: 12),
            ],
            for (final note in meal.notes) NoteText(note),
          ],
        ),
      ),
    );
  }
}

class MenuItemRow extends StatelessWidget {
  const MenuItemRow({super.key, required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              item.name,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (item.price != null)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                '${_formatPrice(item.price!)}원',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class SectionItemsView extends StatelessWidget {
  const SectionItemsView({
    super.key,
    required this.items,
    required this.section,
  });

  final List<MenuItem> items;
  final MenuSection section;

  @override
  Widget build(BuildContext context) {
    if (_usesInlineComposition(section, items)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Wrap(
              spacing: 4,
              runSpacing: 6,
              children: [
                for (var index = 0; index < items.length; index++)
                  Text(
                    '${items[index].name}${index == items.length - 1 ? '' : ','}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF4F5A53),
                      height: 1.35,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      children: [for (final item in items) MenuItemRow(item: item)],
    );
  }
}

class NoteText extends StatelessWidget {
  const NoteText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: const Color(0xFF69736D)),
      ),
    );
  }
}

class OperatingHoursText extends StatelessWidget {
  const OperatingHoursText(this.hours, {super.key});

  final String hours;

  @override
  Widget build(BuildContext context) {
    return Text(
      '운영시간 $hours',
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: const Color(0xFF69736D)),
    );
  }
}

class MenuImageLink extends StatelessWidget {
  const MenuImageLink({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.photo_outlined,
              size: 16,
              color: Color(0xFF0B6B4B),
            ),
            const SizedBox(width: 4),
            Text(
              '메뉴판 사진으로 보기',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: const Color(0xFF0B6B4B),
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.underline,
                decorationColor: const Color(0xFF0B6B4B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FixedMenusView extends StatefulWidget {
  const FixedMenusView({
    super.key,
    required this.items,
    required this.order,
    required this.selectedMeal,
    required this.floatingActionVisible,
    required this.onMealChanged,
    required this.onEditOrder,
  });

  final List<FixedMenuEntry> items;
  final List<String> order;
  final String selectedMeal;
  final bool floatingActionVisible;
  final ValueChanged<String> onMealChanged;
  final VoidCallback onEditOrder;

  @override
  State<FixedMenusView> createState() => _FixedMenusViewState();
}

class _FixedMenusViewState extends State<FixedMenusView> {
  final _expandedSections = <String>{};
  final _cardKeys = <String, GlobalKey>{};

  @override
  Widget build(BuildContext context) {
    final entries = _sortByOrder(
      widget.items.where((entry) {
        final meal = entry.meals[widget.selectedMeal];
        return meal != null &&
            (meal.sections.isNotEmpty || meal.imagePath != null);
      }).toList(),
      widget.order,
      (entry) => entry.cafeteriaId,
    );

    return Column(
      children: [
        MealSelector(
          selectedMeal: widget.selectedMeal,
          onChanged: widget.onMealChanged,
          onEditOrder: widget.onEditOrder,
        ),
        Expanded(
          child: entries.isEmpty
              ? const EmptyMenusMessage()
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    widget.floatingActionVisible ? 88 : 24,
                  ),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final cardKey = _cardKeys.putIfAbsent(
                      entry.cafeteriaId,
                      GlobalKey.new,
                    );
                    return KeyedSubtree(
                      key: cardKey,
                      child: FixedMenuCard(
                        entry: entry,
                        mealKey: widget.selectedMeal,
                        expandedSections: _expandedSections,
                        onToggleSection: (sectionKey) {
                          final wasExpanded = _expandedSections.contains(
                            sectionKey,
                          );
                          setState(
                            () => _toggleSet(_expandedSections, sectionKey),
                          );
                          if (wasExpanded) {
                            _scrollCardIntoView(cardKey);
                          }
                        },
                      ),
                    );
                  },
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemCount: entries.length,
                ),
        ),
      ],
    );
  }

  void _toggleSet(Set<String> set, String value) {
    if (!set.add(value)) {
      set.remove(value);
    }
  }

  void _scrollCardIntoView(GlobalKey cardKey) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = cardKey.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
  }
}

class FixedMenuCard extends StatelessWidget {
  const FixedMenuCard({
    super.key,
    required this.entry,
    required this.mealKey,
    required this.expandedSections,
    required this.onToggleSection,
  });

  final FixedMenuEntry entry;
  final String mealKey;
  final Set<String> expandedSections;
  final ValueChanged<String> onToggleSection;

  @override
  Widget build(BuildContext context) {
    final meal = entry.meals[mealKey]!;
    final mode = _fixedExpansionMode(entry.cafeteriaId);
    final visibleSections = meal.sections
        .where(
          (section) => _showsFixedSection(
            entry.cafeteriaId,
            mealKey,
            section,
            expandedSections,
          ),
        )
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    entry.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (meal.imagePath != null)
                  MenuImageLink(
                    onTap: () =>
                        _showMenuImage(context, entry.name, meal.imagePath!),
                  ),
              ],
            ),
            if (meal.hoursLabel != null) ...[
              const SizedBox(height: 4),
              OperatingHoursText(meal.hoursLabel!),
            ],
            if (visibleSections.isNotEmpty) const SizedBox(height: 12),
            for (final section in visibleSections) ...[
              FixedSectionBlock(
                cafeteriaId: entry.cafeteriaId,
                mealKey: mealKey,
                section: section,
                expansionMode: mode,
                expandedSections: expandedSections,
                onToggleSection: onToggleSection,
                hideToggle: _hidesFixedSectionToggleInBlock(
                  entry.cafeteriaId,
                  mealKey,
                  section.title,
                  expandedSections,
                ),
              ),
              if (section != visibleSections.last) const SizedBox(height: 12),
            ],
            if (_showsGroupedFixedToggle(
              entry.cafeteriaId,
              mealKey,
              visibleSections,
            )) ...[
              const SizedBox(height: 4),
              FoldButton(
                expanded: true,
                expandedLabel: '접기',
                collapsedLabel: '메뉴 전체 보기',
                onTap: () => onToggleSection(
                  _fixedSectionExpansionKey(
                    entry.cafeteriaId,
                    mealKey,
                    'general',
                  ),
                ),
              ),
            ],
            if (meal.notes.isNotEmpty) const SizedBox(height: 10),
            for (final note in meal.notes) NoteText(note),
          ],
        ),
      ),
    );
  }

  void _showMenuImage(BuildContext context, String name, String imagePath) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text(name),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            body: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Center(child: Image.asset(imagePath, fit: BoxFit.contain)),
            ),
          ),
        );
      },
    );
  }
}

class FixedSectionBlock extends StatelessWidget {
  const FixedSectionBlock({
    super.key,
    required this.cafeteriaId,
    required this.mealKey,
    required this.section,
    required this.expansionMode,
    required this.expandedSections,
    required this.onToggleSection,
    this.hideToggle = false,
  });

  final String cafeteriaId;
  final String mealKey;
  final MenuSection section;
  final FixedExpansionMode expansionMode;
  final Set<String> expandedSections;
  final ValueChanged<String> onToggleSection;
  final bool hideToggle;

  @override
  Widget build(BuildContext context) {
    final isSectionMode = expansionMode == FixedExpansionMode.section;
    final sectionKey = _fixedSectionExpansionKey(
      cafeteriaId,
      mealKey,
      section.title,
    );
    final showsToggle = _showsFixedSectionToggle(cafeteriaId, section.title);
    final isExpanded = expandedSections.contains(sectionKey);
    final visibleItems = isSectionMode && !isExpanded
        ? section.items.take(2).toList()
        : section.items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.title != 'general') ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  section.title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF0B6B4B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (section.price != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    '${_formatPrice(section.price!)}원',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        SectionItemsView(items: visibleItems, section: section),
        for (final note in section.notes) NoteText(note),
        if (!hideToggle &&
            isSectionMode &&
            showsToggle &&
            section.items.length > 2) ...[
          const SizedBox(height: 4),
          FoldButton(
            expanded: isExpanded,
            expandedLabel: '접기',
            collapsedLabel: '메뉴 전체 보기',
            onTap: () => onToggleSection(sectionKey),
          ),
        ],
      ],
    );
  }
}

class FoldButton extends StatelessWidget {
  const FoldButton({
    super.key,
    required this.expanded,
    required this.expandedLabel,
    required this.collapsedLabel,
    required this.onTap,
  });

  final bool expanded;
  final String expandedLabel;
  final String collapsedLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF6B6B6B);
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: Theme.of(context).textTheme.bodySmall,
      ),
      onPressed: onTap,
      icon: Icon(
        expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
        size: 18,
      ),
      label: Text(expanded ? expandedLabel : collapsedLabel),
    );
  }
}

enum FixedExpansionMode { none, section }

FixedExpansionMode _fixedExpansionMode(String cafeteriaId) {
  if (cafeteriaId == 'dure_midam' ||
      cafeteriaId == 'engineering_snack' ||
      cafeteriaId == 'building_75_1_food_court' ||
      cafeteriaId == 'building_220') {
    return FixedExpansionMode.section;
  }
  return FixedExpansionMode.none;
}

String _fixedSectionExpansionKey(
  String cafeteriaId,
  String mealKey,
  String sectionTitle,
) {
  var keyTitle = sectionTitle;
  if (cafeteriaId == 'engineering_snack' && sectionTitle == '사이드') {
    keyTitle = 'general';
  }
  return '$cafeteriaId:$mealKey:$keyTitle';
}

bool _showsFixedSectionToggle(String cafeteriaId, String sectionTitle) {
  return !(cafeteriaId == 'engineering_snack' && sectionTitle == '사이드');
}

bool _hidesFixedSectionToggleInBlock(
  String cafeteriaId,
  String mealKey,
  String sectionTitle,
  Set<String> expandedSections,
) {
  if (cafeteriaId != 'engineering_snack' || sectionTitle != 'general') {
    return false;
  }
  final menuKey = _fixedSectionExpansionKey(cafeteriaId, mealKey, 'general');
  return expandedSections.contains(menuKey);
}

bool _showsFixedSection(
  String cafeteriaId,
  String mealKey,
  MenuSection section,
  Set<String> expandedSections,
) {
  if (cafeteriaId != 'engineering_snack' || section.title != '사이드') {
    return true;
  }
  final menuKey = _fixedSectionExpansionKey(cafeteriaId, mealKey, 'general');
  return expandedSections.contains(menuKey);
}

bool _showsGroupedFixedToggle(
  String cafeteriaId,
  String mealKey,
  List<MenuSection> visibleSections,
) {
  return cafeteriaId == 'engineering_snack' &&
      visibleSections.any((section) => section.title == '사이드');
}

bool _usesInlineComposition(MenuSection section, List<MenuItem> items) {
  if (items.length < 3 || items.any((item) => item.price != null)) {
    return false;
  }
  final title = section.title;
  return section.price != null ||
      title.contains('세미뷔페') ||
      title.contains('셀프코너') ||
      title.contains('뷔페');
}

List<T> _sortByOrder<T>(
  List<T> items,
  List<String> order,
  String Function(T item) idOf,
) {
  final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
  final indexed = [
    for (var i = 0; i < items.length; i++) (index: i, item: items[i]),
  ];
  indexed.sort((left, right) {
    final leftRank = rank[idOf(left.item)];
    final rightRank = rank[idOf(right.item)];
    if (leftRank != null && rightRank != null) {
      return leftRank.compareTo(rightRank);
    }
    if (leftRank != null) return -1;
    if (rightRank != null) return 1;
    return left.index.compareTo(right.index);
  });
  return [for (final item in indexed) item.item];
}

class AppData {
  const AppData({
    required this.menuDate,
    required this.dailyMenus,
    required this.fixedMenus,
  });

  final String menuDate;
  final List<DailyMenuEntry> dailyMenus;
  final List<FixedMenuEntry> fixedMenus;

  Map<String, String> get dailyNamesById => {
    for (final entry in dailyMenus) entry.cafeteria.id: entry.cafeteria.name,
  };

  Map<String, String> get fixedNamesById => {
    for (final entry in fixedMenus) entry.cafeteriaId: entry.name,
  };

  static Future<AppData> load(DateTime date) async {
    final cafeteriasJson = await rootBundle.loadString(
      'assets/data/cafeterias.json',
    );
    final fixedJson = await rootBundle.loadString(
      'assets/data/fixed_menus.json',
    );
    final dateKey = _assetDate(date);

    final cafeterias = (jsonDecode(cafeteriasJson) as List<dynamic>)
        .map((item) => Cafeteria.fromJson(item as Map<String, dynamic>))
        .toList();
    final cafeteriaById = {for (final item in cafeterias) item.id: item};
    final fixedMenus = (jsonDecode(fixedJson) as List<dynamic>)
        .map((item) => FixedMenuEntry.fromJson(item as Map<String, dynamic>))
        .toList();

    String dailyJson;
    try {
      dailyJson = await rootBundle.loadString(
        'assets/data/menus/$dateKey.json',
      );
    } on FlutterError {
      return AppData(
        menuDate: dateKey,
        dailyMenus: const [],
        fixedMenus: fixedMenus,
      );
    }

    final dailyMap = jsonDecode(dailyJson) as Map<String, dynamic>;
    final entries = (dailyMap['cafeterias'] as List<dynamic>)
        .map(
          (item) => DailyMenuEntry.fromJson(
            item as Map<String, dynamic>,
            cafeteriaById[item['cafeteriaId']]!,
          ),
        )
        .toList();

    return AppData(
      menuDate: dailyMap['date'] as String,
      dailyMenus: entries,
      fixedMenus: fixedMenus,
    );
  }
}

class CafeteriaOrder {
  const CafeteriaOrder({required this.daily, required this.fixed});

  final List<String> daily;
  final List<String> fixed;

  CafeteriaOrder copyWith({List<String>? daily, List<String>? fixed}) {
    return CafeteriaOrder(
      daily: daily ?? this.daily,
      fixed: fixed ?? this.fixed,
    );
  }

  CafeteriaOrder withKnownIds({
    required Iterable<String> dailyIds,
    required Iterable<String> fixedIds,
  }) {
    return CafeteriaOrder(
      daily: _syncIds(daily, dailyIds),
      fixed: _syncIds(fixed, fixedIds),
    );
  }

  static List<String> _syncIds(List<String> stored, Iterable<String> knownIds) {
    final known = knownIds.toSet();
    return [
      for (final id in stored)
        if (known.contains(id)) id,
      for (final id in knownIds)
        if (!stored.contains(id)) id,
    ];
  }

  @override
  bool operator ==(Object other) {
    return other is CafeteriaOrder &&
        _sameIds(daily, other.daily) &&
        _sameIds(fixed, other.fixed);
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(daily), Object.hashAll(fixed));

  static bool _sameIds(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  factory CafeteriaOrder.fromJson(Map<String, dynamic> json) {
    return CafeteriaOrder(
      daily: (json['daily'] as List<dynamic>).cast<String>(),
      fixed: (json['fixed'] as List<dynamic>).cast<String>(),
    );
  }
}

class CafeteriaOrderStore {
  static const _initializedKey = 'cafeteria_order_initialized';
  static const _dailyKey = 'daily_cafeteria_order';
  static const _fixedKey = 'fixed_cafeteria_order';

  static Future<CafeteriaOrder> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_initializedKey) != true) {
      final defaultOrder = await _loadDefaultOrder();
      await _write(prefs, defaultOrder);
      await prefs.setBool(_initializedKey, true);
      return defaultOrder;
    }

    final daily = prefs.getStringList(_dailyKey);
    final fixed = prefs.getStringList(_fixedKey);
    if (daily == null || fixed == null || daily.isEmpty || fixed.isEmpty) {
      final defaultOrder = await _loadDefaultOrder();
      await _write(prefs, defaultOrder);
      return defaultOrder;
    }
    return CafeteriaOrder(daily: daily, fixed: fixed);
  }

  static Future<void> save(CafeteriaOrder order) async {
    final prefs = await SharedPreferences.getInstance();
    await _write(prefs, order);
    await prefs.setBool(_initializedKey, true);
  }

  static Future<CafeteriaOrder> _loadDefaultOrder() async {
    final jsonText = await rootBundle.loadString(
      'assets/data/default_cafeteria_order.json',
    );
    return CafeteriaOrder.fromJson(
      jsonDecode(jsonText) as Map<String, dynamic>,
    );
  }

  static Future<void> _write(
    SharedPreferences prefs,
    CafeteriaOrder order,
  ) async {
    await prefs.setStringList(_dailyKey, order.daily);
    await prefs.setStringList(_fixedKey, order.fixed);
  }
}

class Cafeteria {
  const Cafeteria({required this.id, required this.name});

  final String id;
  final String name;

  factory Cafeteria.fromJson(Map<String, dynamic> json) {
    return Cafeteria(id: json['id'] as String, name: json['name'] as String);
  }
}

class DailyMenuEntry {
  const DailyMenuEntry({required this.cafeteria, required this.meals});

  final Cafeteria cafeteria;
  final Map<String, Meal> meals;

  factory DailyMenuEntry.fromJson(
    Map<String, dynamic> json,
    Cafeteria cafeteria,
  ) {
    final mealsJson = json['meals'] as Map<String, dynamic>;
    return DailyMenuEntry(
      cafeteria: cafeteria,
      meals: mealsJson.map(
        (key, value) =>
            MapEntry(key, Meal.fromJson(value as Map<String, dynamic>)),
      ),
    );
  }
}

class Meal {
  const Meal({
    required this.sections,
    required this.notes,
    this.hoursLabel,
    this.busyHoursLabel,
    this.imagePath,
  });

  final List<MenuSection> sections;
  final List<String> notes;
  final String? hoursLabel;
  final String? busyHoursLabel;
  final String? imagePath;

  factory Meal.fromJson(Map<String, dynamic> json) {
    return Meal(
      sections: (json['sections'] as List<dynamic>)
          .map((item) => MenuSection.fromJson(item as Map<String, dynamic>))
          .where(
            (section) => section.items.isNotEmpty || section.notes.isNotEmpty,
          )
          .toList(),
      notes: (json['notes'] as List<dynamic>).cast<String>(),
      hoursLabel: _rangeLabel(json['hours']),
      busyHoursLabel: _rangeLabel(json['busyHours']),
      imagePath: json['imagePath'] as String?,
    );
  }
}

class MenuSection {
  const MenuSection({
    required this.title,
    required this.price,
    required this.items,
    required this.notes,
  });

  final String title;
  final int? price;
  final List<MenuItem> items;
  final List<String> notes;

  factory MenuSection.fromJson(Map<String, dynamic> json) {
    return MenuSection(
      title: json['title'] as String,
      price: json['price'] as int?,
      items: (json['items'] as List<dynamic>)
          .map((item) => MenuItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      notes: (json['notes'] as List<dynamic>).cast<String>(),
    );
  }
}

class MenuItem {
  const MenuItem({required this.name, required this.price});

  final String name;
  final int? price;

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(name: json['name'] as String, price: json['price'] as int?);
  }
}

class FixedMenuEntry {
  const FixedMenuEntry({
    required this.cafeteriaId,
    required this.name,
    required this.meals,
  });

  final String cafeteriaId;
  final String name;
  final Map<String, Meal> meals;

  factory FixedMenuEntry.fromJson(Map<String, dynamic> json) {
    final mealsJson = json['meals'] as Map<String, dynamic>;
    return FixedMenuEntry(
      cafeteriaId: json['cafeteriaId'] as String,
      name: json['name'] as String,
      meals: mealsJson.map(
        (key, value) =>
            MapEntry(key, Meal.fromJson(value as Map<String, dynamic>)),
      ),
    );
  }
}

String? _rangeLabel(dynamic value) {
  if (value == null) return null;
  final map = value as Map<String, dynamic>;
  return '${map['start']}~${map['end']}';
}

bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _assetDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

String _dateHeaderLabel(DateTime date) {
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  final weekday = weekdays[date.weekday - 1];
  return '${date.month}.${date.day} $weekday';
}

String _formatPrice(int price) {
  final source = price.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < source.length; i += 1) {
    if (i != 0 && (source.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(source[i]);
  }
  return buffer.toString();
}
