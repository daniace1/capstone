import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ironlens/Detalle_Rutina_View.dart';
import 'package:ironlens/detalle_maquina_view.dart';
import 'package:ironlens/perfil_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tflite_flutter/tflite_flutter.dart'; // LA NUEVA LIBRERÍA
import 'package:image/image.dart' as img; // Para procesar la imagen
import 'data_service.dart';


class GymTestView extends StatefulWidget {
  @override
  _GymTestViewState createState() => _GymTestViewState();
}

class _GymTestViewState extends State<GymTestView> {
  final _supabase = Supabase.instance.client;
  File? _image;
  Map<String, dynamic>? _perfil;
  List<dynamic> _maquinasDisponibles = [];
  bool _loading = true;
  final ImagePicker _picker = ImagePicker(); 
  final Map<String, DateTime> _tiemposBloqueo = {};
  Map<String, bool> _ejerciciosCompletados = {}; 
  String? _idUsuario;

  @override
  void initState() {
    super.initState();
    _cargarDatosIniciales();
    _iniciarApp();
  }
  Future<void> _iniciarApp() async {
    await DataService.verificarCambioDeDia(); // <-- Esto corre antes de cargar nada
    _cargarDatosIniciales(); // Tu función normal de carga
  }
  
  // Carga el perfil y las máquinas para que no den error de "null"
  Future<void> _cargarDatosIniciales() async {
    try {
      final perfilData = await _supabase.from('perfiles').select().eq('id', 1).single();
      final maquinasData = await _supabase.from('maquinas').select();
      setState(() {
        _perfil = perfilData;
        _maquinasDisponibles = maquinasData;
        _loading = false;
      });
    } catch (e) {
      print("Error inicial: $e");
      setState(() => _loading = false);
    }
  }

