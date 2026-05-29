import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PerfilFormView extends StatefulWidget {
  final Map<String, dynamic>? datosActuales;

  const PerfilFormView({Key? key, this.datosActuales}) : super(key: key);

  @override
  _PerfilFormViewState createState() => _PerfilFormViewState();
}

class _PerfilFormViewState extends State<PerfilFormView> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false; 
  
  late TextEditingController _nombreController;
  late TextEditingController _limitacionesController;
  late TextEditingController _pesoController;
  late TextEditingController _alturaController;
  
  String _objetivoSelected = 'Ganar Masa Muscular';
  String _nivelSelected = 'Principiante';
  int _diasSelected = 3;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.datosActuales?['nombre'] ?? '');
    _limitacionesController = TextEditingController(text: widget.datosActuales?['limitaciones'] ?? '');
    _pesoController = TextEditingController(text: widget.datosActuales?['peso']?.toString() ?? '');
    _alturaController = TextEditingController(text: widget.datosActuales?['altura']?.toString() ?? '');

    if (widget.datosActuales != null) {
      _objetivoSelected = widget.datosActuales?['meta'] ?? 'Ganar Masa Muscular';
      _nivelSelected = widget.datosActuales?['nivel'] ?? 'Principiante';
      _diasSelected = widget.datosActuales?['dias_disponibles'] ?? 3;
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _limitacionesController.dispose();
    _pesoController.dispose();
    _alturaController.dispose();
    super.dispose();
  }

  void _guardarPerfil() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _loading = true);
      
      // ID de usuario manual para las pruebas (Simulando usuario ID: 1)
      final int idUsuarioPrueba = 1; 

      final datosPerfil = {
        'id': idUsuarioPrueba,
        'nombre': _nombreController.text.trim(),
        'meta': _objetivoSelected,
        'nivel': _nivelSelected,
        'dias_disponibles': _diasSelected,
        'limitaciones': _limitacionesController.text.trim(),
        'peso': double.tryParse(_pesoController.text.trim()) ?? 0.0,
        'altura': double.tryParse(_alturaController.text.trim()) ?? 0.0,
      };

      try {
        await Supabase.instance.client
            .from('perfiles')
            .upsert(datosPerfil);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ ¡Perfil actualizado en Supabase!"), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true); 
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error al guardar: $e"), backgroundColor: Colors.red),
        );
      } finally {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.datosActuales == null ? "Completar Perfil" : "Editar Perfil"),
        backgroundColor: Colors.blueGrey[900],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(labelText: 'Nombre o Apodo', border: OutlineInputBorder()),
                validator: (value) => value!.isEmpty ? 'Por favor ingresa tu nombre' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _pesoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Peso (kg)', hintText: 'Ej: 75.5', border: OutlineInputBorder()),
                validator: (value) => value!.isEmpty ? 'Ingresa tu peso' : null,
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _alturaController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Altura (metros)', hintText: 'Ej: 1.75', border: OutlineInputBorder()),
                validator: (value) => value!.isEmpty ? 'Ingresa tu altura' : null,
              ),
              const SizedBox(height: 16),
              
              DropdownButtonFormField<String>(
                value: _objetivoSelected,
                decoration: const InputDecoration(labelText: 'Objetivo de Entrenamiento', border: OutlineInputBorder()),
                items: ['Ganar Masa Muscular', 'Perder Peso', 'Resistencia', 'Salud/Cardio'].map((String value) {
                  return DropdownMenuItem<String>(value: value, child: Text(value));
                }).toList(),
                onChanged: (val) => setState(() => _objetivoSelected = val!),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _nivelSelected,
                decoration: const InputDecoration(labelText: 'Nivel de Experiencia', border: OutlineInputBorder()),
                items: ['Principiante', 'Intermedio', 'Avanzado'].map((String value) {
                  return DropdownMenuItem<String>(value: value, child: Text(value));
                }).toList(),
                onChanged: (val) => setState(() => _nivelSelected = val!),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<int>(
                value: _diasSelected,
                decoration: const InputDecoration(labelText: 'Días disponibles a la semana', border: OutlineInputBorder()),
                items: [2, 3, 4, 5, 6].map((int value) {
                  return DropdownMenuItem<int>(value: value, child: Text("$value días"));
                }).toList(),
                onChanged: (val) => setState(() => _diasSelected = val!),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _limitacionesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '¿Lesiones o limitaciones médicas?',
                  hintText: 'Ej: Dolor en rodilla derecha, hernia, ninguna.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _loading ? null : _guardarPerfil,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _loading 
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text("GUARDAR DATOS", style: TextStyle(fontSize: 16, color: Colors.white)),
              )
            ],
          ),
        ),
      ),
    );
  }
}