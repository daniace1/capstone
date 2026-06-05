import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'rutina_view.dart';
import 'perfil_form_view.dart';
import 'data_service.dart'; // Tu archivo donde pusimos las 3 funciones
import 'gemini_service.dart'; // Donde tienes la lógica de Groq
import 'dart:convert';

class PerfilView extends StatefulWidget {
  const PerfilView({Key? key}) : super(key: key);

  @override
  State<PerfilView> createState() => _PerfilViewState();
}

class _PerfilViewState extends State<PerfilView> {
  final _supabase = Supabase.instance.client;
  final int? idUsuarioPrueba = 1; // Usuario fijo para pruebas

  Map<String, dynamic>? datosUsuario;
  List<Map<String, dynamic>> _ejerciciosCompletados = [];
  bool cargandoUsuario = true;
  bool cargandoHistorial = true;
  bool tieneRutina = false;

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario();
    _cargarHistorialDetecciones();
    _verificarRutinaExistente();
  }

  Future<void> _cargarDatosUsuario() async {
    if (idUsuarioPrueba == null) return;
    setState(() => cargandoUsuario = true);

    try {
      final res = await _supabase
          .from('perfiles')
          .select()
          .eq('id', idUsuarioPrueba!)
          .maybeSingle();

      setState(() {
        datosUsuario = res;
        cargandoUsuario = false;
      });
    } catch (e) {
      print("Error al cargar datos de usuario: $e");
      setState(() => cargandoUsuario = false);
    }
  }

  

  Future<void> _cargarHistorialDetecciones() async {
    if (idUsuarioPrueba == null) return;
    setState(() => cargandoHistorial = true);

    try {
      final historialRes = await _supabase
          .from('historial_detecciones')
          .select('maquinas(id, nombre, grupo_muscular, descripcion)')
          .eq('usuario_id', idUsuarioPrueba!);

      List<Map<String, dynamic>> listaTemporal = [];

      if (historialRes != null) {
        for (var item in historialRes as List) {
          if (item['maquinas'] != null) {
            listaTemporal.add(item['maquinas'] as Map<String, dynamic>);
          }
        }
      }

      setState(() {
        _ejerciciosCompletados = listaTemporal;
        cargandoHistorial = false;
      });
    } catch (e) {
      print("Error al cargar historial de detecciones: $e");
      setState(() => cargandoHistorial = false);
    }
  }

  Future<void> _confirmarEliminacion(Map<String, dynamic> maquina, StateSetter setModalState) async {
    final String nombreMaquina = maquina['nombre']?.toString() ?? 'Máquina';
    final int? maquinaId = int.tryParse(maquina['id']?.toString() ?? '');

    if (maquinaId == null) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Eliminar Máquina', style: TextStyle(color: Colors.white)),
        content: Text(
          '¿Estás seguro de que deseas eliminar "$nombreMaquina" de tu lista detectada?',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        await _supabase
            .from('historial_detecciones')
            .delete()
            .eq('usuario_id', idUsuarioPrueba!)
            .eq('maquina_id', maquinaId);

        setState(() {
          _ejerciciosCompletados.removeWhere((m) => m['id'] == maquinaId);
        });

        setModalState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$nombreMaquina" eliminada correctamente.')),
        );
      } catch (e) {
        print("Error al eliminar máquina: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo eliminar la máquina.')),
        );
      }
    }
  }

  void _verMaquinasDetectadas() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text(
                    'Mis Máquinas Detectadas',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (cargandoHistorial)
                    const Center(child: CircularProgressIndicator(color: Colors.amber))
                  else if (_ejerciciosCompletados.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32.0),
                      child: Text(
                        'Aún no has detectado ninguna máquina.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: _ejerciciosCompletados.length,
                        itemBuilder: (context, index) {
                          final maquina = _ejerciciosCompletados[index];
                          final String nombreMaquina = maquina['nombre']?.toString() ?? 'Máquina genérica';
                          final String grupoMuscular = maquina['grupo_muscular']?.toString() ?? 'General';

                          return ListTile(
                            leading: const Icon(Icons.fitness_center, color: Colors.amber),
                            title: Text(
                              nombreMaquina,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              grupoMuscular,
                              style: const TextStyle(color: Colors.grey),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.redAccent),
                              onPressed: () => _confirmarEliminacion(maquina, setModalState),
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


  Future<void> _verificarRutinaExistente() async {
    final res = await _supabase
        .from('rutinas') // Asegúrate que este nombre de tabla sea el correcto
        .select('id')
        .eq('usuario_id', idUsuarioPrueba!)
        .maybeSingle();

    setState(() {
      tieneRutina = res != null;
    });
  }


  Future<void> _ejecutarAnalisisMensual(BuildContext context, double pesoActual) async {
    final usuarioId = idUsuarioPrueba; 
    final reporte = await DataService.obtenerAnalisisMensual(
    usuarioId.toString(), 
    pesoActual // <--- El double que capturaste del TextField
);

    if (usuarioId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Usuario no identificado")));
      return;
    }

    // --- PASO 1: VALIDACIÓN DE ANTIGÜEDAD (Mínimo 20 días) ---
    try {
      final primerRegistro = await Supabase.instance.client
          .from('historial_misiones')
          .select('fecha_completada')
          .eq('usuario_id', usuarioId)
          .order('fecha_completada', ascending: true)
          .limit(1)
          .single();

      final fechaInicio = DateTime.parse(primerRegistro['fecha_completada'] as String);
      final diasDeUso = DateTime.now().difference(fechaInicio).inDays;

      if (diasDeUso < 20) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("⚠️ Necesitas al menos 20 días de historial. Llevas $diasDeUso días.")),
        );
        return;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No encontramos historial suficiente para el análisis.")));
      return;
    }
    // --- FIN PASO 1 ---

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final reporte = await DataService.prepararReporteParaIA(usuarioId.toString());
      final datosParaIA = jsonEncode(reporte);
      final analisisFinal = await GeminiService().analizarProgresoMensual(
        datosParaIA, 
        pesoActual // Asegúrate de que esta variable 'pesoActual' exista en tu contexto
      );

      Navigator.pop(context); // Quitar loading

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Tu Análisis Mensual"),
          content: SingleChildScrollView(child: Text(analisisFinal)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cerrar"))
          ],
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      print("Error en análisis: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Mi Perfil Fitness', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.amber),
            onPressed: () async {
              final resultado = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PerfilFormView(datosActuales: datosUsuario),
                ),
              );
              if (resultado == true) {
                _cargarDatosUsuario();
              }
            },
          )
        ],
      ),
      body: cargandoUsuario
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),
                  const CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.amber,
                    child: Icon(Icons.person, size: 60, color: Color(0xFF121212)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    datosUsuario?['nombre'] ?? 'Usuario de Prueba',
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    datosUsuario?['nivel'] ?? 'Nivel no definido',
                    style: const TextStyle(color: Colors.amber, fontSize: 16, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 32),
                  _buildInfoCard(),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: const Color(0xFF121212),
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.remove_red_eye),
                    label: const Text('Ver Máquinas Detectadas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    onPressed: _verMaquinasDetectadas,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tieneRutina ? Colors.green : const Color(0xFF1E1E1E),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: tieneRutina ? Colors.green : Colors.amber, width: 1),
                      ),
                    ),
                    icon: Icon(tieneRutina ? Icons.visibility : Icons.smart_toy, color: Colors.white),
                    label: Text(
                      tieneRutina ? 'Ver Rutina' : 'Generar Rutina con IA',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      if (tieneRutina) {
                        // Si ya tiene, solo navegar
                        Navigator.push(context, MaterialPageRoute(builder: (context) => RutinaView(datosUsuario: datosUsuario, maquinas: _ejerciciosCompletados)));
                      } else {
                        // SI NO TIENE: GENERAR AUTOMÁTICAMENTE
                        setState(() => cargandoUsuario = true); // Indicamos que estamos trabajando
                        
                        try {
                          // 1. Llamar a Groq (GeminiService)
                          final String jsonString = await GeminiService().generarRutinaIA(
                            nombre: datosUsuario?['nombre'] ?? 'Usuario',
                            peso: (datosUsuario?['peso'] ?? 0).toDouble(),
                            altura: (datosUsuario?['altura'] ?? 0).toDouble(),
                            objetivo: datosUsuario?['meta'] ?? 'Resistencia',
                            nivel: datosUsuario?['nivel'] ?? 'Intermedio',
                            diasDisponibles: datosUsuario?['dias_disponibles'] ?? 3,
                            limitaciones: datosUsuario?['limitaciones'] ?? 'Ninguna',
                            maquinasDisponibles: _ejerciciosCompletados.map((item) {
                            return {
                              'nombre': item['nombre']?.toString() ?? '',
                              'grupo_muscular': item['grupo_muscular']?.toString() ?? '',
                              'descripcion': item['descripcion']?.toString() ?? '',
                            };
                         }).toList(),
                          );

                          // 2. Guardar en BD (DataService)
                          final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
                          await DataService.procesarYGuardarRutinaIA(jsonMap, idUsuarioPrueba!);

                          // 3. Actualizar UI y navegar
                          setState(() {
                            tieneRutina = true;
                            cargandoUsuario = false;
                          });
                          
                          Navigator.push(context, MaterialPageRoute(builder: (context) => RutinaView(datosUsuario: datosUsuario, maquinas: _ejerciciosCompletados)));
                        
                        } catch (e) {
                          setState(() => cargandoUsuario = false);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al generar la rutina. Intenta de nuevo.')));
                        }
                      }
                    },
                    
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2C2C2C),
                      foregroundColor: Colors.amber,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: Colors.amber, width: 1),
                    ),
                    icon: const Icon(Icons.analytics_outlined),
                    label: const Text('ANÁLISIS MENSUAL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      final pesoController = TextEditingController();
                      
                      // Abrir diálogo para pedir peso
                      final pesoInput = await showDialog<String>(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: const Color(0xFF1E1E1E),
                          title: const Text("Peso Actual (kg)", style: TextStyle(color: Colors.white)),
                          content: TextField(
                            controller: pesoController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: "Ej: 98.5",
                              hintStyle: TextStyle(color: Colors.grey),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
                            ),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                              onPressed: () => Navigator.pop(context, pesoController.text),
                              child: const Text("Analizar", style: TextStyle(color: Colors.black)),
                            ),
                          ],
                        ),
                      );

                      // Si el usuario ingresó algo, ejecutamos el análisis con ese dato
                      if (pesoInput != null && pesoInput.isNotEmpty) {
                        final double? pesoActual = double.tryParse(pesoInput);
                        if (pesoActual != null) {
                          // Llamamos a la función pasándole el peso
                          _ejecutarAnalisisMensual(context, pesoActual);
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildInfoRow(Icons.fitness_center, 'Objetivo', datosUsuario?['meta'] ?? 'No indicado'),
            const Divider(color: Colors.grey),
            _buildInfoRow(Icons.straighten, 'Altura', '${datosUsuario?['altura'] ?? '--'} m'),
            const Divider(color: Colors.grey),
            _buildInfoRow(Icons.monitor_weight, 'Peso', '${datosUsuario?['peso'] ?? '--'} kg'),
            const Divider(color: Colors.grey),
            _buildInfoRow(Icons.calendar_month, 'Días disponibles', '${datosUsuario?['dias_disponibles'] ?? '--'} días'),
            const Divider(color: Colors.grey),
            _buildInfoRow(Icons.warning, 'Limitaciones', datosUsuario?['limitaciones'] ?? 'Ninguna'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.amber, size: 24),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 16)),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
        
      ),
    );
  }
  
}