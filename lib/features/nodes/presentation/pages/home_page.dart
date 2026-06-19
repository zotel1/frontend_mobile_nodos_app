import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_event.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_state.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/widgets/bluetooth_off_banner.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/widgets/node_tile.dart';

/// Main screen showing a list of detected BLE nodes.
///
/// Reads [NodeListBloc] and [BleBloc] from the widget tree (provided by
/// [MultiBlocProvider] in app.dart).
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final bleBloc = context.read<BleBloc>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nodos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: BlocBuilder<BleBloc, BleState>(
        builder: (context, bleState) {
          return Column(
            children: [
              if (bleState is BluetoothOff)
                BluetoothOffBanner(
                  onGoToSettings: () {
                    // Placeholder — system Bluetooth settings not opened here.
                  },
                ),
              Expanded(child: _buildNodeList()),
            ],
          );
        },
      ),
      floatingActionButton: BlocBuilder<BleBloc, BleState>(
        builder: (context, bleState) {
          final isScanning = bleState is BleScanning;
          return FloatingActionButton(
            onPressed: () {
              if (isScanning) {
                bleBloc.add(const StopScan());
              } else {
                bleBloc.add(const StartScan());
              }
            },
            tooltip: isScanning ? 'Detener escaneo' : 'Iniciar escaneo',
            child: Icon(isScanning ? Icons.stop : Icons.bluetooth_searching),
          );
        },
      ),
    );
  }

  Widget _buildNodeList() {
    return BlocBuilder<NodeListBloc, NodeListState>(
      builder: (context, state) {
        return switch (state) {
          NodeListLoading() =>
            const Center(child: CircularProgressIndicator()),
          NodeListEmpty() => const Center(
              child: Text(
                'No se encontraron nodos',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          NodeListLoaded(:final nodes) => ListView.builder(
              itemCount: nodes.length,
              itemBuilder: (context, index) => NodeTile(
                node: nodes[index],
                onTap: () => Navigator.pushNamed(
                  context,
                  '/node/${nodes[index].id}',
                ),
              ),
            ),
          NodeListError(:final message) => Center(
              child: Text(
                message,
                style: const TextStyle(color: Colors.red, fontSize: 16),
              ),
            ),
          _ => const SizedBox.shrink(),
        };
      },
    );
  }
}
