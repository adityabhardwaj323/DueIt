import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/utils/app_timezone.dart';
import '../data/dues_repository.dart';

Map<String, List<Due>> _groupDuesByPerson(List<Due> dues) {
  final groups = <String, List<Due>>{};
  for (final due in dues) {
    final key = due.personName.trim().toLowerCase();
    groups.putIfAbsent(key, () => []).add(due);
  }
  return groups;
}

class DuesScreen extends ConsumerWidget {
  const DuesScreen({super.key});

  String _formatDueDate(DateTime dt) {
    final businessDt = tz.TZDateTime.from(dt, AppTimezone.businessLocation);
    final today = AppTimezone.businessDate();
    final itemDate = tz.TZDateTime(
      AppTimezone.businessLocation,
      businessDt.year,
      businessDt.month,
      businessDt.day,
    );

    final diffDays = itemDate.difference(today).inDays;
    if (diffDays == 0) return 'Due today';
    if (diffDays == 1) return 'Due tomorrow';
    if (diffDays == -1) return 'Due yesterday';
    if (diffDays < -1) return '${-diffDays}d overdue';

    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return 'Due ${months[businessDt.month - 1]} ${businessDt.day}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final duesAsyncValue = ref.watch(duesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.account_balance_wallet_rounded,
                color: theme.colorScheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Dues & Balances'),
          ],
        ),
      ),
      body: duesAsyncValue.when(
        data: (dues) {
          if (dues.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.volunteer_activism_rounded,
                        size: 54,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'All Settled Up!',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No pending debts or loans.\nTrack money you lend or borrow by tapping +.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? const Color(0xFF9CA3AF)
                            : const Color(0xFF6B7280),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 360,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Expanded(
                                child: _OutstandingAmount(
                                  label: 'You owe',
                                  amount: 0,
                                  color: Colors.redAccent,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _OutstandingAmount(
                                  label: 'Owed to you',
                                  amount: 0,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final pendingDues = dues.where((d) => d.status != 'settled').toList();
          final settledDues = dues.where((d) => d.status == 'settled').toList();
          final allAccounts = _groupDuesByPerson(dues);
          final pendingPeople = _groupDuesByPerson(pendingDues).keys;
          final pendingAccounts = <String, List<Due>>{
            for (final key in pendingPeople) key: allAccounts[key]!,
          };
          final settledAccounts = _groupDuesByPerson(settledDues)
            ..removeWhere((key, _) => pendingAccounts.containsKey(key));

          final totalLent = pendingDues
              .where((d) => d.direction == 'lent')
              .fold(0.0, (acc, d) => acc + d.amount);
          final totalBorrowed = pendingDues
              .where((d) => d.direction == 'borrowed')
              .fold(0.0, (acc, d) => acc + d.amount);
          final netBalance = totalLent - totalBorrowed;

          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 84),
            children: [
              // Summary Balance Card
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [const Color(0xFF232230), const Color(0xFF191823)]
                          : [
                              theme.colorScheme.primary.withOpacity(0.08),
                              theme.colorScheme.secondary.withOpacity(0.04),
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.primary.withOpacity(0.18),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'NET BALANCE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                  color: isDark
                                      ? const Color(0xFF9CA3AF)
                                      : const Color(0xFF6B7280),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${netBalance >= 0 ? '+' : '-'}₹${netBalance.abs().toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: netBalance >= 0
                                      ? Colors.green
                                      : Colors.redAccent,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (netBalance >= 0
                                          ? Colors.green
                                          : Colors.redAccent)
                                      .withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              netBalance >= 0 ? 'You are owed' : 'You owe',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: netBalance >= 0
                                    ? Colors.green
                                    : Colors.redAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.14),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 14,
                                    color: Colors.green,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Owed to you',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      '₹${totalLent.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.14),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.arrow_downward_rounded,
                                    size: 14,
                                    color: Colors.redAccent,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'You owe',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      '₹${totalBorrowed.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Active person accounts
              if (pendingAccounts.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
                  child: Row(
                    children: [
                      Text(
                        'People with balances',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${pendingAccounts.length}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ...pendingAccounts.values.map(
                  (account) => _buildAccountCard(context, account, theme),
                ),
              ],

              // Settled people accounts
              if (settledAccounts.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 6),
                  child: Row(
                    children: [
                      Text(
                        'Settled Accounts',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? const Color(0xFF9CA3AF)
                              : const Color(0xFF6B7280),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${settledAccounts.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ...settledAccounts.values.map(
                  (account) => _buildAccountCard(context, account, theme),
                ),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              'Error loading dues: $error',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const DueDetailScreen()));
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Due'),
      ),
    );
  }

  Widget _buildAccountCard(
    BuildContext context,
    List<Due> transactions,
    ThemeData theme,
  ) {
    final personName = transactions.first.personName;
    final activeTransactions = transactions
        .where((due) => due.status != 'settled')
        .toList();
    final lent = activeTransactions
        .where((due) => due.direction == 'lent')
        .fold<double>(0, (sum, due) => sum + due.amount);
    final borrowed = activeTransactions
        .where((due) => due.direction == 'borrowed')
        .fold<double>(0, (sum, due) => sum + due.amount);
    final balance = lent - borrowed;
    final balanceColor = balance > 0
        ? Colors.green
        : balance < 0
        ? Colors.redAccent
        : theme.colorScheme.onSurfaceVariant;
    final balanceLabel = activeTransactions.isEmpty
        ? 'Settled'
        : balance > 0
        ? 'They owe you'
        : balance < 0
        ? 'You owe them'
        : 'Even balance';
    final historyLabel = activeTransactions.isEmpty
        ? 'Settled'
        : '$balanceLabel · ${activeTransactions.length} open ${activeTransactions.length == 1 ? 'entry' : 'entries'}';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PersonDuesAccountScreen(personName: personName),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: balanceColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  balance == 0
                      ? Icons.account_balance_wallet_outlined
                      : Icons.person_outline_rounded,
                  color: balanceColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      personName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      historyLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${balance.abs().toStringAsFixed(2)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: balanceColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PersonDuesAccountScreen extends ConsumerStatefulWidget {
  const PersonDuesAccountScreen({super.key, required this.personName});

  final String personName;

  @override
  ConsumerState<PersonDuesAccountScreen> createState() =>
      _PersonDuesAccountScreenState();
}

class _PersonDuesAccountScreenState
    extends ConsumerState<PersonDuesAccountScreen> {
  bool _isSettling = false;

  Future<void> _settleAccount(List<Due> activeDues) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Settle this account?'),
        content: Text(
          'This closes ${activeDues.length} open entries for '
          '${widget.personName}. The person stays in your settled accounts. '
          'You can remove them separately after settlement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Settle account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSettling = true);
    try {
      final repository = ref.read(duesRepositoryProvider);
      for (final due in activeDues) {
        await repository.settleDue(due.id, createNextRecurring: false);
      }
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(content: Text('${widget.personName} account settled.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not settle the full account: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSettling = false);
    }
  }

  Future<void> _removePerson(List<Due> transactions) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${widget.personName}?'),
        content: Text(
          'This permanently removes ${widget.personName} and all '
          '${transactions.length} saved account entries. The expense total '
          'will no longer include this person’s balance entries.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove person'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSettling = true);
    try {
      final repository = ref.read(duesRepositoryProvider);
      for (final due in transactions) {
        await repository.deleteDue(due.id);
      }
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(content: Text('${widget.personName} was removed.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not fully remove ${widget.personName}: $error',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSettling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duesAsync = ref.watch(duesStreamProvider);

    return Scaffold(
      appBar: AppBar(title: Text('${widget.personName} account')),
      body: duesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
        data: (allDues) {
          final transactions =
              allDues
                  .where(
                    (due) =>
                        due.personName.trim().toLowerCase() ==
                        widget.personName.trim().toLowerCase(),
                  )
                  .toList()
                ..sort(
                  (a, b) => b.transactionDate.compareTo(a.transactionDate),
                );
          final activeDues = transactions
              .where((due) => due.status != 'settled')
              .toList();
          final owedToYou = activeDues
              .where((due) => due.direction == 'lent')
              .fold<double>(0, (sum, due) => sum + due.amount);
          final youOwe = activeDues
              .where((due) => due.direction == 'borrowed')
              .fold<double>(0, (sum, due) => sum + due.amount);
          final net = owedToYou - youOwe;
          final label = net > 0
              ? 'They owe you'
              : net < 0
              ? 'You owe them'
              : 'Even balance';
          final balanceColor = net > 0
              ? Colors.green
              : net < 0
              ? Colors.redAccent
              : theme.colorScheme.onSurfaceVariant;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: balanceColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₹${net.abs().toStringAsFixed(2)}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: balanceColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _OutstandingAmount(
                              label: 'Owed to you',
                              amount: owedToYou,
                              color: Colors.green,
                            ),
                          ),
                          Expanded(
                            child: _OutstandingAmount(
                              label: 'You owe',
                              amount: youOwe,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Open transactions',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${activeDues.length} entries',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (activeDues.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No open entries. This person stays saved in Settled Accounts.',
                    ),
                  ),
                )
              else
                SizedBox(
                  height: (MediaQuery.sizeOf(context).height * 0.42).clamp(
                    180.0,
                    400.0,
                  ),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: activeDues.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 2),
                    itemBuilder: (context, index) {
                      final due = activeDues[index];
                      final isBorrowed = due.direction == 'borrowed';
                      final isSettled = due.status == 'settled';
                      final tint = isSettled
                          ? theme.colorScheme.onSurfaceVariant
                          : isBorrowed
                          ? Colors.redAccent
                          : Colors.green;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DueDetailScreen(due: due),
                            ),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: tint.withOpacity(0.12),
                            child: Icon(
                              isSettled
                                  ? Icons.check_rounded
                                  : isBorrowed
                                  ? Icons.south_west_rounded
                                  : Icons.north_east_rounded,
                              color: tint,
                            ),
                          ),
                          title: Text(
                            '${isBorrowed ? 'I owe them' : 'They owe me'} · ₹${due.amount.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: tint,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            '${due.reason?.trim().isNotEmpty == true ? '${due.reason} · ' : ''}${due.transactionDate.day}/${due.transactionDate.month}/${due.transactionDate.year}${isSettled ? ' · Settled' : ''}',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                        ),
                      );
                    },
                  ),
                ),
              if (activeDues.isNotEmpty) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _isSettling
                      ? null
                      : () => _settleAccount(activeDues),
                  icon: _isSettling
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('Settle account'),
                ),
              ],
              if (transactions.isNotEmpty && activeDues.isEmpty) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isSettling
                      ? null
                      : () => _removePerson(transactions),
                  icon: const Icon(Icons.person_remove_outlined),
                  label: const Text('Remove person & history'),
                ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                DueDetailScreen(initialPersonName: widget.personName),
          ),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add transaction'),
      ),
    );
  }
}

class DueDetailScreen extends ConsumerStatefulWidget {
  final Due? due;
  final String? initialPersonName;

  const DueDetailScreen({super.key, this.due, this.initialPersonName});

  @override
  ConsumerState<DueDetailScreen> createState() => _DueDetailScreenState();
}

class _DueDetailScreenState extends ConsumerState<DueDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _personName;
  late double _amount;
  late String _direction;
  String? _reason;
  DateTime? _dueDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _personName = widget.due?.personName ?? widget.initialPersonName ?? '';
    _amount = widget.due?.amount ?? 0.0;
    _direction = widget.due?.direction ?? 'lent';
    _reason = widget.due?.reason;

    if (widget.due?.dueDate != null) {
      _dueDate = tz.TZDateTime.from(
        widget.due!.dueDate!,
        AppTimezone.businessLocation,
      );
    }
  }

  Future<void> _saveDue() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isSaving = true);

    DateTime? finalDueDate;
    if (_dueDate != null) {
      finalDueDate = AppTimezone.createBusinessEventTime(
        _dueDate!.year,
        _dueDate!.month,
        _dueDate!.day,
        23,
        59,
      );
    }

    final repo = ref.read(duesRepositoryProvider);
    final reasonVal = _reason?.trim().isEmpty == true ? null : _reason?.trim();

    try {
      if (widget.due == null) {
        await repo.createDue(
          personName: _personName.trim(),
          amount: _amount,
          direction: _direction,
          reason: reasonVal,
          dueDate: finalDueDate,
          transactionDate: DateTime.now().toUtc(),
        );
      } else {
        await repo.updateDue(
          widget.due!.id,
          personName: _personName.trim(),
          amount: _amount,
          direction: _direction,
          reason: reasonVal,
          dueDate: finalDueDate,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save due: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Due Entry'),
        content: const Text(
          'Are you sure you want to delete this transaction record?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(duesRepositoryProvider).deleteDue(widget.due!.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.due == null ? 'New Due Entry' : 'Edit Due Entry'),
        actions: [
          if (widget.due != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Delete',
              onPressed: _confirmDelete,
            ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: _isSaving
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.check_rounded),
                    tooltip: 'Save',
                    onPressed: _saveDue,
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Direction Selector
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'lent',
                    label: Text('They owe me'),
                    icon: Icon(Icons.arrow_upward_rounded, color: Colors.green),
                  ),
                  ButtonSegment(
                    value: 'borrowed',
                    label: Text('I owe them'),
                    icon: Icon(
                      Icons.arrow_downward_rounded,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
                selected: {_direction},
                onSelectionChanged: (newSelection) {
                  setState(() => _direction = newSelection.first);
                },
              ),
              const SizedBox(height: 18),
              TextFormField(
                initialValue: _personName,
                decoration: const InputDecoration(
                  labelText: 'Person Name',
                  prefixIcon: Icon(Icons.person_rounded),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (val) => val == null || val.trim().isEmpty
                    ? 'Please enter person\'s name'
                    : null,
                onSaved: (val) => _personName = val!,
              ),
              const SizedBox(height: 14),
              TextFormField(
                initialValue: widget.due == null ? '' : _amount.toString(),
                decoration: const InputDecoration(
                  labelText: 'Amount (₹)',
                  prefixIcon: Icon(Icons.currency_rupee_rounded),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty)
                    return 'Please enter amount';
                  final parsed = double.tryParse(val.trim());
                  if (parsed == null || parsed <= 0)
                    return 'Please enter a valid positive amount';
                  return null;
                },
                onSaved: (val) => _amount = double.parse(val!.trim()),
              ),
              const SizedBox(height: 14),
              TextFormField(
                initialValue: _reason,
                decoration: const InputDecoration(
                  labelText: 'Note / Reason (Optional)',
                  prefixIcon: Icon(Icons.note_rounded),
                ),
                onSaved: (val) => _reason = val,
              ),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(
                    Icons.calendar_month_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(
                    _dueDate == null
                        ? 'Set Due Date'
                        : 'Due Date: ${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}',
                    style: TextStyle(
                      fontWeight: _dueDate == null
                          ? FontWeight.normal
                          : FontWeight.w600,
                    ),
                  ),
                  trailing: _dueDate != null
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () => setState(() => _dueDate = null),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final nowTz = AppTimezone.businessNow();
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _dueDate ?? nowTz,
                      firstDate: nowTz.subtract(const Duration(days: 365)),
                      lastDate: DateTime(2100),
                    );
                    if (date != null) setState(() => _dueDate = date);
                  },
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _isSaving ? null : _saveDue,
                icon: const Icon(Icons.check_rounded),
                label: Text(
                  widget.due == null ? 'Record Transaction' : 'Save Changes',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutstandingAmount extends StatelessWidget {
  const _OutstandingAmount({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
