import 'controller.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'widgets/month_card.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MonthlyReport extends StatefulWidget {
  final List<Map<String, dynamic>> transactions;

  const MonthlyReport({super.key, required this.transactions});

  @override
  State<MonthlyReport> createState() => _MonthlyReportState();
}

class _MonthlyReportState extends State<MonthlyReport> {
  late final MonthlyReportController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MonthlyReportController(transactions: widget.transactions);
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _showYearPickerSheet(
    Color cardBackgroundColor,
    Color cardTextColor,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: cardBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  'Year: ${_controller.selectedYear}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: cardTextColor,
                  ),
                ),
              ),
              const Divider(height: 1),
              ..._controller.availableYears.map(
                (year) => ListTile(
                  key: ValueKey('year-option-$year'),
                  title: Text(
                    year.toString(),
                    style: TextStyle(color: cardTextColor),
                  ),
                  trailing: year == _controller.selectedYear
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _controller.selectYear(year);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cardBackgroundColor = colorScheme.surface;
    final cardTextColor =
        ThemeData.estimateBrightnessForColor(cardBackgroundColor) ==
            Brightness.dark
        ? Colors.white
        : Colors.black;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: colorScheme.primaryGradient,
            border: Border(
              bottom: BorderSide(color: colorScheme.secondary, width: 3),
            ),
          ),
        ),
        surfaceTintColor: Colors.transparent,
        toolbarHeight: MediaQuery.textScalerOf(context).scale(18) > 28
            ? 112
            : 64,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Monthly history',
          maxLines: 2,
          softWrap: true,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        actions: [
          IconButton(
            key: const ValueKey('year-filter-button'),
            onPressed: () =>
                _showYearPickerSheet(cardBackgroundColor, cardTextColor),
            icon: const Icon(Icons.filter_list, color: Colors.white),
            tooltip: 'Filter by year',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(cardBackgroundColor, cardTextColor, colorScheme),
    );
  }

  Widget _buildBody(
    Color cardBackgroundColor,
    Color cardTextColor,
    dynamic colorScheme,
  ) {
    final filteredMonths = _controller.filteredMonths;

    if (filteredMonths.isEmpty) {
      return const Center(
        child: Text(
          'No transactions found for this time range.',
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    // Pre-filter to cards with real data so itemCount is accurate
    final visibleMonths = filteredMonths.where((month) {
      final data = _controller.monthlySums[month]!;
      final total =
          data['directWasher']! + data['directDryer']! + data['loyaltyCard']!;
      return !(total == 0 &&
          data['loyaltyWasher'] == 0 &&
          data['loyaltyDryer'] == 0);
    }).toList();

    if (visibleMonths.isEmpty) {
      return const Center(
        child: Text(
          'No transactions found for this time range.',
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    final scrollController = ScrollController();

    return Theme(
      data: Theme.of(context).copyWith(
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(colorScheme.primary),
          trackColor: WidgetStateProperty.all(Colors.transparent),
          thickness: WidgetStateProperty.all(8),
          radius: const Radius.circular(4),
        ),
      ),
      child: Scrollbar(
        controller: scrollController,
        thumbVisibility: true,
        interactive: true,
        child: ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: visibleMonths.length,
          itemBuilder: (context, index) {
            final month = visibleMonths[index];
            final data = _controller.monthlySums[month]!;
            return MonthCard(
              month: month,
              data: data,
              cardBackgroundColor: cardBackgroundColor,
              cardTextColor: cardTextColor,
              primaryColor: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF8DCDF4)
                  : colorScheme.primary,
            );
          },
        ),
      ),
    );
  }
}
