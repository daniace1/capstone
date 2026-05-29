import 'package:flutter/material.dart';
import 'package:ironlens/rutina_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'perfil_form_view.dart';

class PerfilView extends StatefulWidget {
  const PerfilView({Key? key}) : super(key: key);

  @override
  _PerfilViewState createState() => _PerfilViewState();
}



class _PerfilViewState extends State<PerfilView> {
  final int idUsuarioPrueba = 1; // Tu usuario manual de pruebas
  Map<String, dynamic>? datosUsuario;
  List<String> maquinasRegistradas = [];
  bool _isLoading = true;

  final SupabaseClient _supabase = Supabase.instance.client;
  bool _tieneRutinaGuardada = false;
  bool _checkingRutina = true;

  @override
  void initState() {
    super.initState();
    _cargarDatosDesdeSupabase();
    _revisarRutinaExistente();
  }

  // 1. Carga los datos del perfil y el historial cruzado desde Supabase
  Future<void> _cargarDatosDesdeSupabase() async {
    try {
      setState(() => _isLoading = true);

      // Cargar datos del usuario
      final perfilRes = await Supabase.instance.client
          .from('perfiles')
          .select()
          .eq('id', idUsuarioPrueba)
          .maybeSingle();

      // Cargar historial de máquinas vinculadas
      final historialRes = await Supabase.instance.client
          .from('historial_detecciones')
          .select('maquinas(nombre)')
          .eq('usuario_id', idUsuarioPrueba);

      List<String> listaTemporal = [];
      if (historialRes != null) {
        for (var item in historialRes as List) {
          if (item['maquinas'] != null) {
            listaTemporal.add(item['maquinas']['nombre'].toString());
          }
        }
      }

      setState(() {
        datosUsuario = perfilRes;
        maquinasRegistradas = listaTemporal;
        _isLoading = false;
      });
    } catch (e) {
      print("Error cargando perfil: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _revisarRutinaExistente() async {
    try {
      // Buscamos de forma preventiva si el usuario de pruebas ya tiene fila
      final response = await _supabase
          .from('rutinas')
          .select('id')
          .eq('usuario_id', idUsuarioPrueba) // Usamos tu variable idUsuarioPrueba
          .maybeSingle();

      setState(() {
        _tieneRutinaGuardada = response != null;
        _checkingRutina = false;
      });
    } catch (e) {
      print("Error chequeando rutina en perfil: $e");
      setState(() => _checkingRutina = false);
    }
  }

  // 2. Query que elimina la máquina directo en Supabase
  Future<void> _eliminarMaquinaDelHistorial(String nombreMaquina) async {
    try {
      final maquinaRes = await Supabase.instance.client
          .from('maquinas')
          .select('id')
          .eq('nombre', nombreMaquina)
          .maybeSingle();

      if (maquinaRes != null) {
        final int maquinaId = maquinaRes['id'];

        await Supabase.instance.client
            .from('historial_detecciones')
            .delete()
            .eq('usuario_id', idUsuarioPrueba)
            .eq('maquina_id', maquinaId);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("🗑️ '$nombreMaquina' eliminada correctamente."),
            backgroundColor: Colors.red[700],
          ),
        );

        // Recargamos los datos locales para refrescar la lista
        await _cargarDatosDesdeSupabase();
      }
    } catch (e) {
      print("Error al borrar máquina: $e");
    }
  }

  Future<void> _registrarMaquinaDetectada(int maquinaId) async {
    try {
      await Supabase.instance.client.from('historial_detecciones').insert({
        'usuario_id': idUsuarioPrueba, // Usamos tu variable ya definida
        'maquina_id': maquinaId,
        'creado_el': DateTime.now().toIso8601String(),
      });
      print("✅ Máquina registrada correctamente en historial_detecciones");
      
      // Al registrar, refrescamos la lista inmediatamente
      await _cargarDatosDesdeSupabase();
    } catch (e) {
      print("❌ Error al registrar máquina: $e");
    }
  }

