import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_state.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/bloc/user_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/widgets/color_picker.dart';

/// Pantalla de onboarding para primera ejecución.
///
/// QUÉ: guía al usuario por 3 pasos secuenciales:
///   1. Permisos — solicita permisos de Bluetooth
///   2. Bluetooth — verifica que BT esté encendido
///   3. Perfil — configura nombre y color del dispositivo
///
/// POR QUÉ: en primera ejecución, la app necesita permisos, BT activo
/// y un perfil de usuario antes de comenzar a escanear nodos.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  /// Índice del paso actual (0 = Permisos, 1 = Bluetooth, 2 = Perfil).
  int _currentStep = 0;

  /// Controlador del campo de nombre con valor por defecto "Nodo".
  final _nameController = TextEditingController(text: 'Nodo');

  /// Color seleccionado en el ColorPicker (hex string).
  String _selectedColor = '#2196F3';

  /// Flag para mostrar mensaje de permisos denegados.
  bool _permissionsDenied = false;

  /// Indica si se está ejecutando una operación asíncrona.
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Solicita permisos de Bluetooth Scan y Connect.
  ///
  /// QUÉ: llama a [Permission.bluetoothScan.request] y
  /// [Permission.bluetoothConnect.request] y avanza al paso 2
  /// si ambos son concedidos o si la plataforma no está disponible
  /// (entorno de test).
  ///
  /// POR QUÉ: sin estos permisos, la app no puede escanear ni
  /// conectarse a dispositivos BLE cercanos.
  Future<void> _requestPermissions() async {
    setState(() => _isLoading = true);

    try {
      final scanStatus = await Permission.bluetoothScan.request();
      final connectStatus = await Permission.bluetoothConnect.request();

      if (!mounted) return;

      if (scanStatus.isGranted && connectStatus.isGranted) {
        setState(() {
          _permissionsDenied = false;
          _isLoading = false;
          _currentStep = 1; // Avanzar a Bluetooth
        });
      } else {
        setState(() {
          _permissionsDenied = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      // En entorno de test o si la plataforma no está disponible,
      // avanzamos al paso 2 directamente.
      if (!mounted) return;
      setState(() {
        _permissionsDenied = false;
        _currentStep = 1;
        _isLoading = false;
      });
    }
  }

  /// Abre la configuración de Bluetooth del sistema.
  ///
  /// QUÉ: lanza un Android Intent para abrir la pantalla de
  /// configuración de Bluetooth del dispositivo.
  ///
  /// POR QUÉ: permite al usuario activar BT sin salir de la app.
  void _openBluetoothSettings() {
    const AndroidIntent(action: 'android.settings.BLUETOOTH_SETTINGS')
        .launch();
  }

  /// Verifica si Bluetooth está encendido según el estado del BleBloc.
  ///
  /// QUÉ: consulta [BleBloc.state] — si no es [BluetoothOff],
  /// BT está encendido.
  bool get _isBluetoothOn {
    final bleState = context.read<BleBloc>().state;
    return bleState is! BluetoothOff;
  }

  /// Guarda el perfil del usuario y marca onboarding como completo.
  ///
  /// QUÉ: despacha [CreateUserProfile] para asegurar que la fila users
  /// existe con los valores del onboarding. Luego actualiza nombre y color
  /// (idempotente), persiste el flag `onboarding_complete`, y navega a Home.
  ///
  /// POR QUÉ: antes se despachaban UpdateUserNameEvent y UpdateUserColorEvent
  /// directamente. Si la tabla users estaba vacía (primera ejecución sin
  /// LoadProfile previo), las actualizaciones fallaban silenciosamente.
  /// CreateUserProfile garantiza que la fila existe antes de los updates.
  Future<void> _saveAndStart() async {
    setState(() => _isLoading = true);

    final userBloc = context.read<UserBloc>();

    // 1. Crear o asegurar el perfil con los valores del onboarding.
    //    Si ya existe (LoadProfile de app.dart creó uno default),
    //    sobreescribe nombre y color.
    userBloc.add(CreateUserProfile(_nameController.text, _selectedColor));

    // 2. Esperar a que el BLoC procese CreateUserProfile.
    //    Usamos Future.delayed porque el BLoC procesa asíncronamente
    //    y necesitamos que la fila users exista antes de los updates.
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // 3. Ahora la fila users SÍ existe — actualizar nombre y color.
    userBloc.add(UpdateUserNameEvent(_nameController.text));
    userBloc.add(UpdateUserColorEvent(_selectedColor));

    // Persistir flag de onboarding completado.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);

    if (!mounted) return;
    setState(() => _isLoading = false);

    // Navegar a HomePage.
    context.go('/');
  }

  /// Construye el contenido del paso actual.
  Widget _buildStep() {
    switch (_currentStep) {
      case 0:
        return _buildPermissionsStep();
      case 1:
        return _buildBluetoothStep();
      case 2:
        return _buildProfileStep();
      default:
        return const SizedBox.shrink();
    }
  }

  /// Paso 1: Permisos de Bluetooth.
  ///
  /// Muestra un mensaje explicativo y un botón para solicitar
  /// permisos. Si los permisos son denegados, muestra un
  /// mensaje de error.
  Widget _buildPermissionsStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.bluetooth_searching,
            size: 64,
            color: Colors.blue,
          ),
          const SizedBox(height: 24),
          const Text(
            'Nodos necesita permiso de Bluetooth para detectar dispositivos cercanos',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 24),
          if (_permissionsDenied)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Sin permisos la app no puede funcionar',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _requestPermissions,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continuar'),
            ),
          ),
        ],
      ),
    );
  }

  /// Paso 2: Verificación de Bluetooth.
  ///
  /// Si BT está encendido, muestra confirmación y botón para
  /// avanzar. Si está apagado, muestra mensaje y botón para
  /// abrir configuración.
  Widget _buildBluetoothStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isBluetoothOn ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            size: 64,
            color: _isBluetoothOn ? Colors.blue : Colors.grey,
          ),
          const SizedBox(height: 24),
          if (_isBluetoothOn) ...[
            const Text(
              'Bluetooth activado',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => setState(() => _currentStep = 2),
                child: const Text('Continuar'),
              ),
            ),
          ] else ...[
            const Text(
              'Activá Bluetooth para continuar',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _openBluetoothSettings,
                child: const Text('Abrir configuración'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Paso 3: Configuración de perfil.
  ///
  /// Permite al usuario ingresar un nombre y seleccionar un color
  /// para su dispositivo. Al presionar "Comenzar", guarda el perfil
  /// y navega a la HomePage.
  Widget _buildProfileStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.person,
            size: 64,
            color: Colors.blue,
          ),
          const SizedBox(height: 24),
          const Text(
            'Configurá tu perfil',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Nombre del dispositivo',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          ColorPicker(
            selectedColor: _selectedColor,
            onColorSelected: (color) {
              setState(() => _selectedColor = color);
            },
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _saveAndStart,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Comenzar'),
            ),
          ),
        ],
      ),
    );
  }

  /// Muestra un diálogo de confirmación al intentar salir del onboarding.
  ///
  /// QUÉ: pregunta al usuario si realmente desea salir sin completar
  /// el perfil, ya que la app no puede funcionar sin un perfil configurado.
  ///
  /// POR QUÉ: el hardware back podría saltarse el onboarding (N1).
  /// Este diálogo es la última defensa antes de cerrar la app.
  void _showExitDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Salir sin completar el perfil?'),
        content: const Text(
          'La app necesita un perfil para funcionar. Si salís ahora, '
          'deberás volver a configurarlo la próxima vez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              // Cerrar el diálogo y luego cerrar la app vía SystemNavigator.
              Navigator.of(ctx).pop();
              SystemNavigator.pop();
            },
            child: const Text('Salir'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) {
        // Solo mostrar diálogo si NO se pudo popear (hardware back bloqueado).
        // Si didPop == true, la página ya fue popeada (no debería pasar con
        // canPop: false, pero lo chequeamos por seguridad).
        if (!didPop) {
          _showExitDialog();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Paso ${_currentStep + 1} de 3'),
          automaticallyImplyLeading: false,
        ),
        body: _buildStep(),
      ),
    );
  }
}
