import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/logistics_provider.dart';
import '../widgets/delivery_note_card.dart';

class DeliveryNotesTabView extends StatefulWidget {
  final String status;

  const DeliveryNotesTabView({Key? key, required this.status}) : super(key: key);

  @override
  State<DeliveryNotesTabView> createState() => _DeliveryNotesTabViewState();
}

class _DeliveryNotesTabViewState extends State<DeliveryNotesTabView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    
    // Al inicializar el tab, verificamos si ya tiene datos. Si no, cargamos la primera página.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<LogisticsProvider>();
      if (!provider.getTabState(widget.status).isInitialized) {
        provider.fetchFirstPage(widget.status);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Infinite Scroll: cuando estemos al 85% del scroll, pedimos la siguiente página
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.85) {
      context.read<LogisticsProvider>().fetchNextPage(widget.status);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LogisticsProvider>(
      builder: (context, provider, child) {
        final state = provider.getTabState(widget.status);

        // Si es la primera carga (aún no inicializado)
        if (!state.isInitialized && state.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        // Si hay un error y no hay datos, mostrar el error en pantalla
        if (provider.errorMessage != null && state.notes.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${provider.errorMessage}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => provider.fetchFirstPage(widget.status),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          );
        }

        // Si ya cargó pero no hay datos
        if (state.notes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'No hay remitos en esta pestaña.',
                  style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }

        // Lista de datos
        return RefreshIndicator(
          onRefresh: () => provider.fetchFirstPage(widget.status),
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: state.notes.length + (state.hasMoreData ? 1 : 0),
            itemBuilder: (context, index) {
              // Si llegamos al final de la lista y hay más datos, mostramos el loader inferior
              if (index == state.notes.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final note = state.notes[index];
              return DeliveryNoteCard(note: note);
            },
          ),
        );
      },
    );
  }
}
