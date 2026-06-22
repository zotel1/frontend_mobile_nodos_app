import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend_mobile_nodos_app/core/utils/app_theme_mode.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/bloc/user_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/widgets/color_picker.dart';

/// User profile settings screen.
///
/// Allows configuring the user's display name and preferred color.
/// Reads [UserBloc] from the widget tree (provided by [MultiBlocProvider]
/// in app.dart).
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Load user profile on first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userBloc = context.read<UserBloc>();
      if (userBloc.state is! UserLoaded) {
        userBloc.add(const LoadProfile());
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: BlocBuilder<UserBloc, UserState>(
        builder: (context, state) {
          return switch (state) {
            UserLoading() =>
              const Center(child: CircularProgressIndicator()),
            UserError(:final message) => Center(
                child: Text(
                  'Error: $message',
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                ),
              ),
            UserLoaded(:final user) => _buildLoadedState(user),
            _ => const Center(child: Text('Cargando perfil...')),
          };
        },
      ),
    );
  }

  Widget _buildLoadedState(User user) {
    final userBloc = context.read<UserBloc>();
    // Obtiene el themeMode actual del estado para reflejarlo en el toggle.
    final currentThemeMode =
        (userBloc.state is UserLoaded) ? (userBloc.state as UserLoaded).themeMode : AppThemeMode.system;

    // QUÉ: Inicializa el controller SOLO si está vacío, para preservar
    // ediciones no guardadas frente a reemisiones de UserLoaded.
    // POR QUÉ: al usar controller en lugar de initialValue, el widget
    // no reinicia el texto en cada rebuild; debemos hacerlo manualmente
    // solo en la primera carga.
    if (_nameController.text.isEmpty) {
      _nameController.text = user.name;
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        const SizedBox(height: 24),
        // ─── Toggle de tema ──────────────────────────────────
        // QUÉ: SegmentedButton con 3 opciones de ThemeMode.
        // POR QUÉ: el usuario elige entre seguir al sistema,
        //   forzar claro o forzar oscuro. El estado se mantiene
        //   en memoria (UserBloc) sin persistir a DB (Phase 3).
        const Text(
          'Tema',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        SegmentedButton<AppThemeMode>(
          segments: const [
            ButtonSegment<AppThemeMode>(
              value: AppThemeMode.system,
              label: Text('Sistema'),
              icon: Icon(Icons.brightness_auto),
            ),
            ButtonSegment<AppThemeMode>(
              value: AppThemeMode.light,
              label: Text('Claro'),
              icon: Icon(Icons.brightness_5),
            ),
            ButtonSegment<AppThemeMode>(
              value: AppThemeMode.dark,
              label: Text('Oscuro'),
              icon: Icon(Icons.brightness_2),
            ),
          ],
          selected: {currentThemeMode},
          onSelectionChanged: (selected) {
            userBloc.add(UpdateThemeMode(selected.first));
          },
        ),
        const SizedBox(height: 24),
        const Text(
          'Color personalizado',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        ColorPicker(
          selectedColor: user.color,
          onColorSelected: (color) {
            userBloc.add(UpdateUserColorEvent(color));
          },
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () {
            final name = _nameController.text.isEmpty
                ? user.name
                : _nameController.text;
            userBloc.add(UpdateUserNameEvent(name));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
