import 'package:flutter/material.dart';
import 'data_service.dart';


class DetalleRutinaView extends StatelessWidget {
  const DetalleRutinaView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Rutina del Día"),
        backgroundColor: Colors.transparent,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DataService.obtenerDetalleMisiones(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final ejercicios = snapshot.data!;
          
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: ejercicios.length,
            itemBuilder: (context, index) {
              final ej = ejercicios[index];
              return ExpansionTile(
                collapsedBackgroundColor: const Color(0xFF1E1E1E),
                backgroundColor: const Color(0xFF2A2A2A),
                leading: const Icon(Icons.fitness_center, color: Colors.orangeAccent),
                title: Text(
                  ej['nombre'] ?? 'Sin nombre', 
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                ),
                subtitle: Text(
                  "${ej['series'] ?? 0} series x ${ej['repeticiones'] ?? 0} reps", 
                  style: const TextStyle(color: Colors.grey)
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Ejecución Técnica:", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        // Aquí debe decir 'ejecucion_tecnica'
                        Text(ej['ejecucion_tecnica'] ?? "No disponible", style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 15),
                        const Text("Tip Kinesiológico:", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        // Aquí debe decir 'tip'
                        Text(ej['tip'] ?? "Sin consejos", style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}