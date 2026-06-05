import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GeminiService {
  
  // Getter seguro para obtener la llave desde el archivo .env
  String get _apiKey => dotenv.env['GROQ_API_KEY'] ?? '';

  Future<String> generarRutinaIA({
    required String nombre,
    required double peso,
    required double altura,
    required String objetivo,
    required String nivel,
    required int diasDisponibles,
    required String limitaciones,
    required List<Map<String, String>> maquinasDisponibles,
  }) async {
    try {
      final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');

      String infoMaquinasText = "";
      for (var maq in maquinasDisponibles) {
        infoMaquinasText += "- Máquina: ${maq['nombre']}\n";
        infoMaquinasText += "  Grupo Muscular: ${maq['grupo_muscular'] ?? 'General'}\n";
        infoMaquinasText += "  Cómo se usa/Descripción: ${maq['descripcion'] ?? 'Uso estándar'}\n\n";
      }

      final prompt = '''
        Eres un entrenador de gimnasio profesional, experto en kinesiología y biomecánica.
        Tu objetivo es diseñar una rutina de entrenamiento altamente profesional y pedagógica.
        "Para cada ejercicio, incluye obligatoriamente el campo 'ejecucion_tecnica' con una explicación breve de cómo realizarlo."

        DATOS DEL USUARIO:
        - Nombre: $nombre
        - Peso: $peso kg | Altura: $altura m
        - Objetivo Principal: $objetivo
        - Nivel de Experiencia: $nivel
        - Frecuencia: $diasDisponibles días a la semana
        - Limitaciones Físicas o Lesiones: $limitaciones

        MÁQUINAS DISPONIBLES EN EL GIMNASIO (Usa SOLO estas máquinas):
        $infoMaquinasText

        REGLAS DE ORO:
        1. Genera exactamente $diasDisponibles días de entrenamiento independientes.
        2. Cada ejercicio DEBE incluir una guía paso a paso de ejecución técnica para evitar lesiones.
        3. El "tip_kinesico" debe enfocarse en la conexión mente-músculo y activación.

        ESTRUCTURA OBLIGATORIA DEL JSON:
        {
          "resumen_general": "Un párrafo motivacional explicando la estrategia global.",
          "dias": [
            {
              "dia_numero": 1,
              "enfoque_dia": "Nombre del enfoque",
              "ejercicios": [
                {
                  "nombre_ejercicio": "Nombre de la máquina",
                  "series": "3",
                  "repeticiones": "10-12",
                  "enfoque_carga": "Explicación del peso sugerido",
                  "ejecucion_correcta": "1. Posición inicial detallada. 2. Fase concéntrica. 3. Fase excéntrica.",
                  "tip_kinesico": "Consejo experto sobre biomecánica o respiración"
                }
              ]
            }
          ]
        }
        ''';

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'llama-3.3-70b-versatile',
          'messages': [{'role': 'user', 'content': prompt}],
          'temperature': 0.4,
          'response_format': {'type': 'json_object'} 
        }),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
        return jsonResponse['choices'][0]['message']['content'];
      } else {
        print("Error de Groq: ${response.statusCode} - ${response.body}");
        return _jsonPorDefecto();
      }
    } catch (e) {
      print("Error en la conexión: $e");
      return _jsonPorDefecto();
    }
  }

  String _jsonPorDefecto() {
    return jsonEncode({
      "resumen_general": "Un párrafo motivacional explicando la estrategia global.",
      "dias": [{
          "dia_numero": 1,
          "enfoque_dia": "Nombre del enfoque",
          "ejercicios": [{
              "nombre_ejercicio": "Nombre de la máquina",
              "series": "3",
              "repeticiones": "10-12",
              "enfoque_carga": "Explicación del peso sugerido",
              "ejecucion_correcta": "1. Posición inicial detallada. 2. Fase concéntrica. 3. Fase excéntrica.",
              "tip_kinesico": "Consejo experto sobre biomecánica o respiración"
            }]
        }]
    });
  }

  Future<String> analizarRendimiento(String datosRendimiento) async {
    final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');

    final prompt = '''
      Eres un entrenador profesional. Analiza el rendimiento del usuario y su cumplimiento de la rutina.
      Datos: $datosRendimiento
      Responde con un feedback motivador y técnico breve.
    ''';

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'model': 'llama-3.3-70b-versatile',
        'messages': [{'role': 'user', 'content': prompt}],
        'temperature': 0.4,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['choices'][0]['message']['content'];
    } else {
      return "Buen trabajo hoy, sigue así.";
    }
  }

  Future<String> analizarProgresoMensual(String datosComparativos, double pesoActual) async {
    final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');
    final Map<String, dynamic> datos = jsonDecode(datosComparativos);

    final historial = datos['historial'] ?? 'Sin historial';
    final pesoInicial = datos['peso'] ?? pesoActual;

    final prompt = '''
      Eres un entrenador de élite y especialista en kinesiología. Analiza este historial de ejercicios: $historial. 
      Analiza la evolución del usuario en los últimos 30 días basándote en estos datos: $datosComparativos.
      Peso al iniciar el ciclo: $pesoInicial kg
      Peso actual: $pesoActual kg.
      Tu respuesta DEBE ser un reporte profesional estructurado:
      1. RESUMEN DE PROGRESO: Analiza su evolución en volumen de entrenamiento.
      2. ANÁLISIS DE RENDIMIENTO: Comenta sobre el volumen y la variedad.
      3. RECOMENDACIONES TÉCNICAS: Sugiere 2 ajustes específicos.
      4. MENSAJE MOTIVACIONAL: Directo, empoderador y profesional.
    ''';

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'model': 'llama-3.3-70b-versatile',
        'messages': [{'role': 'user', 'content': prompt}],
        'temperature': 0.4,
      }),
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
      return jsonResponse['choices'][0]['message']['content'];
    } else {
      print("Error en análisis mensual: ${response.statusCode}");
      return "Has completado un ciclo importante. ¡Prepárate para el siguiente nivel!";
    }
  }
}