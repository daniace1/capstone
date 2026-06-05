import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DetalleMaquinaView extends StatelessWidget {
  final Map maquina; // Aquí recibes los datos de la máquina
  final double? confianza;

  const DetalleMaquinaView({super.key, required this.maquina, this.confianza});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(maquina['nombre'] ?? "Detalle")),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Mostramos la imagen de la URL que vendrá de Supabase
            Image.network(
              maquina['image_url'] ?? 'https://via.placeholder.com/300', 
              height: 250,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => 
                  const Icon(Icons.fitness_center, size: 100),
            ),
            
            const SizedBox(height: 10), // Un pequeño espacio tras la imagen
            if (confianza != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  "Certeza de detección: ${(confianza! * 100).toStringAsFixed(1)}%",
                  style: const TextStyle(
                    color: Colors.amber, 
                    fontWeight: FontWeight.bold,
                    fontSize: 14
                  ),
                ),
              ),
            const SizedBox(height: 10),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Grupo Muscular: ${maquina['grupo_muscular']}",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(maquina['descripcion'] ?? "Sin descripción disponible."),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save, color: Colors.white),
                    label: const Text("GUARDAR MÁQUINA INVENTARIO", style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                    ),
                    onPressed: () async {
                      // 1. Forzamos el ID de prueba manual 1
                      final int idUsuarioPrueba = 1; 
                      
                      try {
                        // 2. Intentamos insertar en el historial al presionar el botón
                        await Supabase.instance.client.from('historial_detecciones').insert({
                          'usuario_id': idUsuarioPrueba, 
                          'maquina_id': maquina['id'], // 'widget.maquina' o 'maquina' según como recibas la variable
                        });
                        
                        // 🟢 AVISO DE ÉXITO TRAS APRETAR EL BOTÓN
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("✨ ¡'${maquina['nombre']}' añadida con éxito a tu inventario!"),
                            backgroundColor: Colors.green[700],
                            duration: const Duration(seconds: 3),
                          ),
                        );

                      } catch (error) {
                        // 🟢 AVISO DE DUPLICADO TRAS APRETAR EL BOTÓN
                        print("Error por duplicado: $error");
                        
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("⚠️ La máquina '${maquina['nombre']}' ya la tenías en tu lista."),
                            backgroundColor: Colors.orange[800],
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    },
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}