# ShotMap

[![Última versión](https://img.shields.io/github/v/release/ixiehao/ShotMap?display_name=tag&label=release&color=2563eb)](https://github.com/ixiehao/ShotMap/releases/latest)
[![Verificación](https://img.shields.io/github/actions/workflow/status/ixiehao/ShotMap/ci.yml?branch=main&label=verify)](https://github.com/ixiehao/ShotMap/actions/workflows/ci.yml)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111827?logo=apple)](https://github.com/ixiehao/ShotMap/releases/latest)
[![Licencia MIT](https://img.shields.io/badge/license-MIT-059669)](LICENSE)

[English](README.md) · [简体中文](README.zh-CN.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [Español](README.es.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

**La app está disponible en 7 idiomas:** English · 简体中文 · Français · Русский · Español · 日本語 · 한국어. Todos incluidos en una sola descarga.

![Interfaz en inglés de ShotMap creando un mosaico a partir de Tears of Steel](website/assets/workspace-en.webp?v=20261017)

*El ejemplo muestra la interfaz en inglés. La app también está disponible en español.*

## Tus vídeos, más fáciles de encontrar.

Una carpeta puede guardar años de vídeos familiares, viajes y momentos cotidianos. Pero un nombre de archivo o una miniatura rara vez basta para encontrar el vídeo que buscas. **ShotMap** reúne momentos de cada vídeo en un mosaico de imágenes para que puedas reconocer las escenas sin reproducir los archivos uno por uno.

Empieza con **Selección auto** y sustituye los fotogramas que quieras en **Elegir fotogramas**. ShotMap es una app nativa para macOS y de código abierto. El procesamiento y la exportación se realizan en tu Mac, sin cuenta ni subida de vídeos a internet.

> **Empieza aquí:** [Descargar la última versión internacional](https://github.com/ixiehao/ShotMap/releases/latest) · DMG universal · macOS 13 o posterior · Apple Silicon e Intel

> **Vídeo de demostración:** *Tears of Steel* (2012) © Blender Foundation / Blender Institute, con licencia [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). Las capturas y la animación usan este vídeo.

## Para esos momentos que quieres volver a encontrar

- **Recuerdos personales y familiares:** localiza un cumpleaños, un viaje, una puesta de sol o los primeros pasos de un niño sin abrir cada archivo.
- **Creación y edición:** revisa un lote de vídeos antes de elegir el material que llevarás a tu programa de edición.
- **Organización de carpetas:** guarda un mosaico junto a cada vídeo original y añade marcas de tiempo y nombres de archivo si los necesitas.

## Del vídeo al mosaico en tres pasos

| 1. Añade vídeos | 2. Elige los momentos | 3. Guarda el mosaico |
| --- | --- | --- |
| Arrastra un vídeo o añade varios a la cola. | Usa Selección auto y ajusta los fotogramas a mano. | Exporta un PNG o JPG junto al vídeo original. |

## Elige las imágenes y su presentación

- Intenta priorizar imágenes nítidas y variadas, reduciendo los fotogramas negros, borrosos o casi idénticos.
- Reúne reproductor, línea de tiempo, avance por fotogramas y galería en **Elegir fotogramas**.
- Procesa varios vídeos seguidos, permite pausar tras el vídeo actual y reanudar después, y completa la vista previa a medida que obtiene las imágenes.
- Ofrece cuadrículas de 3 × 3 a 8 × 8, proporción, color de fondo, anchura de imagen, marcas de tiempo y nombre del archivo.
- Admite MP4, MOV, MPEG y otros formatos compatibles con macOS.
- Permite cambiar entre siete idiomas sin reiniciar. Puedes usar la apariencia clara, oscura o del sistema.

### Mira cómo funciona

Esta grabación muestra el paso de un mosaico terminado a la selección manual. Puedes localizar un momento en la línea de tiempo, elegir otra imagen en la galería y guardar el resultado.

![ShotMap pasa del mosaico de Tears of Steel a la selección manual de fotogramas, con línea de tiempo y galería](docs/assets/video-to-storyboard-demo.gif?v=tears-20261016)

## Descargar e instalar

Abre la [última versión internacional](https://github.com/ixiehao/ShotMap/releases/latest), descarga el `.dmg` universal y arrastra **ShotMap.app** a **Aplicaciones**. El mismo instalador incluye los siete idiomas y funciona en Mac con Apple Silicon e Intel.

La página de la versión incluye una suma de comprobación SHA-256 para verificar la descarga. ShotMap aún no está notarizado por Apple. Si macOS pide confirmar el desarrollador, haz clic con la tecla Control pulsada en la app dentro de Aplicaciones, elige **Abrir** y vuelve a confirmar con **Abrir**. No necesitas reducir la seguridad del sistema.

### Elegir el idioma

Usa el menú de idiomas de la esquina superior derecha para cambiar al instante, sin reiniciar ni vaciar la cola. Al abrirse por primera vez, ShotMap usa el idioma del sistema si está disponible; en caso contrario, usa inglés. Después recuerda tu elección.

## Tus vídeos se quedan en tu Mac

ShotMap no requiere cuenta, no hace seguimiento ni sube vídeos a la nube. Tampoco incluye Electron, FFmpeg ni un entorno de ejecución de Python. La comprobación opcional de actualizaciones solo consulta información pública de las versiones de GitHub; nunca envía vídeos ni datos de uso.

## Ayuda, comentarios y comunidad

- **¿Es tu primera vez con ShotMap?** Visita la [web oficial](https://ixiehao.github.io/ShotMap/es/) para ver una presentación breve y capturas reales.
- **¿Necesitas ayuda, has encontrado un fallo o tienes una idea?** Consulta [Soporte](SUPPORT.md) y usa un [formulario de incidencias](https://github.com/ixiehao/ShotMap/issues/new/choose) para errores reproducibles y propuestas concretas.
- **¿Quieres preguntar o compartir tu experiencia?** Participa en [GitHub Discussions](https://github.com/ixiehao/ShotMap/discussions).
- **¿Quieres colaborar?** Lee [CONTRIBUTING.md](CONTRIBUTING.md). Comunica los problemas de seguridad mediante el [canal privado](https://github.com/ixiehao/ShotMap/security/advisories/new).
- **Información del proyecto:** [CHANGELOG.md](CHANGELOG.md) · [PRIVACY.md](PRIVACY.md) · [Desarrollador: ixiehao](https://github.com/ixiehao)

## Derechos y licencias

- El código Swift, la documentación y el icono Iris son creaciones originales del proyecto, publicadas bajo la [licencia MIT](LICENSE).
- La app solo usa frameworks de los SDK de Apple. No incluye código de aplicaciones de terceros, paquetes, SDK de análisis ni recursos de MoviePrint.
- Los SVG de [Tabler Icons Outline](https://github.com/tabler/tabler-icons) se usan sin modificar bajo la [licencia MIT](ThirdPartyLicenses/TablerIcons-MIT.txt). La fuente Noto Sans CJK incluida usa la [SIL Open Font License 1.1](ThirdPartyLicenses/NotoSansCJK-OFL-1.1.txt). Consulta [NOTICE.md](NOTICE.md).
- El vídeo de demostración es *Tears of Steel* (2012) © Blender Foundation / Blender Institute, con licencia [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/).
- Procesa solo vídeos que te pertenezcan o que tengas autorización para analizar. Crear un mosaico no concede derechos para publicar ni redistribuir el vídeo original.

## Documentación de desarrollo

[Índice](docs/README.md) · [Desarrollo y validación](docs/DEVELOPMENT.md) · [Mantenimiento de la web](docs/WEBSITE.md).

El código de la web oficial está en `website/`; `docs/` contiene la documentación de mantenimiento.
