import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'gemini_service.dart';

class RutinaView extends StatefulWidget {
  final Map<String, dynamic>? datosUsuario;
  final List<Map<String, dynamic>> maquinas;

  const RutinaView({super.key, required this.datosUsuario, required this.maquinas});

  @override
  State<RutinaView> createState() => _RutinaViewState();
}

class _RutinaViewState extends State<RutinaView> {
  final GeminiService _geminiService = GeminiService();
  final SupabaseClient _supabase = Supabase.instance.client;

  Map<String, dynamic>? _rutinaJson; 
  bool _isLoading = false;
  int? _idUsuario;

  // Mapa para controlar los checkboxes. Estructura: {"Dia_Numero-NombreEjercicio": true/false}
  final Map<String, bool> _misionesCompletadas = {};

  @override
  void initState() {
    super.initState();
    _idUsuario = int.tryParse(widget.datosUsuario?['id']?.toString() ?? '');
    _inicializarDatos();
  }

  Future<void> _inicializarDatos() async {
    setState(() => _isLoading = true);
    await _cargarOSugiereRutina();
    await _cargarChecksDelDia(); 
    setState(() => _isLoading = false);
  }

  // --- RECUPERAR LOS CHECKS YA GUARDADOS HOY ---
  Future<void> _cargarChecksDelDia() async {
    if (_idUsuario == null) return;

    try {
      final String inicioHoy = DateTime.now().toIso8601String().substring(0, 10); 

      final List<dynamic> registrosHoy = await _supabase
          .from('historial_misiones')
          .select('dia_numero, nombre_ejercicio')
          .eq('usuario_id', _idUsuario!)
          .gte('fecha_completada', '${inicioHoy}T00:00:00Z');

      setState(() {
        _misionesCompletadas.clear();
        for (var reg in registrosHoy) {
          final String llave = "${reg['dia_numero']}-${reg['nombre_ejercicio']}";
          _misionesCompletadas[llave] = true;
        }
      });
    } catch (e) {
      print("Error al recuperar los checks de hoy: $e");
    }
  }

  // --- GUARDAR O ELIMINAR EL CHECK EN LA TABLA HISTORIAL ---
  Future<void> _marcarMisionEnBaseDatos(int diaNumero, String nombreEjercicio, bool completado) async {
    if (_idUsuario == null) return;

    final String llaveUnica = "$diaNumero-$nombreEjercicio";

    setState(() {
      _misionesCompletadas[llaveUnica] = completado;
    });

    try {
      if (completado) {
        await _supabase.from('historial_misiones').insert({
          'usuario_id': _idUsuario,
          'dia_numero': diaNumero,
          'nombre_ejercicio': nombreEjercicio,
          'completado': true,
        });
        print("¡Misión guardada en Supabase!");
      } else {
        final String inicioHoy = DateTime.now().toIso8601String().substring(0, 10);
        
        await _supabase
            .from('historial_misiones')
            .delete()
            .eq('usuario_id', _idUsuario!)
            .eq('dia_numero', diaNumero)
            .eq('nombre_ejercicio', nombreEjercicio)
            .gte('fecha_completada', '${inicioHoy}T00:00:00Z');
            
        print("Misión eliminada del historial de hoy.");
      }
    } catch (e) {
      print("Error al actualizar el check en Supabase: $e");
      setState(() {
        _misionesCompletadas[llaveUnica] = !completado;
      });
    }
  }

  // --- CARGA DE RUTINA DESDE BASE DE DATOS ---
  Future<void> _cargarOSugiereRutina() async {
    if (_idUsuario == null) {
      _obtenerRutinaIA();
      return;
    }

    try {
      final response = await _supabase
          .from('rutinas')
          .select('contenido_rutina')
          .eq('usuario_id', _idUsuario!)
          .maybeSingle();

      if (response != null && response['contenido_rutina'] != null) {
        setState(() {
          _rutinaJson = jsonDecode(response['contenido_rutina'].toString());
        });
      } else {
        await _obtenerRutinaIA();
      }
    } catch (e) {
      print("Error al leer de Supabase: $e");
      await _obtenerRutinaIA();
    }
  }

  // --- GENERACIÓN DE RUTINA KINESIOLÓGICA CON IA ---
  Future<void> _obtenerRutinaIA() async {
    final nombre = widget.datosUsuario?['nombre'] ?? 'Usuario';
    final peso = double.tryParse(widget.datosUsuario?['peso']?.toString() ?? '') ?? 70.0;
    final altura = double.tryParse(widget.datosUsuario?['altura']?.toString() ?? '') ?? 1.70;
    final objetivo = widget.datosUsuario?['meta'] ?? 'Ponerse en forma';
    final nivel = widget.datosUsuario?['nivel'] ?? 'Principiante';
    final dias = widget.datosUsuario?['dias_disponibles'] ?? 3;
    final limitaciones = widget.datosUsuario?['limitaciones'] ?? 'Ninguna';

    List<Map<String, String>> maquinasEstructuradas = widget.maquinas.map((m) {
      return {
        'nombre': m['nombre']?.toString() ?? 'Máquina genérica',
        'grupo_muscular': m['grupo_muscular']?.toString() ?? 'General',
        'descripcion': m['descripcion']?.toString() ?? 'Uso estándar en el gimnasio.',
      };
    }).toList();

    if (maquinasEstructuradas.isEmpty) {
      maquinasEstructuradas = [
        {
          'nombre': 'Mancuernas',
          'grupo_muscular': 'Cuerpo completo',
          'descripcion': 'Pesos libres para realizar ejercicios multiarticulares.'
        }
      ];
    }

    final resultadoJsonString = await _geminiService.generarRutinaIA(
      nombre: nombre,
      peso: peso,
      altura: altura,
      objetivo: objetivo,
      nivel: nivel,
      diasDisponibles: dias,
      limitaciones: limitaciones, // Corregido el typo aquí
      maquinasDisponibles: maquinasEstructuradas,
    );

    try {
      final decoded = jsonDecode(resultadoJsonString);
      setState(() {
        _rutinaJson = decoded;
      });

      if (_idUsuario != null) {
        await _supabase.from('rutinas').upsert({
          'usuario_id': _idUsuario,
          'contenido_rutina': resultadoJsonString,
        }, onConflict: 'usuario_id');
        print("¡Rutina JSON guardada con éxito en Supabase!");
      }
    } catch (e) {
      print("Error al procesar o guardar el JSON de la IA: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> listaDias = _rutinaJson?['dias'] ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Misiones de Entrenamiento"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
          : listaDias.isEmpty
              ? const Center(child: Text("No hay rutinas disponibles.", style: TextStyle(color: Colors.white)))
              : Column(
                  children: [
                    // --- SECCIÓN 1: CUADRO DE ESTRATEGIA + RESUMEN RÁPIDO ---
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.withOpacity(0.3), width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.fitness_center, color: Colors.blue[400], size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  "RESUMEN GENERAL DEL PLAN",
                                  style: TextStyle(color: Colors.blue[400], fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1),
                                ),
                              ],
                            ),
                            if (_rutinaJson?['resumen_general'] != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _rutinaJson!['resumen_general'].toString(),
                                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4, fontStyle: FontStyle.italic),
                              ),
                            ],
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: Divider(color: Colors.white12, thickness: 1),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: listaDias.map<Widget>((dia) {
                                final int numDia = dia['dia_numero'] ?? 1;
                                final String enfoque = dia['enfoque_dia'] ?? 'General';
                                final List<dynamic> ejercicios = dia['ejercicios'] ?? [];

                                String nombresEjercicios = ejercicios.map((e) => e['nombre_ejercicio'] ?? 'Ejercicio').join('  •  ');

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                                  child: RichText(
                                    text: TextSpan(
                                      style: const TextStyle(fontSize: 13, height: 1.4),
                                      children: [
                                        TextSpan(
                                          text: "Día $numDia ($enfoque): ",
                                          style: TextStyle(color: Colors.blue[300], fontWeight: FontWeight.bold),
                                        ),
                                        TextSpan(
                                          text: nombresEjercicios,
                                          style: const TextStyle(color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "CHECKLIST DE MISIONES",
                          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5),
                        ),
                      ),
                    ),

                    // --- SECCIÓN 2: PANEL DE MISIONES ---
                    Expanded(
                      child: ListView.builder(
                        itemCount: listaDias.length,
                        itemBuilder: (context, index) {
                          final dia = listaDias[index];
                          final int numDia = dia['dia_numero'] ?? (index + 1);
                          final String enfoque = dia['enfoque_dia'] ?? 'General';
                          final List<dynamic> ejercicios = dia['ejercicios'] ?? [];

                          return Card(
                            color: const Color(0xFF1E1E1E),
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ExpansionTile(
                              collapsedIconColor: Colors.white,
                              iconColor: Colors.blue,
                              title: Text(
                                "DÍA $numDia - $enfoque",
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              children: ejercicios.map<Widget>((ejercicio) {
                                final String nombreEj = ejercicio['nombre_ejercicio'] ?? 'Ejercicio';
                                final String series = ejercicio['series'] ?? '3';
                                final String reps = ejercicio['repeticiones'] ?? '12';
                                final String carga = ejercicio['enfoque_carga'] ?? 'Moderada';
                                final String tip = ejercicio['tip_kinesico'] ?? '';

                                final String llaveUnica = "$numDia-$nombreEj";
                                final bool estaCompletado = _misionesCompletadas[llaveUnica] ?? false;

                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2A2A2A),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: CheckboxListTile(
                                      activeColor: Colors.green,
                                      checkColor: Colors.white,
                                      title: Text(
                                        nombreEj,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          decoration: estaCompletado ? TextDecoration.lineThrough : null,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 4),
                                          Text("Sets: $series | Reps: $reps", style: const TextStyle(color: Colors.blueGrey)),
                                          Text("Carga: $carga", style: const TextStyle(color: Colors.orangeAccent, fontSize: 13)),
                                          if (tip.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text("💡 Tip: $tip", style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                                          ]
                                        ],
                                      ),
                                      value: estaCompletado,
                                      onChanged: (bool? valor) {
                                        _marcarMisionEnBaseDatos(numDia, nombreEj, valor ?? false);
                                      },
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        },
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _obtenerRutinaIA,
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        label: const Text("Actualizar Plan Completo"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey[800],
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    )
                  ],
                ),
    );
  }
}