  // 3. Modal Desplegable con la lista y los botones de basurero
  void _mostrarMaquinasModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "🏋️ Mis Máquinas Registradas",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        "${maquinasRegistradas.length} en total",
                        style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.grey),
                  const SizedBox(height: 10),
                  
                  if (maquinasRegistradas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text("No tienes máquinas registradas.", style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: maquinasRegistradas.length,
                        itemBuilder: (context, index) {
                          final nombreMaquina = maquinasRegistradas[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6.0),
                            child: Row(
                              children: [
                                const Icon(Icons.fitness_center, color: Colors.blueGrey, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    nombreMaquina,
                                    style: const TextStyle(fontSize: 16, color: Colors.white),
                                  ),
                                ),
                                const Icon(Icons.check_circle, color: Colors.green, size: 22),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                                  onPressed: () {
                                    _confirmarEliminacion(nombreMaquina, setModalState);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 4. Cartel de Confirmación de Borrado
  void _confirmarEliminacion(String nombreMaquina, StateSetter setModalState) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("¿Eliminar máquina?"),
          content: Text("¿Seguro que quieres sacar '$nombreMaquina' de tu lista registrada?"),
          actions: [
            TextButton(
              child: const Text("Cancelar"),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text("Eliminar", style: TextStyle(color: Colors.red)),
              onPressed: () async {
                Navigator.of(context).pop();
                await _eliminarMaquinaDelHistorial(nombreMaquina);
                setModalState(() {}); // Refresca el modal enseguida
              },
            ),
          ],
        );
      },
    );
  }

  // 5. El método auxiliar que dibuja los datos de Peso, Altura, etc.
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueGrey[400], size: 24),
          const SizedBox(width: 12),
          Text(
            "$label: ",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // 6. El método Build Limpio sin la lista duplicada en pantalla
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("IronLens AI"),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle, size: 30, color: Colors.orangeAccent),
            onPressed: () {
              // Esto abre tu archivo perfil_view.dart
              Navigator.push(context, MaterialPageRoute(builder: (context) => const PerfilView()));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 1. Tarjeta con los datos de Salud del Usuario
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Hola, ${datosUsuario?['nombre'] ?? 'Usuario'} 👋",
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () async {
                            final resultado = await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => PerfilFormView(datosActuales: datosUsuario)),
                            );
                            if (resultado == true) {
                              _cargarDatosDesdeSupabase(); 
                            }
                          },
                        )
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    _buildInfoRow(Icons.fitness_center, "Peso", "${datosUsuario?['peso'] ?? 0} kg"),
                    _buildInfoRow(Icons.height, "Altura", "${datosUsuario?['altura'] ?? 0} m"),
                    _buildInfoRow(Icons.track_changes, "Objetivo", datosUsuario?['meta'] ?? 'No definido'),
                    _buildInfoRow(Icons.bar_chart, "Nivel", datosUsuario?['nivel'] ?? 'No definido'),
                    _buildInfoRow(Icons.calendar_month, "Frecuencia", "${datosUsuario?['dias_disponibles'] ?? 0} días a la semana"),
                    _buildInfoRow(Icons.warning_amber, "Limitaciones", datosUsuario?['limitaciones'] ?? 'Ninguna'),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),

            // 2. Botón para ver las máquinas registradas en el modal
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: _mostrarMaquinasModal, 
                icon: const Icon(Icons.list_alt, color: Colors.white),
                label: const Text("VER MIS MÁQUINAS REGISTRADAS", style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey[800],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 3. NUEVO BOTÓN: Generar Rutina con IA (Nos lleva a la nueva vista pasándole los datos)
            _checkingRutina
                ? const Center(child: CircularProgressIndicator(color: Colors.blue))
                : SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        // Convertimos tu lista de textos simples a mapas
                        List<Map<String, dynamic>> maquinasParaEnviar = [];
                        for (var nombreMaquina in maquinasRegistradas) {
                          maquinasParaEnviar.add({
                            'nombre': nombreMaquina.toString(),
                            'grupo_muscular': 'Detectado',
                            'descripcion': 'Uso estándar en el gimnasio.'
                          });
                        }

                        // Forzamos el mapa con el ID estático 1 para las pruebas
                        Map<String, dynamic> datosConId = {
                          'id': 1,
                          'nombre': datosUsuario?['nombre'] ?? 'Usuario',
                          'peso': datosUsuario?['peso'],
                          'altura': datosUsuario?['altura'],
                          'meta': datosUsuario?['meta'],
                          'nivel': datosUsuario?['nivel'],
                          'dias_disponibles': datosUsuario?['dias_disponibles'],
                          'limitaciones': datosUsuario?['limitaciones'],
                        };

                        // Viajamos a la pantalla de la rutina
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (context) => RutinaView(
                              datosUsuario: datosConId,
                              maquinas: maquinasParaEnviar,
                            ),
                          ),
                        );

                        // Al regresar de la pantalla, refrescamos el estado del botón
                        _revisarRutinaExistente();
                      },
                      icon: Icon(
                        _tieneRutinaGuardada ? Icons.fitness_center : Icons.auto_awesome, 
                        color: Colors.white
                      ),
                      label: Text(
                        _tieneRutinaGuardada ? "VER MI RUTINA" : "GENERAR MI RUTINA IA",
                        style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _tieneRutinaGuardada ? Colors.green[800] : Colors.blue[800], // Verde si existe, Azul si es nueva
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
          ],
        ),
      ),
      // Pega esto justo antes del último } de tu Scaffold
    
    );
  }
}