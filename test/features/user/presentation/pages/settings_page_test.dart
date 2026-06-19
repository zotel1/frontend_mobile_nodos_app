import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/bloc/user_bloc.dart';

// Will be created after writing this test
// ignore: depend_on_referenced_packages
import 'package:frontend_mobile_nodos_app/features/user/presentation/pages/settings_page.dart';

@GenerateNiceMocks([MockSpec<UserBloc>()])
import 'settings_page_test.mocks.dart';

final _testUser = User(
  uuid: 'test-uuid',
  name: 'Test User',
  color: '#2196F3',
  deviceType: 'android',
  createdAt: DateTime(2026, 1, 1),
);

Widget _pumpSettingsPage({required UserState userState}) {
  final mockUserBloc = MockUserBloc();

  when(mockUserBloc.state).thenReturn(userState);
  when(mockUserBloc.stream).thenAnswer((_) => Stream.value(userState));

  return MaterialApp(
    home: BlocProvider<UserBloc>.value(
      value: mockUserBloc,
      child: const SettingsPage(),
    ),
  );
}

void main() {
  group('SettingsPage', () {
    testWidgets('shows user name TextFormField when loaded', (tester) async {
      await tester.pumpWidget(_pumpSettingsPage(
        userState: UserLoaded(_testUser),
      ));

      // Finds a TextFormField containing the user name.
      final nameField = find.byWidgetPredicate(
        (widget) => widget is TextFormField,
      );
      expect(nameField, findsOneWidget);

      // The TextFormField should show the user's name.
      // We need to pump to let the initialValue settle.
      final editable = tester.widget<TextFormField>(nameField);
      expect(editable.initialValue, _testUser.name);
    });

    testWidgets('shows CircularProgressIndicator when loading', (tester) async {
      await tester.pumpWidget(_pumpSettingsPage(
        userState: const UserLoading(),
      ));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error text when error state', (tester) async {
      await tester.pumpWidget(_pumpSettingsPage(
        userState: const UserError('Save failed'),
      ));

      expect(find.text('Error: Save failed'), findsOneWidget);
    });

    testWidgets('save button dispatches UpdateUserNameEvent', (tester) async {
      final mockUserBloc = MockUserBloc();

      when(mockUserBloc.state).thenReturn(UserLoaded(_testUser));
      when(mockUserBloc.stream)
          .thenAnswer((_) => Stream.value(UserLoaded(_testUser)));

      await tester.pumpWidget(MaterialApp(
        home: BlocProvider<UserBloc>.value(
          value: mockUserBloc,
          child: const SettingsPage(),
        ),
      ));

      // Enter new text.
      final textField = find.byType(TextFormField);
      await tester.enterText(textField, 'New Name');
      await tester.pump();

      // Tap save button.
      final saveButton = find.widgetWithText(ElevatedButton, 'Guardar');
      expect(saveButton, findsOneWidget);
      await tester.tap(saveButton);
      await tester.pump();

      // Verify event dispatched.
      verify(mockUserBloc.add(const UpdateUserNameEvent('New Name')))
          .called(1);
    });

    testWidgets('shows ColorPicker when loaded', (tester) async {
      await tester.pumpWidget(_pumpSettingsPage(
        userState: UserLoaded(_testUser),
      ));

      // The ColorPicker is a Wrap with GestureDetector widgets (color circles).
      // We verify it's rendered by checking for the color label.
      expect(find.text('Color personalizado'), findsOneWidget);
    });

    // ─── Tema (Dark Mode) ──────────────────────────────────
    // QUÉ: verifica que el toggle de tema es visible y funcional
    // POR QUÉ: el usuario debe poder elegir entre sistema/claro/oscuro
    //   desde SettingsPage. Cada selección despacha UpdateThemeMode.

    testWidgets('muestra toggle de tema con opciones Sistema/Claro/Oscuro',
        (tester) async {
      await tester.pumpWidget(_pumpSettingsPage(
        userState: UserLoaded(_testUser),
      ));

      // Verifica que los labels de las opciones están visibles.
      expect(find.text('Sistema'), findsOneWidget);
      expect(find.text('Claro'), findsOneWidget);
      expect(find.text('Oscuro'), findsOneWidget);
    });

    testWidgets('seleccionar Oscuro despacha UpdateThemeMode con dark',
        (tester) async {
      final mockUserBloc = MockUserBloc();

      when(mockUserBloc.state).thenReturn(UserLoaded(_testUser));
      when(mockUserBloc.stream)
          .thenAnswer((_) => Stream.value(UserLoaded(_testUser)));

      await tester.pumpWidget(MaterialApp(
        home: BlocProvider<UserBloc>.value(
          value: mockUserBloc,
          child: const SettingsPage(),
        ),
      ));

      // Toca la opción "Oscuro".
      await tester.tap(find.text('Oscuro'));
      await tester.pump();

      // Verifica que UpdateThemeMode fue despachado con ThemeMode.dark.
      verify(mockUserBloc.add(const UpdateThemeMode(ThemeMode.dark)))
          .called(1);
    });

    testWidgets('seleccionar Sistema despacha UpdateThemeMode con system',
        (tester) async {
      final mockUserBloc = MockUserBloc();

      // Siembra con themeMode=dark para que Sistema NO esté ya
      // seleccionado (SegmentedButton ignora taps en el valor ya activo).
      when(mockUserBloc.state)
          .thenReturn(UserLoaded(_testUser, themeMode: ThemeMode.dark));
      when(mockUserBloc.stream).thenAnswer(
          (_) => Stream.value(UserLoaded(_testUser, themeMode: ThemeMode.dark)));

      await tester.pumpWidget(MaterialApp(
        home: BlocProvider<UserBloc>.value(
          value: mockUserBloc,
          child: const SettingsPage(),
        ),
      ));

      // Toca la opción "Sistema".
      await tester.tap(find.text('Sistema'));
      await tester.pump();

      // Verifica que UpdateThemeMode fue despachado con ThemeMode.system.
      verify(mockUserBloc.add(const UpdateThemeMode(ThemeMode.system)))
          .called(1);
    });
  });
}
