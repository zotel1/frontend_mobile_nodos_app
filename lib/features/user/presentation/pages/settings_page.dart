import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextFormField(
          initialValue: user.name,
          decoration: const InputDecoration(labelText: 'Nombre'),
          onChanged: (value) {
            _nameController.text = value;
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