  // Función para abrir la cámara/galería
  // Función para abrir la cámara/galería  
  Future<void> _pickImage() async {
      final ImagePicker picker = ImagePicker(); // Usamos esta misma variable abajo
      
      final ImageSource? source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Seleccionar imagen"),
          content: const Text("¿De dónde quieres sacar la foto de la máquina?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, ImageSource.gallery),
              child: const Text("GALERÍA"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ImageSource.camera),
              child: const Text("CÁMARA"),
            ),
          ],
        ),
      );

      if (source != null) {
        // Si es cámara, NO le metemos maxWidth ni maxHeight para que Samsung no rote la foto de lado
        final XFile? image = await picker.pickImage(
          source: source,
          imageQuality: 90, // Mantenemos buena calidad para que la IA distinga bien
        );
        
        if (image != null) {
          setState(() {
            _image = File(image.path);
          });
          
          // Ejecutamos la inferencia con el archivo limpio y con la orientación correcta
          _runInference(File(image.path));
        }
      }
  }

  Future<void> _runInference(File image) async {
    try {
      setState(() => _loading = true);

      // 1. Cargar el archivo de etiquetas (labels.txt)
      final String labelsRaw = await DefaultAssetBundle.of(context).loadString('assets/models/labels.txt');
      List<String> labels = labelsRaw
          .split('\n')
          .map((s) => s.trim()) 
          .where((s) => s.isNotEmpty)
          .toList();
      
      // 2. Cargamos el intérprete
      final interpreter = await Interpreter.fromAsset('assets/models/model_unquant.tflite');
      
      // 3. Procesamos la imagen (Resize a 224x224)
      var input = await _imageToByteList(image);
      
      // 4. Preparar el 'output'
      var output = List.filled(1 * labels.length, 0.0).reshape([1, labels.length]);

      // 5. Ejecutar IA
      interpreter.run(input, output);

      // 6. Encontrar el índice ganador y su probabilidad
      List<double> probabilidades = List<double>.from(output[0]);
      int indexMax = 0;
      double maxProb = -1.0;
      for (int i = 0; i < probabilidades.length; i++) {
        if (probabilidades[i] > maxProb) {
          maxProb = probabilidades[i];
          indexMax = i;
        }
      }

      // --- FILTRO DE CONFIANZA (UMBRAL DEL 65%) ---
      if (maxProb < 0.65) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("🤔 No estoy muy seguro (Certeza: ${(maxProb * 100).toStringAsFixed(1)}%). Acércate más a la máquina."),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
        return; 
      }
      // --------------------------------------------

      // 7. El nombre sale directo del archivo labels limpiando el número
      String resultadoIA = labels[indexMax].replaceFirst(RegExp(r'\d+\s+'), '').trim();
      print("IA detectó con éxito (${(maxProb * 100).toStringAsFixed(1)}%): $resultadoIA");

      // 8. Buscar en la lista local de Supabase
      final Map<String, dynamic>? maquinaEncontrada = _maquinasDisponibles
        .cast<Map<String, dynamic>>()
        .firstWhere(
          (m) => m['nombre']?.toString().toLowerCase() == resultadoIA.toLowerCase(),
          orElse: () => {}, 
        );

      if (maquinaEncontrada != null && maquinaEncontrada.isNotEmpty) {
        if (!mounted) return;

        // 1. Navegamos y esperamos a que el usuario vuelva
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DetalleMaquinaView(
              maquina: maquinaEncontrada,
              confianza: maxProb, 
            ),
          ),
        ).then((_) {
          // 2. CUANDO VUELVES, LIMPIAMOS LA IMAGEN
          setState(() {
            _image = null; 
          });
        });
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("La máquina '$resultadoIA' no está en la base de datos.")),
        );
      }

    } catch (e) {
      print("Error general en _runInference: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<Uint8List> _imageToByteList(File imageFile) async {
    final Uint8List imageBytes = await imageFile.readAsBytes();
    
    // 1. Decodificar la imagen
    img.Image? originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) throw Exception("No se pudo decodificar la imagen");

    // 2. CORRECCIÓN DE ORIENTACIÓN (Crucial para la cámara)
    // La librería 'image' tiene una función para aplicar la rotación según el EXIF
    originalImage = img.bakeOrientation(originalImage);

    // 3. RECORTAR EN LUGAR DE ESTIRAR (Mejor para la IA)
    // En lugar de forzar 224x224 (deformación), centramos y recortamos el cuadrado
    final int size = originalImage.width < originalImage.height 
        ? originalImage.width 
        : originalImage.height;
    
    final img.Image cropped = img.copyResizeCropSquare(originalImage, size: size);
    final img.Image resized = img.copyResize(cropped, width: 224, height: 224);
    
    // 4. Convertir a Float32
    final Float32List buffer = Float32List(1 * 224 * 224 * 3);
    int pixelIndex = 0;
    
    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final img.Pixel pixel = resized.getPixel(x, y);
        // Ajustar según si tu modelo usa RGB o BGR (Teachable Machine suele ser RGB)
        buffer[pixelIndex++] = pixel.r.toDouble() / 255.0;
        buffer[pixelIndex++] = pixel.g.toDouble() / 255.0;
        buffer[pixelIndex++] = pixel.b.toDouble() / 255.0;
      }
    }
    return buffer.buffer.asUint8List();
  }


  // ESTO ES LO QUE PEDISTE: El listado que se desliza hacia arriba
  void _mostrarListadoMaquinas() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      isScrollControlled: true, // Para que pueda ser más alto
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25))
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7, // 70% de la pantalla
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              Container(
                width: 50, height: 5, 
                decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(10))
              ),
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text("MÁQUINAS DISPONIBLES", 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.orangeAccent)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _maquinasDisponibles.length,
                  itemBuilder: (context, i) {
                    final item = _maquinasDisponibles[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: ListTile(
                        leading: const Icon(Icons.fitness_center, color: Colors.orangeAccent),
                        title: Text(item['nombre'] ?? "Máquina"),
                        subtitle: Text(item['grupo_muscular'] ?? "General"),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                        onTap: () {
                        // 1. Primero cerramos el modal deslizante
                          Navigator.pop(context); 

                          // 2. Luego navegamos a la pantalla de detalle
                          // Usamos Navigator.push para que Flutter ponga la flecha de "atrás" automática
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DetalleMaquinaView(
                                maquina: item, // Pasamos la información de la máquina seleccionada
                              ),
                            ),
                          );
                        },
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
  }

  Future<int> _contarMisionesCompletadasHoy() async {
    try {
      final hoy = DateTime.now();
      // Formato ISO para el inicio del día (YYYY-MM-DDT00:00:00)
      final fechaInicio = DateTime(hoy.year, hoy.month, hoy.day).toIso8601String();
      
      final response = await _supabase
          .from('historial_misiones')
          .count(CountOption.exact)
          .eq('usuario_id', 1) 
          .eq('completado', true)
          .gte('fecha_completada', fechaInicio);

      // En las versiones recientes de supabase_flutter, .count() devuelve un int
      // Si usas una versión antigua, esto podría ser un objeto CountResponse
      return response; 
    } catch (e) {
      print("Error al contar misiones: $e");
      return 0;
    }
  }


  Future<void> _actualizarEstadoMision(String nombreEjercicio, int diaNumero, bool completado) async {
    // 1. Actualización visual inmediata
    setState(() {
      _ejerciciosCompletados[nombreEjercicio] = completado;
    });
    if (_idUsuario == null) return;

    try {
      if (completado) {
        // 2. Usamos upsert. Importante: NO incluyas el 'id' aquí.
        // Al no incluir el 'id', dejas que Supabase lo genere automáticamente.
        await Supabase.instance.client.from('historial_misiones').upsert({
          'usuario_id': _idUsuario,
          'nombre_ejercicio': nombreEjercicio,
          'dia_numero': diaNumero,
          'fecha_completada': DateTime.now().toIso8601String(),
          'completado': true,
        }, onConflict: 'usuario_id, dia_numero, nombre_ejercicio');
      } else {
        // 3. Borrado si se desmarca
        await Supabase.instance.client.from('historial_misiones')
            .delete()
            .eq('usuario_id', _idUsuario!)
            .eq('nombre_ejercicio', nombreEjercicio)
            .eq('dia_numero', diaNumero);
      }
    } catch (e) {
      print("Error al actualizar misión: $e");
      // Revertir cambio si falla la BD
      setState(() {
        _ejerciciosCompletados[nombreEjercicio] = !completado;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text("IronLens AI"),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle, size: 30, color: Colors.orangeAccent),
            onPressed: () async {
              /*print("DEBUG: El valor de mi ID antes de llamar es: $_idUsuario");
              final user = Supabase.instance.client.auth.currentUser;
              final idReal = user?.id ?? "1";
              await DataService.simular20DiasDeDatos(idReal);*/
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PerfilView()),
              ).then((_) {
                // ESTA LÍNEA ES LA CLAVE
                // Cuando vuelves de PerfilView, se dispara la recarga
                _cargarDatosIniciales(); 
                setState(() {}); 
              });
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 1. PERFIL RESUMIDO
            Container(
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.orangeAccent,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  const SizedBox(width: 15),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("HOLA, ${(_perfil?['nombre'] ?? 'FABIÁN').toUpperCase()}", 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      Text("${_perfil?['peso'] ?? '--'} KG | Meta: ${_perfil?['meta'] ?? 'Entrenar'}", 
                        style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),

            // 2. SELECCIÓN DE IMAGEN
            const SizedBox(height: 10),
            _image == null
              ? FutureBuilder<int>(
                  future: _contarMisionesCompletadasHoy(),
                  builder: (context, snapshot) {
                    final completadas = snapshot.data ?? 0;
                    
                    // Envolvemos el Container en InkWell
                    return InkWell(
                      borderRadius: BorderRadius.circular(25),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const DetalleRutinaView()),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.grey[900]!, const Color(0xFF1E1E1E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.insights, color: Colors.orangeAccent, size: 40),
                            const SizedBox(height: 15),
                            Text("MISIÓN DE HOY: $completadas COMPLETADAS",
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              value: completadas / 5,
                              backgroundColor: Colors.grey[800],
                              color: Colors.orangeAccent,
                              borderRadius: BorderRadius.circular(10),
                              minHeight: 8,
                            ),
                            const SizedBox(height: 20),
                            const Text("DETALLE DE HOY", style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),

                            _buildListaEjercicios(),

                            const SizedBox(height: 15),
                            Text(completadas >= 5 ? "¡Meta diaria alcanzada! 🎉" : "¡Sigue así, vamos a por más!",
                                style: const TextStyle(color: Colors.grey, fontSize: 13, fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ),
                    );
                  },
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: Image.file(_image!, height: 220, width: double.infinity, fit: BoxFit.cover),
                ),
            const SizedBox(height: 15),
            ElevatedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.camera_alt),
              label: const Text("ANALIZAR MÁQUINA"),
            ),

            const SizedBox(height: 30),

            // 3. BOTÓN PARA VER LISTADO (Abre el Modal deslizante)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ListTile(
                tileColor: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                leading: const Icon(Icons.list, color: Colors.orangeAccent),
                title: const Text("VER TODAS LAS MÁQUINAS"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _mostrarListadoMaquinas,
              ),
            ),
          ],
        ),
      ),
    );
  }

  
  Widget _buildListaEjercicios() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DataService.obtenerDetalleMisiones(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final lista = snapshot.data!;
        return Column(
          children: lista.map((item) {
            // Extraemos valores de forma segura
            final String nombreEj = item['nombre']?.toString() ?? 'Ejercicio';
            final int diaNum = (item['dia_numero'] is int) ? item['dia_numero'] : 0;
            final bool estaMarcado = item['completado'] ?? false;
            final String idString = item['id']?.toString() ?? '0';
            
            return InkWell(
              onTap: () {
                final ahora = DateTime.now();

                // Lógica de 3 minutos
                if (estaMarcado) {
                  final tiempoMarcado = _tiemposBloqueo[idString];
                  if (tiempoMarcado != null && ahora.difference(tiempoMarcado).inMinutes < 3) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Espera 3 minutos.")));
                    return;
                  }
                }

                // Llamada a la función corregida
                _actualizarEstadoMision(nombreEj, diaNum, !estaMarcado);

                setState(() {
                  item['completado'] = !estaMarcado;
                  if (item['completado']) _tiemposBloqueo[idString] = ahora;
                });
              },
              child: ListTile(
                leading: Icon(
                  (item['completado'] ?? false) ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: (item['completado'] ?? false) ? Colors.green : Colors.grey,
                ),
                title: Text(nombreEj, style: const TextStyle(color: Colors.white)),
                subtitle: Text("${item['series']} series de ${item['repeticiones']} reps"),
              ),
            );
          }).toList(),
        );
      },
    );
  }
 
}