# sliceApp

Aplicación iOS enfocada en la preparación de archivos 3D para impresión en resina. Permite importar, visualizar, redimensionar, orientar, convertir y exportar modelos listos para laminar.

## Funcionalidades

### Explorador de archivos
- Importa archivos 3D desde tu dispositivo (Files, iCloud, etc.)
- Formatos soportados: **STL**, **OBJ**, **DAE**, **SCN**, **USDZ**
- Lista de archivos con nombre, tipo, tamaño y fecha
- Elimina archivos con swipe
- Los archivos se almacenan en el directorio de documentos de la app

### Visualizador 3D
- Renderizado con SceneKit
- Iluminación tipo estudio: key light, fill light, rim light y ambient
- Controles táctiles: rotar, zoom y pan
- Materiales con sombreado Phong, reflejo specular y doble cara
- Generación automática de normales para archivos que no las incluyen
- Modelo posicionado en cuadrante positivo (X+, Y+, Z+) con base en Y=0

### Cuadrícula y ejes
- Cuadrícula XZ (piso) en cuadrante positivo, adaptada al tamaño del modelo
- Ejes coloreados: **X** (rojo), **Y** (verde), **Z** (azul) con etiquetas
- Marcas numéricas a lo largo de cada eje con valores de distancia
- Esfera blanca en el origen (0,0,0)
- Toggle para ocultar/mostrar desde el menú lateral

### Dimensiones
- Barra inferior con dimensiones reales del modelo en mm por eje
- Se actualiza en tiempo real al redimensionar u orientar
- Toggle para ocultar/mostrar

### Redimensionar y guardar
- Panel con controles independientes por eje (X, Y, Z)
- Slider + botones -/+ para ajustar de 10% a 300%
- Botón de reset para volver al tamaño original
- **Guardar cambios**: aplica la escala directamente a los vértices del archivo
  - Recalcula normales con la transpuesta inversa para escalas no uniformes
  - Sobreescribe el archivo original con las nuevas dimensiones

### Orientar base
- Panel con controles de rotación independientes por eje (X, Y, Z)
- Campo de texto para escribir grados exactos
- Botones -/+ que rotan 5° por clic
- **Seleccionar cara como base**: modo interactivo donde tocas una cara del modelo y se resalta la superficie plana completa; al confirmar, el modelo rota para que esa cara quede como base en Y=0
- Los cambios de orientación se guardan automáticamente al archivo

### Conversión de formatos
- Conversión nativa usando ModelIO de Apple
- OBJ → STL | STL → OBJ | DAE/USDZ → STL u OBJ
- Los archivos convertidos se guardan en la app y aparecen en el explorador

### Menú lateral
- Un solo botón (☰) en la esquina superior derecha abre un panel deslizante
- Secciones organizadas: **Vista**, **Editar**, **Convertir**
- Diseñado para escalar con nuevas herramientas

## Estructura del proyecto

```
sliceApp/
├── sliceAppApp.swift          # Entry point
├── ContentView.swift          # Vista principal
├── FileExplorerView.swift     # Explorador, importación y lista de archivos
├── ModelViewerView.swift      # Visualizador 3D, cuadrícula, ejes, dimensiones,
│                              # paneles de escala y orientación, selección de
│                              # cara, guardado y menú lateral
├── STLParser.swift            # Parser de STL binario y ASCII con auto-normales
├── STLExporter.swift          # Exportador de SceneKit a STL binario
├── ModelConverter.swift       # Conversión entre formatos con ModelIO
└── Assets.xcassets/           # Assets
```

## Tecnologías

| Framework | Uso |
|-----------|-----|
| SwiftUI | Interfaz de usuario |
| SceneKit | Renderizado y visualización 3D |
| ModelIO | Conversión entre formatos 3D |
| UniformTypeIdentifiers | Importación de archivos |

## Requisitos

- iOS 18+
- Xcode 26+
- Swift 5

## Instalación

```bash
git clone https://github.com/Isaprez/sliceApp.git
```

1. Abre `sliceApp.xcodeproj` en Xcode
2. Selecciona tu dispositivo o simulador
3. Build & Run

## Roadmap

- [ ] Laminar modelos (slicing) para impresoras de resina
- [ ] Más formatos de conversión
- [ ] Herramientas de edición adicionales
