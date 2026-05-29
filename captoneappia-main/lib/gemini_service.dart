import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  // Tu clave activa de Groq
  static const String _apiKey = String.fromEnvironment('GROQ_API_KEY');

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

      // Formateamos la información detallada de las máquinas para el prompt
      String infoMaquinasText = "";
      for (var maq in maquinasDisponibles) {
        infoMaquinasText += "- Máquina: ${maq['nombre']}\n";
        infoMaquinasText += "  Grupo Muscular: ${maq['grupo_muscular']}\n";
        infoMaquinasText += "  Cómo se usa: ${maq['descripcion']}\n\n";
      }

      // PROMPT PROFESIONAL + RESPUESTA STRUCTURADA JSON
      final prompt = '''
      Eres un entrenador de gimnasio profesional, experto en kinesiología y biomecánica.
      Tu objetivo es diseñar una rutina de entrenamiento personalizada, coherente, segura y adaptada estrictamente al perfil del usuario.
      Debes entregar tu respuesta ÚNICAMENTE en un formato JSON estructurado plano, sin textos extras.

      DATOS DEL USUARIO:
      - Nombre: $nombre
      - Peso: $peso kg | Altura: $altura m
      - Objetivo Principal: $objetivo
      - Nivel de Experiencia: $nivel
      - Frecuencia: $diasDisponibles días a la semana
      - Limitaciones Físicas o Lesiones: $limitaciones

      MÁQUINAS DISPONIBLES EN EL GIMNASIO (Usa SOLO estas máquinas para los ejercicios):
      $infoMaquinasText

      REGLAS DE ORO PARA LA RUTINA (SÉ COHERENTE):
      1. Dosificación del Peso y Carga: 
         - Si el nivel es 'Principiante', enfócate en el aprendizaje técnico. Indica rangos de repeticiones controlados (ej. 12-15) con cargas ligeras a moderadas que prioricen la ejecución.
         - Si el nivel es 'Avanzado', exige mayor intensidad (ej. 8-10 cerca del fallo muscular o RPE alto).
         - NO uses frases genéricas como "levanta mucho". Sé específico con el esfuerzo estimado en el campo de enfoque de carga.
      2. Respetar Limitaciones: Si el usuario tiene una lesión (ej: 'dolor de hombro' o 'problemas de rodilla'), evita ejercicios de esa máquina que fuercen la zona, o añade una nota de cuidado kinésico estricta en los tips.
      3. Formato de Entrega: Organiza la rutina por bloques de Días. Todo tu análisis profesional debe mapearse exactamente en la estructura JSON solicitada abajo.

      ESTRUCTURA OBLIGATORIA DEL JSON:
      Devuelve exclusivamente un objeto JSON válido con la siguiente forma exacta:

      {
        "resumen_general": "Un párrafo motivacional y kinésico corto explicando la estrategia global de este plan de entrenamiento según el objetivo del alumno y sus limitaciones y mostrar los ejercicios que se deben realizar y sus dias.",
        "dias": [
          {
            "dia_numero": 1,
            "enfoque_dia": "Enfoque muscular principal (ej: Pecho y Tríceps)",
            "ejercicios": [
              {
                "nombre_ejercicio": "Nombre exacto de la máquina utilizada",
                "series": "4",
                "repeticiones": "10-12",
                "enfoque_carga": "Explicación específica del esfuerzo/peso sugerido según su nivel",
                "tip_kinesico": "Tip breve de ejecución basado en kinesiología y la descripción de uso de la máquina"
              }
            ]
          }
        ]
      }

      REGLA CRÍTICA: No incluyas introducciones, ni saludos, ni explicaciones en Markdown (prohibido usar ```json). Solo devuelve el string del JSON puro.
      ''';

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'llama-3.3-70b-versatile',
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.4, // Un pelito más de margen para que fluya su conocimiento kinésico, pero manteniendo el orden
          'response_format': {'type': 'json_object'} 
        }),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
        final stringRutina = jsonResponse['choices'][0]['message']['content'];
        return stringRutina;
      } else {
        print("Error de Groq: ${response.statusCode} - ${response.body}");
        return "Error al procesar la rutina (Código: ${response.statusCode})";
      }
    } catch (e) {
      print("Error en la conexión: $e");
      return "Hubo un error al conectar con el entrenador de IA.";
    }
  }
}