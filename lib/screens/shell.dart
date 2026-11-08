import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'home_screen.dart';
import 'plan_screen.dart';
import 'record_screen.dart';
import 'stats_screen.dart';
import 'workouts_screen.dart';

/// Navegação principal: Início, Treinos, [Gravar], Estatísticas, Plano.
class Shell extends StatefulWidget {
  const Shell({super.key});

  static void openRecord(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const RecordScreen()));
  }

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final msg = state.message;
    if (msg != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        state.clearMessage();
      });
    }

    const pages = [HomeScreen(), WorkoutsScreen(), StatsScreen(), PlanScreen()];
    return Scaffold(
      body: SafeArea(bottom: false, child: IndexedStack(index: _index, children: pages)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Shell.openRecord(context),
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Gravar'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'Treinos'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Estatísticas'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Plano'),
        ],
      ),
    );
  }
}
