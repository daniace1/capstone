import 'dart:convert';
import 'package:ironlens/gemini_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DataService {
  static final _supabase = Supabase.instance.client;
  static Future<int> obtenerDiaActual() async {
    // Aquí tu lógica para obtener el día
    return 1; // O lo que corresponda
  }


  static Future<void> verificarCambioDeDia() async {
    final _supabase = Supabase.instance.client;
    final ahora = DateTime.now();
    
    // Obtenemos los datos del perfil
    final perfil = await _supabase
        .from('perfiles')
        .select('dia_actual_rutina, ultima_fecha_conexion')
        .eq('id', 1)
        .single();
    
    final String ultimaFechaStr = perfil['ultima_fecha_conexion'] ?? ahora.toIso8601String();
    DateTime fechaUltima = DateTime.parse(ultimaFechaStr);
    
    // Si hoy es un día distinto (diferente día del mes o año)
    if (ahora.day != fechaUltima.day || ahora.month != fechaUltima.month || ahora.year != fechaUltima.year) {
      int diaActual = perfil['dia_actual_rutina'] ?? 1;
      // Si llega a 3, vuelve a 1, si no, incrementa
      int nuevoDia = (diaActual >= 3) ? 1 : diaActual + 1;
      
      await _supabase.from('perfiles').update({
        'dia_actual_rutina': nuevoDia,
        'ultima_fecha_conexion': ahora.toIso8601String()
      }).eq('id', 1);
    }
  }

  Future<int> _obtenerDiaActual() async {
    final perfil = await _supabase.from('perfiles').select('dia_actual_rutina').eq('id', 1).single();
    return perfil['dia_actual_rutina'] ?? 1;
  }

  static Future<List<Map<String, dynamic>>> obtenerDetalleMisiones() async {
    final String hoy = DateTime.now().toIso8601String().split('T')[0];
    try {
      // 1. Obtenemos el perfil para saber qué día le toca hoy
      // Asegúrate de que esta columna exista en tu tabla 'perfiles'
      final perfil = await _supabase
          .from('perfiles')
          .select('dia_actual_rutina')
          .eq('id', 1)
          .maybeSingle();
      
      final int diaTocaHoy = perfil?['dia_actual_rutina'] ?? 1;

      // 2. Obtenemos la rutina
      final rutina = await _supabase
          .from('rutinas')
          .select('contenido_rutina')
          .eq('usuario_id', 1)
          .maybeSingle();

      if (rutina == null || rutina['contenido_rutina'] == null) return [];

      // Procesamiento seguro del JSON
      final dynamic rawData = jsonDecode(rutina['contenido_rutina']);
      final Map data = (rawData is Map) ? rawData : {};
      final List<dynamic> dias = data['dias'] ?? [];

      // 3. Buscamos el día específico
      final diaActual = dias.firstWhere(
        (d) => d['dia_numero'] == diaTocaHoy, 
        orElse: () => null
      );

      if (diaActual == null) return [];

      // 4. Traer completados (protegido contra nulos)
      final List<dynamic> ejerciciosHoy = diaActual['ejercicios'] ?? [];
      final completados = await _supabase
          .from('historial_misiones')
          .select('nombre_ejercicio')
          .eq('usuario_id', 1)
          .eq('dia_numero', diaTocaHoy)
          .gte('fecha_completada', hoy);

      List<String> listaCompletados = (completados as List)
          .map((e) => (e['nombre_ejercicio'] ?? '').toString())
          .toList();

      // 5. Retorno blindado (evita pantalla roja)
      return ejerciciosHoy.map((ej) {
        String nombre = (ej['nombre_ejercicio'] ?? 'Ejercicio').toString();
        return {
          // Si no tienes un ID único en el JSON, usa el nombre como ID
          'id': (ej['id_ejercicio'] is int) ? ej['id_ejercicio'] : 0, 
          'nombre': (ej['nombre_ejercicio'] ?? 'Ejercicio').toString(),
          'series': (ej['series'] ?? '0').toString(),
          'repeticiones': (ej['repeticiones'] ?? '0').toString(),
          'ejecucion_tecnica': (ej['ejecucion_tecnica'] ?? "No disponible").toString(),
          'tip': (ej['tip_kinesico'] ?? 'Sin consejos').toString(),
          'completado': listaCompletados.contains(nombre)
        };
      }).toList();
      
    } catch (e) {
      print("Error crítico en DataService: $e");
      return [];
    }
  }

  static Future<Map<String, dynamic>> prepararDatosParaAnalisis() async {
    final supabase = Supabase.instance.client;
    final planTotal = await supabase.from('ejercicios').select('nombre_ejercicio').eq('usuario_id', 1);
    final String hoy = DateTime.now().toIso8601String().split('T')[0];
    final historialHoy = await supabase.from('historial_misiones').select('nombre_ejercicio').eq('usuario_id', 1).gte('fecha_completada', hoy);

    List<String> nombresCompletados = (historialHoy as List).map((e) => e['nombre_ejercicio'].toString()).toList();
    List<Map<String, dynamic>> rutinaAnalizada = (planTotal as List).map((ejercicio) {
      return {
        "ejercicio": ejercicio['nombre_ejercicio'],
        "completado": nombresCompletados.contains(ejercicio['nombre_ejercicio'])
      };
    }).toList();

    return {
      "usuario": {"nombre": "Josepepe", "peso": 100, "meta": "Resistencia"},
      "rendimiento_hoy": rutinaAnalizada,
      "total_misiones": planTotal.length,
      "completadas": nombresCompletados.length
    };
  }

  // 2. NUEVA: Para guardar la rutina que te manda la IA (Llamar al recibir el JSON de la IA)
  static Future<void> procesarYGuardarRutinaIA(Map<String, dynamic> jsonIA, int usuarioId) async {
    print("DEBUG: Entrando a guardar rutina...");
    try{
      final supabase = Supabase.instance.client;
      await supabase.from('ejercicios').delete().eq('usuario_id', usuarioId); // Limpia lo anterior
      print("DEBUG: Rutina anterior borrada. Iniciando inserción...");
      final String hoy = DateTime.now().toIso8601String().split('T')[0];
        await supabase.from('historial_misiones')
            .delete()
            .eq('usuario_id', usuarioId)
            .gte('fecha_completada', hoy);


      print("JSON RECIBIDO: $jsonIA");

      for (var dia in jsonIA['dias']) {
        for (var ej in dia['ejercicios']) {
          try {
            await supabase.from('ejercicios').insert({
              'usuario_id': usuarioId,
              'dia_numero': dia['dia_numero'],
              'nombre_ejercicio': ej['nombre_ejercicio'],
              'series': ej['series'].toString(),
              'repeticiones': ej['repeticiones'].toString(),
              'ejecucion_tecnica': ej['ejecucion_tecnica'],
              'tip_kinesico': ej['tip_kinesico'],
            });
            print("Éxito al guardar: ${ej['nombre_ejercicio']}");
          } catch (e) {
            print("ERROR AL GUARDAR EJERCICIO: $e"); // Esto te dirá exactamente por qué falla
          }
        }
      }
    } catch(e){print("DEBUG CRÍTICO: Ocurrió un error: $e");}
  }
  // 3. NUEVA: Para ejecutar el análisis automático (Llamar para obtener el reporte final)
  static Future<String> ejecutarAnalisisAutomatico(int usuarioId) async {
    final supabase = Supabase.instance.client;
    
    // A. Preparar datos
    final datos = await prepararDatosParaAnalisis(); 

    // B. Invocar a TU clase GeminiService (que usa Groq)
    // Convertimos el Map a String para enviárselo a la IA
    final String jsonDatos = jsonEncode(datos); 
    
    // Aquí usamos tu lógica existente. 
    // OJO: Tendrás que crear un método en GeminiService para esto o usar uno existente.
    final resultadoIA = await GeminiService().analizarRendimiento(jsonDatos);

    // C. Guardar
    await supabase.from('analisis').insert({
      'usuario_id': usuarioId,
      'contenido': resultadoIA,
      'created_at': DateTime.now().toIso8601String(),
    });
    
    return resultadoIA;
  }

  static Future<String> generarReporteProgresoMensual(int usuarioId, Map<String, dynamic> nuevosDatos,double pesoActual) async {
    final supabase = Supabase.instance.client;

    // 1. Obtener datos del perfil guardados hace ~30 días
    final perfilAnterior = await supabase.from('perfiles').select('*').eq('id', usuarioId).single();

    // 2. Obtener resumen de misiones del último mes
    final fechaHaceUnMes = DateTime.now().subtract(Duration(days: 30)).toIso8601String();
    final historialMes = await supabase
        .from('historial_misiones')
        .select('nombre_ejercicio')
        .eq('usuario_id', usuarioId)
        .gte('fecha_completada', fechaHaceUnMes);

    // 3. Crear el JSON de comparación para la IA
    final datosParaComparar = {
      "perfil_inicial": perfilAnterior,
      "datos_actuales": nuevosDatos, // Peso, altura, nuevas medidas que el usuario ingresa
      "historial_mensual": historialMes.length,
      "mensaje_usuario": "Compara el progreso y sugiere ajustes para el próximo ciclo."
    };

    // 4. Llamar a Groq con el peso incluido
    final resultadoIA = await GeminiService().analizarProgresoMensual(
      jsonEncode(datosParaComparar), 
      pesoActual // <--- Este es el segundo argumento que te falta
    );
    // 5. Guardar el reporte en una tabla 'reportes_mensuales'
    await supabase.from('reportes_mensuales').insert({
      'usuario_id': usuarioId,
      'contenido': resultadoIA,
      'fecha_reporte': DateTime.now().toIso8601String(),
    });

    return resultadoIA;
  }

  
  static Future<void> registrarPeso(int usuarioId, double peso) async {
    try {
      await Supabase.instance.client
          .from('historial_peso')
          .insert({
            'usuario_id': usuarioId,
            'peso': peso,
            'fecha': DateTime.now().toIso8601String(),
          });
      print("✅ Registro insertado correctamente");
    } catch (e) {
      print("❌ ERROR EN REGISTRAR PESO: $e");
    }
  }
  

  static Future<Map<String, dynamic>> obtenerAnalisisMensual(String usuarioId, double pesoActual) async {
    final supabase = Supabase.instance.client;
    final haceUnMes = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();

    // Consultas paralelas
    final datosFuture = supabase.from('historial_misiones')
        .select('nombre_ejercicio, fecha_completada')
        .eq('usuario_id', usuarioId)
        .gte('fecha_completada', haceUnMes);

    final historialFuture = supabase.from('historial_peso')
        .select('peso')
        .eq('usuario_id', int.parse(usuarioId))
        .order('fecha', ascending: true)
        .limit(1)
        .maybeSingle();

    final resultados = await Future.wait<dynamic>([datosFuture, historialFuture]);
    final datos = resultados[0] as List<dynamic>;
    final historial = resultados[1] as Map<String, dynamic>?;

    final double pesoInicial = (historial?['peso'] as num?)?.toDouble() ?? pesoActual;
    final metricas = procesarMetricas(datos);

    final Map<String, dynamic> objetoParaIA = {
      "historial": metricas,
      "peso_actual": pesoActual,
      "peso_inicial": pesoInicial,
    };

    final resultadoIA = await GeminiService().analizarProgresoMensual(
      jsonEncode(objetoParaIA), 
      pesoActual // <--- Este es el segundo argumento que te falta
    );

    return {"analisis": resultadoIA};
  }

  static Map<String, dynamic> procesarMetricas(List<dynamic> datos) {
    int totalEjercicios = datos.length;
    
    // Contamos cuántas veces se repite cada ejercicio
    Map<String, int> frecuenciaEjercicios = {};
    for (var registro in datos) {
      String nombre = registro['nombre_ejercicio'];
      frecuenciaEjercicios[nombre] = (frecuenciaEjercicios[nombre] ?? 0) + 1;
    }

    // Identificamos el favorito
    String favorito = frecuenciaEjercicios.entries
        .reduce((a, b) => a.value > b.value ? a : b).key;

    return {
      'total_completados': totalEjercicios,
      'ejercicio_favorito': favorito,
      'detalle_frecuencia': frecuenciaEjercicios
    };
  }

  static Future<Map<String, dynamic>> prepararReporteParaIA(String usuarioId) async {
    final haceUnMes = DateTime.now().subtract(const Duration(days: 30));
    
    // 1. Obtenemos datos crudos
    final datos = await Supabase.instance.client
        .from('historial_misiones')
        .select('nombre_ejercicio, fecha_completada, dia_numero')
        .eq('usuario_id', usuarioId)
        .gte('fecha_completada', haceUnMes.toIso8601String());

    // 2. Procesamos métricas clave
    int totalEntrenamientos = datos.length;
    Set<int> diasUnicos = datos.map((d) => d['dia_numero'] as int).toSet();
    
    Map<String, int> frecuencia = {};
    for (var d in datos) {
      String nombre = d['nombre_ejercicio'];
      frecuencia[nombre] = (frecuencia[nombre] ?? 0) + 1;
    }

    // 3. Retornamos un objeto listo para el prompt de la IA
    return {
      'total_ejercicios_completados': totalEntrenamientos,
      'dias_activos_diferentes': diasUnicos.length,
      'frecuencia_ejercicios': frecuencia,
      'periodo_analizado': "Últimos 30 días"
    };
  }

  




  static Future<void> simular20DiasDeDatos(String? usuarioId) async {
    final String idFinal = (usuarioId == null || usuarioId.isEmpty) ? "1" : usuarioId;
    final int? idConvertido = int.tryParse(idFinal);
    if (idConvertido == null) return;

    final supabase = Supabase.instance.client;
    
    // 1. Limpiamos solo los datos del usuario para empezar de cero
    await supabase.from('historial_misiones').delete().eq('usuario_id', idConvertido);

    // 2. Insertamos datos únicos
    for (int i = 0; i < 25; i++) {
      final fechaSimulada = DateTime.now().subtract(Duration(days: i));
      
      // Cambiamos el ejercicio para que no choque con el constraint
      // Usamos el índice i para que el nombre del ejercicio sea único en cada iteración
      String ejercicio = i % 2 == 0 ? 'Press Banca $i' : 'Leg Curl $i';
      
      await supabase.from('historial_misiones').insert({
        'usuario_id': idConvertido,
        'nombre_ejercicio': ejercicio, 
        'fecha_completada': fechaSimulada.toIso8601String(),
        'dia_numero': (i % 3) + 1, 
      });
    }
    print("¡Datos insertados con éxito! Ya puedes ir a Perfil.");
  }

}