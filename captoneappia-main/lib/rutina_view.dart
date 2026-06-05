import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ironlens/data_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'gemini_service.dart';

class RutinaView extends StatefulWidget {
  final Map<String, dynamic>? datosUsuario;
  final List<Map<String, dynamic>> maquinas; // Se mantiene el nombre exacto de tu variable de máquinas

  const RutinaView({
    Key? key,
    required this.datosUsuario,
    required this.maquinas,
  }) : super(key: key);

  @override
  State<RutinaView> createState() => _RutinaViewState();
}

class _RutinaViewState extends State<RutinaView> {
  final GeminiService _geminiService = GeminiService();
  final _supabase = Supabase.instance.client;

  bool _cargando = false;
  Map<String, dynamic>? _rutinaJson;
  int? _idUsuario;
  int _diaActualUsuario = 1;
  
  Map<String, Map<String, bool>> _ejerciciosCompletados = {};

  @override
  void initState() {
    super.initState();
    _idUsuario = int.tryParse(widget.datosUsuario?['id']?.toString() ?? '1');
    _inicializarApp();
  }
  Future<void> _inicializarApp() async {
    await DataService.verificarCambioDeDia(); // Asegúrate de tener este método en DataService
    final perfil = await _supabase.from('perfiles').select('dia_actual_rutina').eq('id', 1).maybeSingle();
    setState(() => _diaActualUsuario = perfil?['dia_actual_rutina'] ?? 1);
    _cargarRutinaExistente();
  }

  Future<void> _cargarRutinaExistente() async {
    if (_idUsuario == null) return;
    setState(() => _cargando = true);
    print("====== [SUPABASE] Intentando cargar rutina para usuario_id: $_idUsuario ======");

    try {
      final res = await _supabase
          .from('rutinas')
          .select('contenido_rutina')
          .eq('usuario_id', _idUsuario!)
          .maybeSingle();

      if (res != null && res['contenido_rutina'] != null) {
        final rawJson = res['contenido_rutina'];
        Map<String, dynamic> decoded;
        if (rawJson is String) {
          decoded = jsonDecode(rawJson);
        } else {
          decoded = rawJson as Map<String, dynamic>;
        }

        setState(() {
          _rutinaJson = decoded;
          _inicializarChecklist(decoded);
        });
        print("====== [SUPABASE] Rutina cargada con éxito desde la base de datos ======");
      } else {
        print("====== [SUPABASE] No se encontró ninguna rutina previa para este usuario ======");
      }
    } catch (e) {
      print("❌ Error al cargar rutina existente: $e");
    } finally {
      setState(() => _cargando = false);
    }
  }

  Future<void> _inicializarChecklist(Map<String, dynamic> rutina) async {
    _ejerciciosCompletados.clear();
    
    // 1. Inicializar todo en false de forma segura
    final dias = rutina['dias'] as List? ?? [];
    for (var dia in dias) {
      String identificadorDia = "Día ${dia['dia_numero'] ?? '0'}";
      List ejercicios = dia['ejercicios'] ?? [];
      
      // Inicializamos el mapa vacío para este día
      _ejerciciosCompletados[identificadorDia] = {};
      
      for (var ej in ejercicios) {
        String nombreEj = ej['nombre_ejercicio'] ?? 'Ejercicio';
        _ejerciciosCompletados[identificadorDia]![nombreEj] = false;
      }
    }

    // 2. Consultar base de datos
    try {
      final historial = await _supabase
          .from('historial_misiones')
          .select('dia_numero, nombre_ejercicio')
          .eq('usuario_id', _idUsuario!);

      setState(() {
        for (var item in historial) {
          String diaKey = "Día ${item['dia_numero'] ?? '0'}";
          String nombreEj = item['nombre_ejercicio'];
          
          // Si el día y el ejercicio existen en nuestra estructura, los marcamos como true
          if (_ejerciciosCompletados.containsKey(diaKey) && 
              _ejerciciosCompletados[diaKey]!.containsKey(nombreEj)) {
            _ejerciciosCompletados[diaKey]![nombreEj] = true;
          }
        }
      });
    } catch (e) {
      print("Error al sincronizar historial: $e");
    }
  }

