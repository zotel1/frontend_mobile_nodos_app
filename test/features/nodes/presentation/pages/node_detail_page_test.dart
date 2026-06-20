import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/pages/node_detail_page.dart';

@GenerateNiceMocks([MockSpec<NodeListBloc>()])
import 'node_detail_page_test.mocks.dart';

/// Verifica que el botón "Enlazar" aparezca en NodeDetailPage y que
/// el callback onEnlazar se ejecute con el bleAddress correcto.
void main() {
  final testNode = Node(
    id: 1,
    bleAddress: 'AA:BB:CC:DD:EE:FF',
    name: 'Mi Dispositivo',
    firstSeen: DateTime(2026, 1, 1),
    lastSeen: DateTime(2026, 6, 19),
    rssiHistory: const [-45],
    suggestedName: 'Dispositivo Anunciado',
    deviceType: 'Auriculares',
  );

  testWidgets('T3.7: muestra botón Enlazar y el callback recibe bleAddress',
      (tester) async {
    final mockNodeListBloc = MockNodeListBloc();
    String? capturedBleAddress;

    when(mockNodeListBloc.state).thenReturn(NodeListLoaded([testNode]));
    when(mockNodeListBloc.stream)
        .thenAnswer((_) => Stream.value(NodeListLoaded([testNode])));

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<NodeListBloc>.value(
          value: mockNodeListBloc,
          child: NodeDetailPage(
            id: 1,
            onEnlazar: (bleAddress) {
              capturedBleAddress = bleAddress;
            },
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Verificar que la página se renderizó correctamente
    expect(find.text('Mi Dispositivo'), findsAtLeast(1));

    // El ListView tiene muchos elementos — el botón está al final.
    // Hacer scroll hacia abajo para hacerlo visible.
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 500));

    // Verificar que existe un ElevatedButton con icono link y texto Enlazar
    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(find.byIcon(Icons.link), findsOneWidget);
    expect(find.text('Enlazar'), findsOneWidget);

    // Presionar el botón
    await tester.tap(find.text('Enlazar'));
    await tester.pump();

    // Verificar que el callback recibió el bleAddress correcto
    expect(capturedBleAddress, equals('AA:BB:CC:DD:EE:FF'));
  });
}
