# sliceApp

Aplicación iOS para visualizar, explorar y convertir archivos 3D.

## Funcionalidades

### Explorador de archivos
- Importa archivos 3D desde tu dispositivo
- Formatos soportados: **STL**, **OBJ**, **DAE**, **SCN**, **USDZ**
- Lista de archivos importados con nombre, formato y tamaño
- Elimina archivos con swipe

### Visualizador 3D
- Renderizado con SceneKit e iluminación tipo estudio (key, fill, rim y ambient light)
- Controles táctiles: rotar, zoom y pan
- Materiales con sombreado Phong, specular y doble cara
- Generación automática de normales para archivos que no las incluyen

### Cuadrícula y ejes
- Plano XZ (piso) con cuadrícula adaptativa al tamaño del modelo
- Ejes **X** (rojo), **Y** (verde), **Z** (azul) con etiquetas
- Se puede ocultar/mostrar desde el menú de vista

### Dimensiones
- Barra inferior con las dimensiones del modelo en mm por cada eje
- Se actualiza en tiempo real al redimensionar
- Se puede ocultar/mostrar

### Redimensionar
- Panel con controles independientes por eje (X, Y, Z)
- Slider + botones -/+ para ajustar de 10% a 300%
- Botón de reset para volver al tamaño original
- Las dimensiones reflejan la escala aplicada

### Conversión de formatos
- Convierte entre formatos usando ModelIO de Apple
- OBJ → STL
- STL → OBJ
- DAE/USDZ → STL u OBJ
- Menú de conversión disponible al visualizar un modelo
- Los archivos convertidos se guardan en la app

## Estructura del proyecto

```
sliceApp/
├── sliceAppApp.swift          # Entry point
├── ContentView.swift          # Vista principal
├── FileExplorerView.swift     # Explorador y lista de archivos
├── ModelViewerView.swift      # Visualizador 3D, cuadrícula, dimensiones y escala
├── STLParser.swift            # Parser de STL binario y ASCII
├── STLExporter.swift          # Exportador de SceneKit a STL binario
├── ModelConverter.swift       # Conversión entre formatos con ModelIO
└── Assets.xcassets/           # Assets
```

## Requisitos

- iOS 18+
- Xcode 26+
- Swift 5

## Instalación

1. Clona el repositorio
2. Abre `sliceApp.xcodeproj` en Xcode
3. Selecciona tu dispositivo o simulador
4. Build & Run
