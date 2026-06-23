# ProGuard / R8 rules para Nodos App.
#
# PR9: Reglas keep para plugins Flutter que usan reflexión, code generation,
# o JNI (flutter_blue_plus, drift, permission_handler).
# Sin estas reglas, R8 puede eliminar clases necesarias en runtime.

# =============================================================================
# flutter_blue_plus (BLE plugin)
# =============================================================================
# flutter_blue_plus usa JNI y callbacks nativos que R8 no puede detectar como usados.
-keep class com.lib.flutter_blue_plus.** { *; }
-keep class com.boskokg.flutter_blue_plus.** { *; }

# =============================================================================
# Drift (SQLite ORM con generación de código)
# =============================================================================
# Drift genera clases SQL que son referenciadas por reflexión/annotations.
# mozilla/rust para sqflite_common_ffi (métodos nativos).
-keep class drift.** { *; }
-keep class sqflite.** { *; }
-keep class com.tekartik.sqflite.** { *; }

# =============================================================================
# permission_handler
# =============================================================================
# permission_handler registra callbacks nativos vía MethodChannel.
# Las clases de plugin deben conservarse completas para que el channel binding
# funcione correctamente.
-keep class com.baseflow.permissionhandler.** { *; }

# =============================================================================
# Reglas generales de Flutter
# =============================================================================
# Mantener código nativo de Flutter que usa JNI.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }

# Conservar anotaciones usadas en runtime por plugins.
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions
