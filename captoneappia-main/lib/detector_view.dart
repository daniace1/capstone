import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart'; 
import 'package:image/image.dart' as img; // ¡Este es el que te falta para img.decodeImage!
import 'rutina_view.dart';
import 'perfil_view.dart';
import 'dart:typed_data'; // NECESARIO para Float32List

class GymTestView extends StatefulWidget {
  const GymTestView({super.key});

  @override
  State<GymTestView> createState() => _GymTestViewState();
}

class _GymTestViewState extends State<GymTestView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  Map<String, dynamic>? _datosUsuario;
  List<dynamic> _ejerciciosHoy = [];
  Map<String, bool> _misionesCompletadasHoy = {};
  bool _isLoading = true;
  String _enfoqueDia = "Cargando...";
  int _diaNumeroCalculado = 1;
  File? _image;
  bool _tieneRutinaGuardada = false;


  @override
  void initState() {
    super.initState();  
    _verificarRutinaEnHome();
    _cargarHomeData();
  }

  Future<void> _verificarRutinaEnHome() async {
    try {
      final response = await Supabase.instance.client
          .from('rutinas')
          .select('id')
          .eq('usuario_id', 1) // El ID fijo que usas
          .maybeSingle();
          
      setState(() => _tieneRutinaGuardada = response != null);
    } catch (e) {
      print("Error verificando rutina: $e");
    }
  }

  Future<void> _cargarHomeData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      // 1. Obtener perfil
      final perfilRes = await _supabase.from('perfiles').select().eq('id', 1).maybeSingle();
      if (perfilRes != null) _datosUsuario = perfilRes;

      // 2. Obtener rutina
      final rutinaRes = await _supabase.from('rutinas').select('contenido_rutina').eq('usuario_id', 1).maybeSingle();
      
      if (rutinaRes != null && rutinaRes['contenido_rutina'] != null) {
        final Map<String, dynamic> rutinaJson = jsonDecode(rutinaRes['contenido_rutina'].toString());
        final List<dynamic> listaDias = rutinaJson['dias'] ?? [];
        
        int diaActual = 1;
        final int weekday = DateTime.now().weekday; 
        if (weekday == 3 || weekday == 4) diaActual = 2;
        if (weekday >= 5) diaActual = 3;

        final diaData = listaDias.firstWhere(
          (d) => (d['dia_numero'] as int) == diaActual, 
          orElse: () => null
        );

        if (diaData != null) {
          setState(() {
            _ejerciciosHoy = diaData['ejercicios'] ?? [];
            _enfoqueDia = diaData['enfoque_dia'] ?? 'Entrenamiento';
            _diaNumeroCalculado = diaActual;
          });
        }
      }

      // 3. Carga de estados (AQUÍ ESTÁ LA CORRECCIÓN: Todo dentro del try)
      final estadosRes = await Supabase.instance.client 
          .from('historial_misiones')
          .select('nombre_ejercicio')
          .eq('usuario_id', 1)
          .eq('dia_numero', _diaNumeroCalculado);

      Map<String, bool> nuevosEstados = {};
      for (var item in estadosRes) {
        nuevosEstados[item['nombre_ejercicio']] = true;
      }

      setState(() {
        _misionesCompletadasHoy = nuevosEstados;
      });

    } catch (e) {
      print("Error crítico cargando home: $e");
    } finally {
      // El finally siempre va al final de todo
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // MEJORA: Permite elegir entre cámara o galería
  Future<void> _pickImage(ImageSource source) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source);
    
    if (image != null) {
      final file = File(image.path);
      setState(() => _image = file);
      await _runInference(file); // IMPORTANTE: el 'await' asegura que espere a la IA
    }
  }

  


  Future<void> _runInference(File imageFile) async {
    try {
      // 1. Cargar modelo y etiquetas
      final interpreter = await Interpreter.fromAsset('assets/models/model_unquant.tflite');
      final labels = await rootBundle.loadString('assets/models/labels.txt');
      final List<String> labelsList = labels.split('\n').where((s) => s.trim().isNotEmpty).toList();

      // 2. Procesar imagen
      final bytes = await imageFile.readAsBytes();
      final img.Image? originalImage = img.decodeImage(bytes);
      final img.Image resizedImage = img.copyResize(originalImage!, width: 224, height: 224);

      // 3. Preparar buffer (Input normalizado [-1 a 1])
      var input = Float32List(1 * 224 * 224 * 3);
      var buffer = Float32List.view(input.buffer);
      int pixelIndex = 0;
      for (int y = 0; y < 224; y++) {
        for (int x = 0; x < 224; x++) {
          var pixel = resizedImage.getPixel(x, y);
          buffer[pixelIndex++] = (pixel.r - 127.5) / 127.5;
          buffer[pixelIndex++] = (pixel.g - 127.5) / 127.5;
          buffer[pixelIndex++] = (pixel.b - 127.5) / 127.5;
        }
      }

      // 4. Inferencia
      var output = List.filled(labelsList.length, 0.0).reshape([1, labelsList.length]);
      interpreter.run(input.reshape([1, 224, 224, 3]), output);

      // 5. Analizar
      var prediction = output[0] as List<double>;
      int maxIndex = prediction.indexOf(prediction.reduce((a, b) => a > b ? a : b));
      String ejercicioDetectado = labelsList[maxIndex].replaceAll(RegExp(r'^\d+\s+'), '').trim().toLowerCase();

      print("IA Detectó: $ejercicioDetectado");

      // 6. Validar y actualizar UI
      if (mounted) {
        print("IA Detectó: $ejercicioDetectado, iniciando búsqueda en BD...");
        
        // Llamamos directamente a _procesarDeteccion para que busque en 'maquinas'
        // y abra el diálogo de guardar si existe.
        await _procesarDeteccion(ejercicioDetectado);
        
        // También mantenemos la lógica de la rutina diaria
        bool existe = _ejerciciosHoy.any((e) => 
            e['nombre_ejercicio'].toString().trim().toLowerCase() == ejercicioDetectado);
        
        if (existe) {
          setState(() => _misionesCompletadasHoy[ejercicioDetectado] = true);
          await _actualizarEstadoEjercicio(ejercicioDetectado, true);
        }
      }
      interpreter.close();
    } catch (e) {
      print("Error en inferencia: $e");
    }
  }


  // Dialogo para elegir origen de imagen
  void _mostrarOpcionesImagen() {
    showModalBottomSheet(context: context, builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(leading: Icon(Icons.camera_alt), title: Text("Cámara"), onTap: () { _pickImage(ImageSource.camera); Navigator.pop(context); }),
        ListTile(leading: Icon(Icons.photo_library), title: Text("Galería"), onTap: () { _pickImage(ImageSource.gallery); Navigator.pop(context); }),
      ],
    ));
  }


  Future<void> _actualizarEstadoEjercicio(String nombreEjercicio, bool completado) async {
    try {
      if (completado) {
        await Supabase.instance.client.from('historial_misiones').upsert({
          'usuario_id': 1,
          'dia_numero': _diaNumeroCalculado, // <--- ESTO ES LO QUE FALTA
          'nombre_ejercicio': nombreEjercicio,
          'completado': true,
          'fecha_completada': DateTime.now().toIso8601String(),
        });
      } else {
        // Si desmarcas, borras el registro donde coincida el día y el ejercicio
        await Supabase.instance.client.from('historial_misiones')
            .delete()
            .eq('usuario_id', 1)
            .eq('dia_numero', _diaNumeroCalculado)
            .eq('nombre_ejercicio', nombreEjercicio);
      }
    } catch (e) {
      print("❌ Error al actualizar: $e");
    }
  }


  Future<void> _procesarDeteccion(String nombreDetectado) async {
    // Limpiamos el nombre: quitamos espacios y pasamos a minúsculas
    String nombreLimpio = nombreDetectado.trim().toLowerCase();
    
    print("🔍 Buscando en BD: $nombreLimpio");

    try {
      final response = await Supabase.instance.client
          .from('maquinas')
          .select('id, nombre, descripcion')
          .ilike('nombre', '%$nombreLimpio%') // Usamos ilike para buscar coincidencias parciales
          .maybeSingle();

      if (response != null) {
        print("✅ Máquina encontrada: ${response['nombre']}");
        _mostrarDialogoConfirmacion(response); 
      } else {
        print("❌ No se encontró coincidencia para: $nombreLimpio");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("La máquina '$nombreDetectado' no está en la base de datos.")),
        );
      }
    } catch (e) {
      print("❌ Error en la consulta: $e");
    }
  }



  void _mostrarDialogoConfirmacion(Map<String, dynamic> maquinaData) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(maquinaData['nombre']),
        content: Text(maquinaData['descripcion']), // La descripción que pides
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancelar")),
          ElevatedButton(
          onPressed: () async {
            await _registrarMaquinaDetectada(maquinaData['id']); // Llama a la función de registro
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("${maquinaData['nombre']} guardada con éxito.")),
            );
          },
          child: const Text("Guardar Máquina"),
        ),
        ],
      ),
    );
  }


  Future<void> _registrarMaquinaDetectada(int maquinaId) async {
    try {
      await Supabase.instance.client.from('historial_detecciones').insert({
        'usuario_id': 1, // Tu ID de prueba
        'maquina_id': maquinaId,
        'creado_el': DateTime.now().toIso8601String(),
      });
      print("✅ Máquina registrada en el historial.");
    } catch (e) {
      print("❌ Error al registrar máquina: $e");
    }
  }

  




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("IronLens AI"),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle, size: 30),
            onPressed: () => // En cualquier parte donde hagas el Navigator.push
              Navigator.push(
                context, 
                MaterialPageRoute(builder: (context) => const PerfilView()),
              ).then((value) {
                _cargarHomeData(); // <--- Esto obliga a la pantalla a volver a leer Supabase
              }),
          ),
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(child: ListTile(title: Text("HOLA, ${_datosUsuario?['nombre'] ?? 'Usuario'}"), subtitle: Text("Meta: ${_datosUsuario?['meta'] ?? 'Entrenar'}"))),
          const SizedBox(height: 20),
          Card(color: const Color(0xFF1E1E1E), child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
            Text("MISIONES DÍA $_diaNumeroCalculado: $_enfoqueDia", style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
            ..._ejerciciosHoy.map((e) => CheckboxListTile(
            title: Text(e['nombre_ejercicio']),
            subtitle: Text("Series: ${e['series']} | Reps: ${e['repeticiones']}"),
            value: _misionesCompletadasHoy[e['nombre_ejercicio']] ?? false,
            onChanged: (val) async {
              // 1. Actualizamos UI inmediatamente
              setState(() => _misionesCompletadasHoy[e['nombre_ejercicio']] = val!);
              
              // 2. Aquí llamas a la función que guarda en Supabase (tienes que crearla)
              await _actualizarEstadoEjercicio(e['nombre_ejercicio'], val!);
            },
          )),
          ]))),
          const SizedBox(height: 20),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.orangeAccent,
        onPressed: _mostrarOpcionesImagen, // Ya llama a las opciones
        child: const Icon(Icons.camera_alt),
      ),
    );
  }
}