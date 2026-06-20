import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/widgets/node_metadata_sheet.dart';

@GenerateNiceMocks([MockSpec<NodeListBloc>()])
import 'node_metadata_sheet_test.mocks.dart';

/// Tests del widget NodeMetadataSheet.
///
/// T3.5: Verifica que el TextField acepte entrada de nombre, que el
/// ColorPicker muestre opciones de color, y que el botón Guardar
/// despache los eventos UpdateNodeName y UpdateNodeColor al NodeListBloc.
void main() {
  late MockNodeListBloc mockNodeListBloc;

  setUp(() {
    mockNodeListBloc = MockNodeListBloc();
    when(mockNodeListBloc.state).thenReturn(const NodeListLoaded([]));
    when(mockNodeListBloc.stream)
        .thenAnswer((_) => Stream.value(const NodeListLoaded([])));
  });

  /// Helper que construye el bottom sheet directamente (sin showModalBottomSheet)
  /// para evitar problemas de overlay y contexto.
  Widget buildSheet(Node testNode) {
    return MaterialApp(
      home: Scaffold(
        body: NodeMetadataSheet(
          node: testNode,
          nodeListBloc: mockNodeListBloc,
        ),
      ),
    );
  }

  Node testNode({String? suggestedName}) => Node(
        id: 1,
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        name: null,
        color: '#2196F3',
        firstSeen: DateTime(2026, 1, 1),
        lastSeen: DateTime(2026, 6, 20),
        rssiHistory: const [-60],
        suggestedName: suggestedName,
      );

  group('NodeMetadataSheet', () {
    testWidgets('T3.5: TextField permite ingresar nombre', (tester) async {
      await tester.pumpWidget(buildSheet(testNode()));

      // Verificar que hay un TextField presente
      expect(find.byType(TextFormField), findsOneWidget);

      // Ingresar texto en el campo de nombre
      await tester.enterText(find.byType(TextFormField), 'Nodo Amigo');
      await tester.pump();

      // Verificar que el texto ingresado está presente
      expect(find.text('Nodo Amigo'), findsOneWidget);
    });

    testWidgets(
        'T3.5: TextField se pre-llena con suggestedName si existe',
        (tester) async {
      await tester.pumpWidget(
          buildSheet(testNode(suggestedName: 'Dispositivo BT')));

      // Verificar que el TextField tiene el suggestedName pre-llenado
      final textField =
          tester.widget<TextFormField>(find.byType(TextFormField));
      expect(textField.initialValue, equals('Dispositivo BT'));
    });

    testWidgets(
        'T3.5: botón Guardar despacha UpdateNodeName y UpdateNodeColor',
        (tester) async {
      await tester.pumpWidget(buildSheet(testNode()));

      // Ingresar nombre
      await tester.enterText(find.byType(TextFormField), 'Mi Nodo');
      await tester.pump();

      // Tocar el botón Guardar
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verificar que UpdateNodeName fue despachado
      verify(mockNodeListBloc.add(
        argThat(
          predicate((e) =>
              e is UpdateNodeName && e.nodeId == 1 && e.name == 'Mi Nodo'),
        ),
      )).called(1);

      // Verificar que UpdateNodeColor fue despachado
      verify(mockNodeListBloc.add(
        argThat(
          predicate((e) => e is UpdateNodeColor && e.nodeId == 1),
        ),
      )).called(1);
    });

    testWidgets('T3.5: ColorPicker muestra opciones de color',
        (tester) async {
      await tester.pumpWidget(buildSheet(testNode()));

      // Verificar que el ColorPicker está presente
      // El ColorPicker renderiza GestureDetector para cada color
      expect(find.byType(GestureDetector), findsWidgets);
    });
  });
}