  Future<void> _obtenerRutinaIA() async {
    setState(() => _cargando = true);

    final nombre = widget.datosUsuario?['nombre'] ?? 'Usuario';
    final peso = double.tryParse(widget.datosUsuario?['peso']?.toString() ?? '') ?? 70.0;
    final altura = double.tryParse(widget.datosUsuario?['altura']?.toString() ?? '') ?? 1.70;
    final objetivo = widget.datosUsuario?['meta'] ?? 'Ponerse en forma';
    final nivel = widget.datosUsuario?['nivel'] ?? 'Principiante';
    final dias = int.tryParse(widget.datosUsuario?['dias_disponibles']?.toString() ?? '') ?? 3;
    final limitaciones = widget.datosUsuario?['limitaciones'] ?? 'Ninguna';

    List<Map<String, String>> maquinasEstructuradas = widget.maquinas.map((m) {
      return {
        'nombre': m['nombre']?.toString() ?? 'Máquina genérica',
        'grupo_muscular': m['grupo_muscular']?.toString() ?? 'General',
        'descripcion': m['descripcion']?.toString() ?? 'Sin descripción',
      };
    }).toList();

    // Llamada al servicio de Gemini corregido con el parámetro correcto
    final resultadoJsonString = await _geminiService.generarRutinaIA(
      nombre: nombre,
      peso: peso,
      altura: altura,
      objetivo: objetivo,
      nivel: nivel,
      diasDisponibles: dias,
      limitaciones: limitaciones,
      maquinasDisponibles: maquinasEstructuradas,
    );

    print("====== [GEMINI] Respuesta cruda recibida de la IA ======");
    print(resultadoJsonString);

    try {
      final decoded = jsonDecode(resultadoJsonString);
      setState(() {
        _rutinaJson = decoded;
        _inicializarChecklist(decoded);
      });

      if (_idUsuario != null) {
        // 1. Guardar el JSON completo (Tu lógica actual)
        await _supabase.from('rutinas').upsert({
          'usuario_id': _idUsuario,
          'contenido_rutina': resultadoJsonString,
        }, onConflict: 'usuario_id');
        
        // 2. AHORA: Guardar los ejercicios desglosados en la tabla 'ejercicios'
        // Esto es lo que permite que los checkboxes tengan un lugar donde consultar
        await DataService.procesarYGuardarRutinaIA(decoded, _idUsuario!);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('¡Rutina inteligente sincronizada! 💪'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      print("❌ Error crítico: $e");
      // ... (manejo de error igual)
    } finally {
      setState(() => _cargando = false);
    }
  }

  Future<void> _toggleMision(String nombreDia, String nombreEjercicio, bool completado) async {
    int diaNumero = int.tryParse(nombreDia.replaceAll('Día ', '')) ?? 0;
    
    setState(() {
      _ejerciciosCompletados[nombreDia]?[nombreEjercicio] = completado;
    });

    try {
      if (completado) {
        // AQUÍ ESTÁ EL TRUCO: 
        // Enviamos un mapa que SOLO tiene las columnas de datos.
        // NUNCA incluyas la clave 'id' en este mapa.
        final datosMision = {
          'usuario_id': _idUsuario,
          'dia_numero': diaNumero,
          'nombre_ejercicio': nombreEjercicio,
          'completado': true,
          'fecha_completada': DateTime.now().toIso8601String(),
        };

        await _supabase.from('historial_misiones').upsert(
          datosMision, 
          onConflict: 'usuario_id, dia_numero, nombre_ejercicio'
        );
      } else {
        await _supabase.from('historial_misiones')
            .delete()
            .eq('usuario_id', _idUsuario!)
            .eq('dia_numero', diaNumero)
            .eq('nombre_ejercicio', nombreEjercicio);
      }
    } catch (e) {
      print("Error crítico en base de datos: $e");
      setState(() {
        _ejerciciosCompletados[nombreDia]?[nombreEjercicio] = !completado;
      });
    }
  }

  Future<void> _cargarEstadoCheckboxes() async {
    if (_idUsuario == null) return;
    
    // Traemos solo los completados del usuario actual
    final res = await _supabase
        .from('historial_misiones')
        .select('dia_numero, nombre_ejercicio')
        .eq('usuario_id', _idUsuario!);

    if (res != null) {
      setState(() {
        // Limpiamos el mapa antes de cargar para evitar inconsistencias
        _ejerciciosCompletados.clear();
        
        for (var item in res as List) {
          String diaKey = "Día ${item['dia_numero']}";
          String nombreEj = item['nombre_ejercicio'];
          
          // Inicializamos si no existe el día
          if (!_ejerciciosCompletados.containsKey(diaKey)) {
            _ejerciciosCompletados[diaKey] = {};
          }
          
          // Marcamos como TRUE (si está en la tabla, está completado)
          // Nota: Si tu lógica de índices (ejIndex) es compleja, 
          // considera usar el nombre del ejercicio como key en lugar del index.
          _ejerciciosCompletados[diaKey]![nombreEj] = true; 
        }
      });
    }
  }



  @override
  Widget build(BuildContext context) {
    final bool yaTieneRutinaGuardada = _rutinaJson != null;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Mi Rutina Inteligente', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
      ),
      body: _cargando
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.amber),
                  SizedBox(height: 16),
                  Text('Estructurando tu entrenamiento...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : yaTieneRutinaGuardada
              ? _buildRutinaList()
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.smart_toy_outlined, size: 80, color: Colors.amber),
                        const SizedBox(height: 24),
                        const Text(
                          '¿Listo para entrenar?',
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Crearemos un plan adaptado 100% a tus características.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: const Color(0xFF121212),
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _obtenerRutinaIA,
                          child: const Text(
                            'GENERAR RUTINA AHORA',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildRutinaList() {
    final dias = _rutinaJson!['dias'] as List? ?? [];
    final resumen = _rutinaJson!['resumen_general'] ?? 'Sin resumen disponible.';

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: dias.length + 2, 
      itemBuilder: (context, index) {
        // 1. Tarjeta de Resumen General arriba
        if (index == 0) {
          return Card(
            color: const Color(0xFF1E1E1E),
            margin: const EdgeInsets.only(bottom: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Colors.amber, width: 0.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.analytics_outlined, color: Colors.amber, size: 20),
                      SizedBox(width: 8),
                      Text('Estrategia del Entrenador', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(resumen, style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.4)),
                ],
              ),
            ),
          );
        }

        // 2. Botón de recrear rutina abajo del todo
        if (index == dias.length + 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2A2A2A),
                foregroundColor: Colors.amber,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Colors.amber, width: 0.5)
                ),
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('RECREAR / REGENERAR RUTINA', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _obtenerRutinaIA, 
            ),
          );
        }

        // 3. Renderizado de los bloques de días
        final diaData = dias[index - 1] as Map<String, dynamic>;
        String nombreDia = "Día ${diaData['dia_numero'] ?? ''}";
        String enfoqueDia = diaData['enfoque_dia'] ?? 'General';
        List ejercicios = diaData['ejercicios'] ?? [];

        return Card(
          color: const Color(0xFF1E1E1E),
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ExpansionTile(
            initiallyExpanded: index == 1,
            iconColor: Colors.amber,
            collapsedIconColor: Colors.grey,
            title: Text(nombreDia, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: Text('Enfoque: $enfoqueDia', style: const TextStyle(color: Colors.amber, fontSize: 13)),
            children: [
              const Divider(color: Colors.grey, height: 1),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: ejercicios.length,
                itemBuilder: (ctx, ejIndex) {
                  // 1. Convertimos todo a un mapa de forma segura
                  final ej = ejercicios[ejIndex] as Map<String, dynamic>;

                  // PROTECCIÓN DE DATOS (Adiós pantalla roja)
                  String nombreEj = (ej['nombre_ejercicio'] ?? 'Ejercicio').toString();
                  String series = (ej['series'] ?? '0').toString();
                  String repcell = (ej['repeticiones'] ?? '0').toString();
                  String ejecucion = (ej['ejecucion_tecnica'] ?? 'Sin descripción').toString();
                  String tipKinesico = (ej['tip_kinesico'] ?? 'Sin consejos').toString();

                  return CheckboxListTile(
                    activeColor: Colors.amber,
                    title: Text(nombreEj, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      'Sets: $series | Reps: $repcell\nEjecución: $ejecucion\nTip: $tipKinesico',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    value: _ejerciciosCompletados[nombreDia]?[nombreEj] ?? false, 
  
                    onChanged: (int.tryParse(nombreDia.replaceAll('Día ', '')) ?? 0) == _diaActualUsuario
                    ? (bool? valor) => _toggleMision(nombreDia, nombreEj, valor ?? false) // Pasamos nombreEj
                    : null,
                  );
                },
              )
            ],
          ),
        );
      },
    );
  }
}